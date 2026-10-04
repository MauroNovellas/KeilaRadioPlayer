#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Keyboard-to-field timing in a real PTY with a deliberately busy filter.

The TUI/input are real. Audio, network and FFT are simulated; draining escape
sequences does not measure a particular terminal's GPU or Android hardware.
"""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import statistics
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parent.parent


class Probe:
    def __init__(self, directory, catalog, cols, lines, mode):
        self.master, self.slave = pty.openpty()
        self.before = termios.tcgetattr(self.slave)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", lines, cols, 0, 0))
        self.events, notify = os.pipe()
        self.buffer = b""
        self.pending = []
        self.tty_tail = b""
        self.query = ""
        env = dict(os.environ)
        for key, leaf in (("XDG_CONFIG_HOME", "config"), ("XDG_STATE_HOME", "state"),
                          ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            env[key] = str(directory / leaf)
            Path(env[key]).mkdir()
        env.pop("KEILA_FZF_SEARCH", None)
        env.pop("KEILA_SEARCH_MATCH_LIMIT", None)
        self.process = subprocess.Popen(
            ["bash", str(ROOT / "tests/fixtures/search-latency-probe.sh"), str(ROOT),
             str(notify), str(catalog), str(cols), str(lines), mode], env=env,
            stdin=self.slave, stdout=self.slave, stderr=self.slave,
            pass_fds=(notify,), start_new_session=True,
        )
        os.close(notify)

    def pump(self, until):
        ready, _, _ = select.select([self.master, self.events], [], [], max(0, until-time.monotonic()))
        for fd in ready:
            try:
                data = os.read(fd, 65536)
            except OSError as exc:
                if exc.errno != errno.EIO:
                    raise
                data = b""
            if fd == self.master:
                self.tty_tail = (self.tty_tail + data)[-2048:]
            else:
                if not data:
                    raise AssertionError(f"probe ended: {self.tty_tail.decode(errors='replace')!r}")
                self.buffer += data
                while b"\n" in self.buffer:
                    raw, self.buffer = self.buffer.split(b"\n", 1)
                    kind, query = raw.decode().split("\t", 1)
                    self.pending.append((kind, query, time.monotonic()))

    def wait(self, kinds, query, seconds=5):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            while self.pending:
                kind, value, stamp = self.pending.pop(0)
                if kind in kinds and value == query:
                    return stamp
            self.pump(until)
        raise AssertionError(f"timeout waiting {kinds}, query={query!r}, terminal={self.tty_tail!r}")

    def edit(self, data, expected):
        # Discard older notifications so repeated queries cannot match a stale frame.
        self.pending.clear()
        start = time.monotonic()
        os.write(self.master, data)
        finish = self.wait({"field", "frame"}, expected)
        self.query = expected
        return (finish-start)*1000

    def close(self):
        try:
            if self.process.poll() is None:
                os.write(self.master, b"\x1b")
                self.wait({"closed"}, self.query)
                self.process.wait(timeout=5)
            assert self.process.returncode == 0, f"exit {self.process.returncode}"
            assert termios.tcgetattr(self.slave) == self.before, "terminal settings not restored"
        finally:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait()
            for fd in (self.master, self.slave, self.events):
                os.close(fd)


def exercise(directory, catalog, cols, lines, mode):
    directory.mkdir()
    probe = Probe(directory, catalog, cols, lines, mode)
    try:
        probe.wait({"frame"}, "")
        flags = termios.tcgetattr(probe.slave)[3]
        assert not flags & (termios.ICANON | termios.ECHO), "backspace captured by the terminal"
        samples = []
        for char in "rockñá":
            samples.append(probe.edit(char.encode(), probe.query+char))
        for erase in (b"\x7f", b"\x08", b"\x7f"):
            samples.append(probe.edit(erase, probe.query[:-1]))
        samples.append(probe.edit(b"\x1b[3~", ""))
        samples.append(probe.edit("á".encode()*35+b"\x7f"*12, "á"*23))
        samples.append(probe.edit(b"\x7f"*23, ""))

        # Key arrives after a job has started, not just inside the 80 ms debounce.
        samples.append(probe.edit(b"rock", "rock"))
        probe.wait({"work"}, "rock")
        busy = probe.edit(b"\x7f", "roc")
        if mode == "async":
            assert busy < 250, f"foreground filter regression: backspace blocked {busy:.0f} ms"
            assert max(samples) < 750, f"slow keyboard: {max(samples):.0f} ms"
        else:
            assert busy >= 300, "controlled foreground delay was not exercised"
        # Let the new results settle, then keep deleting; no stale publication.
        probe.wait({"frame"}, "roc")
        samples.append(probe.edit(b"\x7f"*3, ""))
        if mode == "async":
            # Repeatedly replace an active job; cancellation must not build an
            # input queue or publish results from the old query.
            for _ in range(3):
                samples.append(probe.edit(b"rock", "rock"))
                probe.wait({"work"}, "rock")
                samples.append(probe.edit(b"\x7f", "roc"))
                probe.wait({"work"}, "roc")
                samples.append(probe.edit(b"\x7f"*3, ""))
            assert max(samples) < 750, f"cancellation stalls keyboard: {max(samples):.0f} ms"
        ordered = sorted(samples)
        p95 = ordered[min(len(ordered)-1, int(len(ordered)*.95))]
        print(f"{cols}x{lines} {mode}: p50 {statistics.median(samples):.1f} ms; "
              f"p95 {p95:.1f} ms; max {max(samples):.1f} ms; busy Backspace {busy:.1f} ms")
    finally:
        probe.close()
    assert not list((directory / "tmp").glob("keila-search.*")), "search left private jobs behind"


def main():
    with tempfile.TemporaryDirectory(prefix="keila-latency-") as temp:
        directory = Path(temp)
        catalog = directory / "catalog.tsv"
        with catalog.open("w", encoding="utf-8") as stream:
            for index in range(50000):
                genre = "rock" if index % 2 else "jazz"
                stream.write(f"Radio {genre} {index:05d}\tMadrid; {genre}\tEspaña\tMP3 128 kbps\t"
                             f"https://radio.invalid/{index}\tES\tradio {genre} {index:05d} madrid españa "
                             f"{genre} música noticias online directo regional\tMadrid\t{genre},music,news\n")
        print("50.000 emisoras; PTY real; espectro/estado de reproducción simulados, logo SIXEL en desktop.")
        for cols, lines in ((132, 40), (40, 10)):
            for mode in ("foreground", "async"):
                exercise(directory / f"{cols}-{mode}", catalog, cols, lines, mode)
    print("ok teclado durante filtrado lento, Unicode, ráfagas, Supr y cierre sin trabajos pendientes")


if __name__ == "__main__":
    main()
