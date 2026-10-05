#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Consentimiento real en PTY, sin gestores ni credenciales del usuario."""
import fcntl
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import termios
import time

ROOT_DIR = Path(__file__).resolve().parent.parent


def acquire_tty():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def check_prompt(mode, answer, accepted):
    master, slave = pty.openpty()
    child = None
    with tempfile.TemporaryDirectory(prefix="keila-deps-tty.") as task_tmp:
        marker = Path(task_tmp) / "changes"
        transcript = bytearray()
        try:
            child = subprocess.Popen(
                ["bash", str(ROOT_DIR / "tests/fixtures/dependency-prompt.sh"),
                 str(ROOT_DIR), mode, str(marker)],
                stdin=slave, stdout=slave, stderr=slave,
                env=dict(os.environ, TMPDIR=task_tmp, LC_ALL="C.UTF-8"),
                preexec_fn=acquire_tty,
            )
            deadline = time.monotonic() + 5
            while b"[s/N] " not in transcript:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
                    raise AssertionError("no llegó la confirmación")
                transcript.extend(os.read(master, 65536))
            # Verificar que no se han autorizado ni cambiado paquetes antes de
            # recibir la respuesta, incluidas reparaciones con todo instalado.
            assert not marker.exists() and b"AUTH" not in transcript
            if mode == "termux-repair":
                assert "medio configurar" in transcript.decode("utf-8")
            else:
                assert b"mpv: Reproduce" in transcript and b"jq: Lee" in transcript
                expected = b"ncurses-utils" if mode.startswith("termux-") else b"ncurses-bin"
                assert expected in transcript
            if mode.startswith("termux-"):
                assert "entorno completo" in transcript.decode("utf-8")
            os.write(master, answer)
            status = child.wait(timeout=5)
            while select.select([master], [], [], 0)[0]:
                transcript.extend(os.read(master, 65536))
            text = transcript.decode("utf-8")
            assert status == (0 if accepted else 1), text
            if accepted:
                assert marker.exists() and "Dependencias listas" in text
                assert "NOISY" not in text, text
                if mode == "termux-repair":
                    assert marker.read_text() == "repair\n"
            elif mode == "failure":
                assert marker.exists() and "Registro completo" in text
                logs = list(Path(task_tmp).glob("keila-deps.*"))
                assert len(logs) == 1 and logs[0].stat().st_mode & 0o777 == 0o600
            else:
                assert not marker.exists() and "cancelada" in text
                assert "AUTH" not in text
        finally:
            if child is not None and child.poll() is None:
                child.kill()
                child.wait(timeout=5)
            os.close(master)
            os.close(slave)


def main():
    for mode, answer, accepted in (
        ("apt", b"\n", False), ("apt", b"n\n", False),
        ("apt", b"otra cosa\n", False), ("apt", b"\x04", False),
        ("apt", b"S\n", True), ("apt", "sí\n".encode(), True),
        ("termux-install", b"s\n", True),
        ("termux-repair", b"n\n", False), ("termux-repair", b"s\n", True),
        ("failure", b"s\n", False),
    ):
        check_prompt(mode, answer, accepted)
    print("ok   PTY: aceptación/rechazo/Enter/EOF, descripción, Termux y error silencioso")


if __name__ == "__main__":
    main()
