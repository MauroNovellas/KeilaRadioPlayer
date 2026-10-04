#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""CPU/RSS del mantenimiento en reposo; sin audio/red ni umbrales de máquina."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('resource_profile', ROOT / 'tests/resource-profile.py')
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--duration', type=int, default=3)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 2 <= args.duration <= 30:
        parser.error('--duration: entre 2 y 30 segundos por escenario')
    results = []
    for mode in ('stopped', 'playing', 'menu', 'animation'):
        with tempfile.TemporaryDirectory(prefix='keila-idle.') as directory:
            report = profile.measure(['bash', str(ROOT / 'tests/fixtures/runtime-idle-probe.sh'),
                                      str(ROOT), mode, str(args.duration), directory])
            if report['exit_code']:
                raise SystemExit(f'{mode}: fallo {report["exit_code"]}')
            ticks = int((Path(directory) / 'ticks').read_text())
            report.update(mode=mode, ticks=ticks,
                          ticks_per_second=round(ticks / report['duration_seconds'], 2))
            results.append(report)
            print(f'{mode}: {report["cpu_percent_one_core"]:.2f}% CPU; '
                  f'{report["rss_peak_sampled_mib"]:.2f} MiB RSS pico; '
                  f'{report["ticks_per_second"]:.2f} ticks/s')
    if args.output:
        args.output.write_text(json.dumps(results, indent=2) + '\n')
    print('CPU de Keila y auxiliares; RSS sumada puede duplicar páginas compartidas.')
    print('No mide FFT, mpv, terminal gráfico, servidor de audio ni batería física.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
