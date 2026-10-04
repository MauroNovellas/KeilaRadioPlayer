#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Teclas recibidas en un TTY real entre lecturas, no mediante una tubería."""

import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import termios
import time


ROOT_DIR = Path(__file__).resolve().parent.parent


def acquire_tty():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def check_session(erase, drain_limit):
    master, slave = pty.openpty()
    gate_read, gate_write = os.pipe()
    child = None
    transcript = bytearray()
    pending = bytearray()
    try:
        settings = termios.tcgetattr(slave)
        settings[6][termios.VERASE] = erase
        # Valores no predeterminados: restaurar solo eco/ICANON no es suficiente.
        settings[6][termios.VMIN] = 4
        settings[6][termios.VTIME] = 2
        termios.tcsetattr(slave, termios.TCSANOW, settings)
        original = termios.tcgetattr(slave)
        env = dict(os.environ, LC_ALL="C.UTF-8",
                   KEILA_INPUT_REPEAT_DRAIN_LIMIT=str(drain_limit))
        child = subprocess.Popen(
            ["bash", str(ROOT_DIR / "tests/fixtures/input-tty-probe.sh"),
             str(ROOT_DIR), str(gate_read)],
            stdin=slave, stdout=slave, stderr=slave, env=env,
            pass_fds=(gate_read,), preexec_fn=acquire_tty,
        )
        os.close(gate_read)
        gate_read = None

        def expect(expected):
            deadline = time.monotonic() + 5
            while True:
                if b"\n" in pending:
                    line, _, remainder = pending.partition(b"\n")
                    pending[:] = remainder
                    actual = line.rstrip(b"\r").decode("utf-8")
                    if actual != expected:
                        raise AssertionError(f"esperado {expected!r}, obtenido {actual!r}")
                    return
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
                    raise AssertionError(f"no llegó {expected!r} (tecla perdida o bloqueo)")
                data = os.read(master, 4096)
                if not data:
                    raise AssertionError(f"PTY cerrado antes de {expected!r}")
                transcript.extend(data)
                pending.extend(data)

        def active_flags():
            current = termios.tcgetattr(slave)
            flags = current[3]
            if flags & (termios.ECHO | termios.ICANON):
                raise AssertionError("el TTY recupera eco/modo canónico entre lecturas")
            if flags & termios.ISIG != original[3] & termios.ISIG:
                raise AssertionError("la TUI cambia las señales del terminal")

        def send_during_processing(stage, keys=b"", active=True):
            expect(f"WAIT:{stage}")
            if active:
                active_flags()
            elif termios.tcgetattr(slave) != original:
                raise AssertionError("suspender no restaura el estado exacto del TTY")
            if keys:
                os.write(master, keys)
            os.write(gate_write, b"go\n")

        send_during_processing("enter", b"a")
        expect("QUERY:rockáa")
        send_during_processing("erase-del", b"\x7f")
        expect("QUERY:rocká")
        send_during_processing("erase-bs", b"\x08")
        expect("QUERY:rock")
        send_during_processing("mixed-burst", b"a" * 12 + b"\x7f" * 5 + b"Z\n")
        expect("QUERY:rockaaaaaaaZ")
        send_during_processing("delete", b"\x1b[3~")
        expect("QUERY:")
        send_during_processing("cursor", b"\x1b[B")
        send_during_processing("geometry", b"\x1b[6;16;8td")
        expect("QUERY:d")
        send_during_processing("geometry-erase", b"\x7f")
        expect("QUERY:")
        send_during_processing("suspended", active=False)
        send_during_processing("resumed", b"\x7f")
        expect("QUERY:")
        expect("DONE")
        if child.wait(timeout=5) != 0:
            raise AssertionError("el probe termina con error")
        if termios.tcgetattr(slave) != original:
            raise AssertionError("salir no restaura el estado exacto del TTY")
    except Exception as error:
        raise AssertionError(
            f"erase={erase!r}, drenaje={drain_limit}: {error}\n"
            + transcript.decode("utf-8", errors="replace")
        ) from error
    finally:
        # Solo el grupo privado creado por esta prueba; nunca procesos de Keila
        # del usuario ni la terminal desde la que se lanzó la batería.
        if child is not None and child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait(timeout=5)
        for fd in (master, slave, gate_read, gate_write):
            if fd is not None:
                os.close(fd)


def main():
    for erase in (b"\x7f", b"\x08"):
        for drain_limit in (2, 512):
            check_session(erase, drain_limit)
    print("ok   TTY: Retroceso, Unicode y ráfagas entre lecturas; suspensión/restauración exacta")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print(f"FAIL {error}", file=sys.stderr)
        sys.exit(1)
