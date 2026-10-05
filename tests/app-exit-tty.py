#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Arranque y salida reales, sin radio ni terminal/datos personales."""

import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT_DIR = Path(__file__).resolve().parent.parent
CLEAN_SCREEN = b"\x1b[0m\x1b[2J\x1b[H"


def acquire_tty():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def check_session(mode, columns=80, lines=24):
    master, slave = pty.openpty()
    child = None
    transcript = bytearray()
    pending = bytearray()
    with tempfile.TemporaryDirectory(prefix="keila-exit-tty.") as task_tmp:
        try:
            settings = termios.tcgetattr(slave)
            settings[6][termios.VMIN] = 4
            settings[6][termios.VTIME] = 2
            termios.tcsetattr(slave, termios.TCSANOW, settings)
            original = termios.tcgetattr(slave)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", lines, columns, 0, 0))
            env = dict(os.environ, TERM="xterm-256color", LC_ALL="C.UTF-8",
                       KEILA_NO_UPDATE_CHECK="1", XDG_CONFIG_HOME=task_tmp + "/config",
                       XDG_STATE_HOME=task_tmp + "/state", XDG_CACHE_HOME=task_tmp + "/cache",
                       XDG_RUNTIME_DIR=task_tmp, TMPDIR=task_tmp)
            child = subprocess.Popen(
                ["bash", str(ROOT_DIR / "tests/fixtures/app-exit-tty-probe.sh"), str(ROOT_DIR)],
                stdin=slave, stdout=slave, stderr=slave, env=env, preexec_fn=acquire_tty,
            )

            def expect(expected):
                deadline = time.monotonic() + 6
                while True:
                    position = pending.find(expected)
                    if position >= 0:
                        del pending[:position + len(expected)]
                        return
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
                        raise AssertionError(f"no llegó {expected!r}")
                    data = os.read(master, 65536)
                    if not data:
                        raise AssertionError("PTY cerrado prematuramente")
                    transcript.extend(data)
                    pending.extend(data)

            def send(keys):
                os.write(master, keys)

            def interrupt():
                # VINTR real: señal a la sesión del PTY, no a nuestra terminal.
                send(original[6][termios.VINTR])

            def finish(expected_status):
                status = child.wait(timeout=6)
                while select.select([master], [], [], 0)[0]:
                    transcript.extend(os.read(master, 65536))
                if status != expected_status:
                    raise AssertionError(f"salida {status}, esperada {expected_status}")
                if termios.tcgetattr(slave) != original:
                    raise AssertionError("no se restaura el estado exacto del terminal")
                if b"\x1b[?1049l" not in transcript or not transcript.endswith(CLEAN_SCREEN):
                    raise AssertionError("TUI no retirada o pantalla final no vacía")
                # No limpiar el scrollback al salir. Algunos TERM usan CSI 3 J
                # al entrar; comprobamos solo el tramo de salida de la TUI.
                exit_tail = transcript[transcript.rfind(b"\x1b[?1049l"):]
                if b"\x1b[3J" in exit_tail:
                    raise AssertionError("salir borra también el scrollback")

            expect(b"STARTING\r\n")
            expect(b"^..^")
            splash_at = time.monotonic()
            # Las pulsaciones durante la bienvenida se conservan.
            if mode == "keys":
                send(b"q")
            expect(b"KEILA")
            expect(b"READY:1")
            elapsed = time.monotonic() - splash_at
            if not 1.75 <= elapsed <= 4:
                raise AssertionError(f"duración del perro inesperada: {elapsed:.2f} s")
            if mode == "keys":
                expect(b"PROMPT:0")
                expect(b"TICK")
                send(b"\n")
                expect(b"READY:2")
                send(b"q")
                expect(b"PROMPT:0")
                send(b"\x1b[B")
                expect(b"PROMPT:1")
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 34, 0, 0))
                os.kill(child.pid, signal.SIGWINCH)
                expect(b"PROMPT:1")
                send(b"\n")
                finish(0)
            elif mode == "interrupt":
                send(b"o")
                expect(b"EDITOR:texto conservado")
                interrupt()
                expect(b"PROMPT:0")
                # Ctrl-C repetido cancela el cuadro, no cierra ni lo anida.
                interrupt()
                expect(b"EDITOR:texto conservado")
                send(b"x")
                expect(b"EDITOR:texto conservadox")
                interrupt()
                expect(b"PROMPT:0")
                send(b"s")
                finish(130)
            elif mode == "terminate":
                os.kill(child.pid, signal.SIGTERM)
                finish(143)
            elif mode == "hangup":
                os.kill(child.pid, signal.SIGHUP)
                finish(129)
            else:
                send(b"q")
                expect(b"PROMPT:0")
                send(b"s")
                finish(0)

            # Splash ASCII acotado también en pantalla pequeña, sin wrap.
            splash = transcript[:transcript.find(b"READY:1")]
            positions = re.findall(rb"\x1b\[(\d+);(\d+)H([^\x1b\r\n]*)", splash)
            for row, col, text in positions:
                if not 1 <= int(row) <= lines or int(col) + len(text) > columns:
                    raise AssertionError("el perro desborda la pantalla")
        except Exception as error:
            raise AssertionError(f"{mode}, {columns}x{lines}: {error}\n"
                                 + transcript.decode("utf-8", errors="replace")) from error
        finally:
            if child is not None and child.poll() is None:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait(timeout=5)
            os.close(master)
            os.close(slave)


def main():
    check_session("keys")
    check_session("interrupt")
    check_session("small", columns=8, lines=4)
    check_session("terminate")
    check_session("hangup")
    print("ok   TTY: perro y KEILA 2 s, teclas en cola, confirmación/Ctrl-C, resize y limpieza exacta")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print(f"FAIL {error}", file=sys.stderr)
        sys.exit(1)
