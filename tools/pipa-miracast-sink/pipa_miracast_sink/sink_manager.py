"""Orchestrate MiracleCast sink processes.

Draft notes:
- miracle-sinkctl is interactive; robust integration should use a PTY or a
  dedicated control API/DBus wrapper, not naive stdout parsing.
- miracle-wifid/sinkctl often require root or appropriate capabilities.
- This draft only detects rtsp:// URIs in output as a spike.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import threading
from collections.abc import Callable


RTSP_RE = re.compile(r"(rtsp://[^\s'\"]+)")


class SinkManager:
    def __init__(
        self,
        sink_name: str = "Pipa Display",
        wifid_cmd: tuple[str, ...] = ("sudo", "miracle-wifid"),
        sinkctl_cmd: tuple[str, ...] = ("sudo", "miracle-sinkctl"),
        log_level: str = "debug",
        on_uri: Callable[[str], None] | None = None,
        on_status: Callable[[str], None] | None = None,
    ):
        self.sink_name = sink_name
        self.wifid_cmd = (*wifid_cmd, "--log-level", log_level)
        self.sinkctl_cmd = (*sinkctl_cmd, "--log-level", log_level)
        self.on_uri = on_uri
        self.on_status = on_status
        self.wifid: subprocess.Popen[str] | None = None
        self.sinkctl: subprocess.Popen[str] | None = None
        self._stop = threading.Event()

    def start(self) -> None:
        self._stop.clear()
        self._require_commands()
        self._emit("Starting miracle-wifid...")
        self.wifid = self._spawn(self.wifid_cmd, "wifid")
        self._emit("Starting miracle-sinkctl...")
        self.sinkctl = self._spawn(self.sinkctl_cmd, "sinkctl")
        threading.Thread(target=self._read_output, args=(self.wifid, "wifid"), daemon=True).start()
        threading.Thread(target=self._read_output, args=(self.sinkctl, "sinkctl"), daemon=True).start()
        self._emit(
            f"Sink manager started. Target name: {self.sink_name!r}. "
            "If Windows+K shows it, connect and watch logs for an rtsp:// URI."
        )

    def stop(self) -> None:
        self._stop.set()
        for proc in (self.sinkctl, self.wifid):
            if proc and proc.poll() is None:
                proc.terminate()
        for proc in (self.sinkctl, self.wifid):
            if proc and proc.poll() is None:
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
        self.wifid = None
        self.sinkctl = None
        self._emit("Sink manager stopped.")

    def _require_commands(self) -> None:
        for cmd in (self.wifid_cmd[0], self.sinkctl_cmd[0]):
            # sudo is allowed as first token; check the actual tool too
            tool = self.wifid_cmd[-2] if cmd == "sudo" else cmd
        for tool in ("miracle-wifid", "miracle-sinkctl"):
            if not shutil.which(tool):
                raise FileNotFoundError(f"Required tool not found in PATH: {tool}")

    def _spawn(self, cmd: tuple[str, ...], name: str) -> subprocess.Popen[str]:
        try:
            return subprocess.Popen(
                list(cmd),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except Exception as exc:
            raise RuntimeError(f"Failed to start {name}: {exc}") from exc

    def _read_output(self, proc: subprocess.Popen[str] | None, name: str) -> None:
        if not proc or not proc.stdout:
            return
        for line in proc.stdout:
            if self._stop.is_set():
                break
            text = line.rstrip()
            self._emit(f"[{name}] {text}")
            match = RTSP_RE.search(text)
            if match and self.on_uri:
                self.on_uri(match.group(1))
        if not self._stop.is_set():
            code = proc.poll()
            self._emit(f"[{name}] exited with code {code}")

    def _emit(self, message: str) -> None:
        if self.on_status:
            self.on_status(message)
