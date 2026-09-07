#!/usr/bin/env python3
"""Linux: measure a Keila session without timing hooks in the TUI loop."""

import argparse
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import tempfile
import time


def parse_stat(text):
    # comm can contain spaces and parentheses. Fields after its last ')' start
    # at field 3 (state); CPU fields 14/15 exclude waited-for children.
    prefix, _, suffix = text.rpartition(')')
    fields = suffix.split()
    return (prefix.split('(', 1)[1], int(fields[19]),
            int(fields[11]) + int(fields[12]))


def tree_sample(pid):
    """Sample own CPU and RSS; never attribute child CPU twice to Bash."""
    pending, seen, rows = [pid], set(), []
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        try:
            root = Path('/proc') / str(current)
            pending.extend(int(child) for child in
                           (root / 'task' / str(current) / 'children').read_text().split())
            pages = int((root / 'statm').read_text().split()[1])
            name, birth, ticks = parse_stat((root / 'stat').read_text())
        except (OSError, ValueError, IndexError):
            continue
        rows.append((current, birth, name, ticks, pages * os.sysconf('SC_PAGE_SIZE')))
    return rows


def process_group(pid, root_pid, name):
    if pid == root_pid:
        return 'Keila (Bash principal)'
    if name in ('bash', 'sh'):
        return 'Bash auxiliares'
    if name in ('mpv', 'ffmpeg', 'parec', 'od', 'jq', 'socat', 'mv', 'curl', 'tput'):
        return name
    return 'Otros auxiliares'


class ProcessTotals:
    def __init__(self):
        self.previous = {}
        self.groups = {}
        self.samples = 0

    def add(self, rows, root_pid):
        self.samples += 1
        memory = {}
        for pid, birth, name, ticks, rss in rows:
            identity = (pid, birth)  # PID reuse must not inherit an old counter.
            group = process_group(pid, root_pid, name)
            totals = self.groups.setdefault(group, {'ticks': 0, 'rss_sum': 0, 'rss_peak': 0})
            totals['ticks'] += max(0, ticks - self.previous.get(identity, 0))
            self.previous[identity] = ticks
            memory[group] = memory.get(group, 0) + rss
        for group, rss in memory.items():
            self.groups[group]['rss_sum'] += rss
            self.groups[group]['rss_peak'] = max(self.groups[group]['rss_peak'], rss)

    def report(self, elapsed):
        hz = os.sysconf('SC_CLK_TCK')
        return [dict(group=group,
                     cpu_seconds_observed=round(values['ticks'] / hz, 3),
                     cpu_percent_one_core_observed=round(100 * values['ticks'] / hz / elapsed, 2),
                     rss_mean_mib=round(values['rss_sum'] / max(self.samples, 1) / 1048576, 2),
                     rss_peak_sampled_mib=round(values['rss_peak'] / 1048576, 2))
                for group, values in sorted(self.groups.items(),
                                            key=lambda item: item[1]['ticks'], reverse=True)]


def measure(command):
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic()
    memory, processes = [], []
    per_process = ProcessTotals()
    child = subprocess.Popen(command)
    previous_handlers = {}

    def forward(signum, _frame):
        # Same foreground group: terminal Ctrl-C also reaches Bash directly.
        # Forward signals delivered only to the measurement process as well.
        if child.poll() is None:
            child.send_signal(signum)

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous_handlers[signum] = signal.signal(signum, forward)
    try:
        while child.poll() is None:
            rows = tree_sample(child.pid)
            rss, count = sum(row[4] for row in rows), len(rows)
            if count:
                memory.append(rss)
                processes.append(count)
                per_process.add(rows, child.pid)
            time.sleep(0.25)
        status = child.wait()
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    elapsed = time.monotonic() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime
    groups = per_process.report(elapsed)
    attributed = sum(values['ticks'] for values in per_process.groups.values()) / os.sysconf('SC_CLK_TCK')
    return {
        'duration_seconds': round(elapsed, 3),
        'cpu_seconds': round(cpu, 3),
        'cpu_percent_one_core': round(100 * cpu / elapsed, 2),
        'rss_mean_mib': round(sum(memory) / max(len(memory), 1) / 1048576, 2),
        'rss_peak_sampled_mib': round(max(memory, default=0) / 1048576, 2),
        'processes_peak_sampled': max(processes, default=0),
        'samples': len(memory),
        'exit_code': status,
        'process_groups': groups,
        'cpu_seconds_observed': round(attributed, 3),
        'cpu_seconds_unattributed': round(max(0, cpu - attributed), 3),
        'cpu_seconds_observed_excess': round(max(0, attributed - cpu), 3),
    }


def launcher_command(launcher, spectrum):
    # Source initializes the usual runtime and cleanup trap. --version keeps
    # this first invocation from opening the TUI; main then runs normally.
    return [
        'bash', '-c',
        'launcher=$1; spectrum=$2; set -- --version; '
        'source "$launcher" >/dev/null; SPECTRUM_ENABLED=$spectrum; main',
        'keila-resource-profile', str(launcher), '1' if spectrum == 'on' else '0',
    ]


