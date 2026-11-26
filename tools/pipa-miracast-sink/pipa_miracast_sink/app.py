from __future__ import annotations

import threading

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk  # type: ignore

from .config import Config
from .p2p_check import has_p2p_support, missing_tools
from .rtsp_player import RtspPlayer
from .sink_manager import SinkManager


class PipaMiracastSinkWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application, config: Config | None = None):
        super().__init__(application=app, title="Pipa Miracast Sink (Draft)")
        self.config = config or Config()
        self.set_default_size(900, 560)

        self.player = RtspPlayer(
            on_error=self._on_player_error,
            on_eos=self._on_player_eos,
            on_status=self._on_status_threadsafe,
        )
        self.sink = SinkManager(
            sink_name=self.config.sink_name,
            wifid_cmd=self.config.miracle_wifid_cmd,
            sinkctl_cmd=self.config.miracle_sinkctl_cmd,
            log_level=self.config.log_level,
            on_uri=self._on_uri,
            on_status=self._on_status_threadsafe,
        )

        self._build_ui()
        self._initial_checks()

    def _build_ui(self) -> None:
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        root.set_margin_top(12)
        root.set_margin_bottom(12)
        root.set_margin_start(12)
        root.set_margin_end(12)

        title = Gtk.Label(label="Pipa Miracast Sink (Win+K receiver draft)")
        title.add_css_class("title-2")
        title.set_halign(Gtk.Align.START)

        self.status_label = Gtk.Label(label="Idle")
        self.status_label.set_halign(Gtk.Align.START)
        self.status_label.set_wrap(True)

        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.start_btn = Gtk.Button(label="Start sink")
        self.stop_btn = Gtk.Button(label="Stop sink")
        self.stop_btn.set_sensitive(False)
        self.start_btn.connect("clicked", self.on_start)
        self.stop_btn.connect("clicked", self.on_stop)

        self.uri_entry = Gtk.Entry()
        self.uri_entry.set_placeholder_text("rtsp://... (manual test URI)")
        self.play_btn = Gtk.Button(label="Play URI")
        self.play_btn.connect("clicked", self.on_play_uri)
        controls.append(self.start_btn)
        controls.append(self.stop_btn)
        controls.append(self.uri_entry)
        controls.append(self.play_btn)

        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_monospace(True)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_child(self.log_view)

        root.append(title)
        root.append(self.status_label)
        root.append(controls)
        root.append(scroll)
        self.set_child(root)

    def _initial_checks(self) -> None:
        missing = missing_tools()
        if missing:
            self._log(f"Missing tools: {', '.join(missing)}")
            self._log("Install prerequisites (see README) before starting.")
        p2p = has_p2p_support()
        if p2p is True:
            self._log("P2P capability detected by iw.")
        elif p2p is False:
            self._log("P2P capability not detected by iw. Win+K discovery may fail.")
        else:
            self._log("Could not determine P2P capability. Run: iw phy | grep -A20 'Supported interface modes'")

    def on_start(self, _btn):
        self.start_btn.set_sensitive(False)
        self.stop_btn.set_sensitive(True)
        self._set_status("Starting sink manager...")
        threading.Thread(target=self._start_sink, daemon=True).start()

    def _start_sink(self):
        try:
            self.sink.start()
        except Exception as exc:
            self._on_status_threadsafe(f"Start failed: {exc}")
            GLib.idle_add(self.start_btn.set_sensitive, True)
            GLib.idle_add(self.stop_btn.set_sensitive, False)

    def on_stop(self, _btn):
        self.sink.stop()
        self.player.stop()
        self.start_btn.set_sensitive(True)
        self.stop_btn.set_sensitive(False)
        self._set_status("Stopped.")

    def on_play_uri(self, _btn):
        uri = self.uri_entry.get_text().strip()
        if not uri:
            self._set_status("Enter an rtsp:// URI first.")
            return
        self._set_status(f"Playing {uri}")
        threading.Thread(target=self.player.play, args=(uri, self.config.gst_video_sink, self.config.gst_audio_sink), daemon=True).start()

    def _on_uri(self, uri: str):
        self._on_status_threadsafe(f"Detected RTSP URI: {uri}")
        GLib.idle_add(self.uri_entry.set_text, uri)
        threading.Thread(target=self.player.play, args=(uri, self.config.gst_video_sink, self.config.gst_audio_sink), daemon=True).start()

    def _on_player_error(self, err: str, dbg: str):
        self._on_status_threadsafe(f"Player error: {err}")
        self._on_status_threadsafe(f"Debug: {dbg}")

    def _on_player_eos(self):
        self._on_status_threadsafe("Stream ended (EOS).")

    def _on_status_threadsafe(self, message: str):
        GLib.idle_add(self._log, message)

    def _set_status(self, message: str):
        self.status_label.set_text(message)
        self._log(message)

    def _log(self, message: str):
        buf = self.log_view.get_buffer()
        end = buf.get_end_iter()
        buf.insert(end, message + "\n")
        mark = buf.create_mark(None, buf.get_end_iter(), False)
        self.log_view.scroll_to_mark(mark, 0.0, True, 0.0, 1.0)
        self.status_label.set_text(message)
        return False


class PipaMiracastSinkApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="ai.arena.pipa.miracast.sink")

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = PipaMiracastSinkWindow(self)
        win.present()


def main():
    app = PipaMiracastSinkApp()
    app.run()
