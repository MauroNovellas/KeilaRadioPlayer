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


def tree_rss(pid):
    """Sample summed resident memory; disappearing processes are normal."""
    pending, seen, total, count = [pid], set(), 0, 0
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
        except (OSError, ValueError, IndexError):
            continue
        total += pages * os.sysconf('SC_PAGE_SIZE')
        count += 1
    return total, count


def measure(command):
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic()
    memory, processes = [], []
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
            rss, count = tree_rss(child.pid)
            if count:
                memory.append(rss)
                processes.append(count)
            time.sleep(0.25)
        status = child.wait()
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    elapsed = time.monotonic() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime
    return {
        'duration_seconds': round(elapsed, 3),
        'cpu_seconds': round(cpu, 3),
        'cpu_percent_one_core': round(100 * cpu / elapsed, 2),
        'rss_mean_mib': round(sum(memory) / max(len(memory), 1) / 1048576, 2),
        'rss_peak_sampled_mib': round(max(memory, default=0) / 1048576, 2),
        'processes_peak_sampled': max(processes, default=0),
        'samples': len(memory),
        'exit_code': status,
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
    assert tree_rss(999999999) == (0, 0)
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
    print('ok   recursos: CPU descendiente, memoria, modos on/off y cierre')


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
    print('Incluye arranque, reproducción y cierre; el medidor queda fuera de la CPU.')
    print('CPU: Keila y descendientes contabilizados al cerrar; RSS muestreada cada 250 ms.')
    print('RSS puede contar páginas compartidas varias veces y omitir picos breves.')
    print('No incluye foot ni el servidor de audio compartido PulseAudio/PipeWire.')
    print(f'Registro: {report}')
    return result['exit_code'] if result['exit_code'] >= 0 else 128 - result['exit_code']


if __name__ == '__main__':
    sys.exit(main())
