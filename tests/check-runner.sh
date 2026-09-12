#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/check.sh"
task_tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
check_manifest "$ROOT_DIR/tests" || fail 'inventario real'
check_selected all integration || fail 'all excluye integración'
if check_selected all manual || check_selected all packaging; then fail 'all inicia pruebas optativas'; fi
printf '#!/bin/bash\n' > "$task_tmp/sample.sh"
printf 'fast|sample.sh|\n' > "$task_tmp/suites.txt"
check_manifest "$task_tmp" || fail 'rechaza manifiesto válido'
printf '#!/bin/bash\n' > "$task_tmp/forgotten.sh"
if check_manifest "$task_tmp" 2>/dev/null; then fail 'no detecta prueba olvidada'; fi
printf 'fast|forgotten.sh|\nfast|sample.sh|\n' >> "$task_tmp/suites.txt"
if check_manifest "$task_tmp" 2>/dev/null; then fail 'no detecta duplicado'; fi
printf 'fast|../sample.sh|\n' > "$task_tmp/suites.txt"
if check_manifest "$task_tmp" 2>/dev/null; then fail 'acepta ruta fuera de tests'; fi
printf 'fast|missing.sh|\n' > "$task_tmp/suites.txt"
if check_manifest "$task_tmp" 2>/dev/null; then fail 'acepta archivo ausente'; fi
# Ejecutar una batería ficticia: no aborta en el primer fallo y aísla XDG/TMPDIR.
printf 'exit 7\n' > "$task_tmp/sample.sh"
printf '[[ "$XDG_CONFIG_HOME" == */forgotten/config && "$TMPDIR" == */forgotten/tmp ]]\n' > "$task_tmp/forgotten.sh"
printf 'fast|sample.sh|\nfast|forgotten.sh|\n' > "$task_tmp/suites.txt"
if (CHECK_DIR=$task_tmp; check_main fast) > "$task_tmp/result" 2>&1; then fail 'oculta test fallido'; fi
grep -q '1 correctas; 1 fallidas' "$task_tmp/result" || fail 'no continúa o no aísla perfiles'
printf 'sleep 10\n' > "$task_tmp/sample.sh"
if (CHECK_DIR=$task_tmp; KEILA_TEST_TIMEOUT=1; check_main fast) > "$task_tmp/result" 2>&1; then fail 'oculta timeout'; fi
grep -q 'FALLO (124)' "$task_tmp/result" || fail 'sin límite por prueba'
printf 'ok   runner: inventario completo, grupos, omisiones y duplicados\n'
