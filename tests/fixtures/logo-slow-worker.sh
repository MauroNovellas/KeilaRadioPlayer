#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Doble de trabajo lento, solo para comprobar cancelación del grupo privado.
printf '%s\n' "$BASHPID" > "$4/child"
sleep 30 &
wait