def self_test():
    # CPU in a grandchild must be counted even after that process has exited.
    worker = (
        'import time; data=bytearray(12*1024*1024); end=time.process_time()+0.3\n'
        'while time.process_time()<end: pass\n'
        'time.sleep(0.6)'
    )
    parent = ('import subprocess,sys; '
              'subprocess.run([sys.executable,"-c",sys.argv[1]],check=True)')
    result = measure([sys.executable, '-c', parent, worker])
    assert result['exit_code'] == 0, result
    assert result['cpu_seconds'] >= 0.25, result
    assert result['rss_peak_sampled_mib'] >= 12, result
    assert result['processes_peak_sampled'] >= 2, result
    assert result['samples'] >= 2, result
    assert tree_sample(999999999) == []
    observed = result['cpu_seconds_observed']
    assert observed >= 0.2, result
    assert observed <= result['cpu_seconds'] + 0.03, result
    # Repeated samples, exited children and reused PIDs must not double CPU.
    totals = ProcessTotals()
    totals.add([(10, 1, 'bash', 5, 1024), (11, 2, 'ffmpeg', 10, 2048)], 10)
    totals.add([(10, 1, 'bash', 7, 1024), (11, 2, 'ffmpeg', 14, 2048)], 10)
    totals.add([(10, 1, 'bash', 8, 1024), (11, 3, 'jq', 2, 512)], 10)
    assert sum(group['ticks'] for group in totals.groups.values()) == 24
    assert totals.groups['ffmpeg']['rss_sum'] == 4096
    assert totals.groups['Keila (Bash principal)']['ticks'] == 8
    fields = ['0'] * 22
    fields[11], fields[12], fields[19] = '7', '3', '123'
    assert parse_stat('10 (name with ) space) ' + ' '.join(fields)) == ('name with ) space', 123, 10)
    with tempfile.TemporaryDirectory(prefix='keila-test ') as directory:
        launcher = Path(directory) / 'fake launcher'
        launcher.write_text(
            'set -u\n'
            'trap \'printf "cleanup\\n"\' EXIT\n'
            'main() { if [[ "${1:-}" == --version ]]; then return 0; fi; '
            'printf "%s\\n" "$SPECTRUM_ENABLED"; }\n'
            'main "$@"\n'
        )
        for mode, expected in [('on', '1'), ('off', '0')]:
            output = subprocess.check_output(launcher_command(launcher, mode), text=True)
            assert output == expected + '\ncleanup\n', output
    print('ok   recursos: CPU descendiente, desglose sin duplicados, memoria, modos y cierre')


def main():
    parser = argparse.ArgumentParser(description='Medición de recursos de Keila en Linux')
    parser.add_argument('--spectrum', choices=('on', 'off'), default='on',
                        help='estado inicial del espectro; no pulsar V durante la prueba')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Esta medición requiere Linux y /proc.')
    if args.self_test:
        self_test()
        return 0
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        parser.error('Ejecuta esta prueba directamente en una terminal.')

    launcher = Path(__file__).resolve().parent.parent / 'keila-radio'
    result = measure(launcher_command(launcher, args.spectrum))
    result['spectrum_initial'] = args.spectrum
    directory = Path(tempfile.mkdtemp(prefix='keila-resources.'))
    report = directory / 'summary.json'
    report.write_text(json.dumps(result, indent=2) + '\n')
    print(f'\nRECURSOS KEILA — espectro {args.spectrum}')
    print(f"Duración: {result['duration_seconds']:.1f} s")
    print(f"CPU acumulada: {result['cpu_seconds']:.2f} s")
    print(f"CPU media: {result['cpu_percent_one_core']:.1f}% (100% = un núcleo)")
    print(f"RSS sumada: media {result['rss_mean_mib']:.1f} MiB; "
          f"máximo muestreado {result['rss_peak_sampled_mib']:.1f} MiB")
    print(f"Procesos simultáneos: máximo muestreado {result['processes_peak_sampled']}")
    print(f"Código de salida: {result['exit_code']}")
    print('\nDESGLOSE OBSERVADO (agrupado por programa)')
    print(f"{'Programa':<24} {'CPU s':>8} {'CPU %':>8} {'RSS media MiB':>14}")
    for row in result['process_groups']:
        print(f"{row['group']:<24} {row['cpu_seconds_observed']:>8.2f} "
              f"{row['cpu_percent_one_core_observed']:>8.1f} {row['rss_mean_mib']:>14.1f}")
    print(f"CPU sin atribuir por muestreo: {result['cpu_seconds_unattributed']:.2f} s")
    if result['cpu_seconds_observed_excess'] > 0.03:
        print('Aviso: el desglose supera el total contabilizado al cierre; '
              'pueden existir descendientes no recogidos por Keila.')
    print('El desglose omite procesos breves y tramos finales entre muestras; no sustituye al total.')
    print('Incluye arranque, reproducción y cierre; el medidor queda fuera de la CPU.')
    print('CPU: Keila y descendientes contabilizados al cerrar; RSS muestreada cada 250 ms.')
    print('RSS puede contar páginas compartidas varias veces y omitir picos breves.')
    print('No incluye foot ni el servidor de audio compartido PulseAudio/PipeWire.')
    print(f'Registro: {report}')
    return result['exit_code'] if result['exit_code'] >= 0 else 128 - result['exit_code']


if __name__ == '__main__':
    sys.exit(main())
