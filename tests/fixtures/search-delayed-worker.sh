#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Retraso controlado para detectar si un filtro bloquea el teclado.
sleep .35
exec bash "$(dirname "${BASH_SOURCE[0]}")/../../lib/search-worker.sh" "$@"
