#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
sleep 30 &
printf '%s\n' "$!" > "$8/child"
wait
