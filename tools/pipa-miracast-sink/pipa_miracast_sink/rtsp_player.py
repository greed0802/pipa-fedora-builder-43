"""GStreamer playback for Miracast RTSP/RTP streams.

This is a draft. Real Miracast streams may need a custom rtspsrc/decodebin
pipeline, caps handling, and latency tuning.
"""

from __future__ import annotations

try:
    import gi

    gi.require_version("Gst", "1.0")
    from gi.repository import Gst  # type: ignore
except Exception:  # pragma: no cover - runtime dependency
    Gst = None


class RtspPlayer:
    def __init__(self, on_error=None, on_eos=None, on_status=None):
        self.pipeline = None
        self.on_error = on_error
        self.on_eos = on_eos
        self.on_status = on_status
        self._gst_ready = False

    def ensure_gst(self):
        if Gst is None:
            raise RuntimeError("GStreamer Python bindings (gi Gst) are not available")
        if not self._gst_ready:
            Gst.init(None)
            self._gst_ready = True

    def play(self, uri: str, video_sink: str = "waylandsink sync=false", audio_sink: str = "pulsesink sync=false"):
        self.ensure_gst()
        self.stop()
        # TODO: replace playbin with a Miracast-tuned pipeline if needed.
        desc = f"playbin uri={uri!r} video-sink={video_sink!r} audio-sink={audio_sink!r}"
        if self.on_status:
            self.on_status(f"Launching pipeline: {desc}")
        self.pipeline = Gst.parse_launch(desc)
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message::error", self._handle_error)
        bus.connect("message::eos", self._handle_eos)
        bus.connect("message::state-changed", self._handle_state)
        self.pipeline.set_state(Gst.State.PLAYING)

    def stop(self):
        if self.pipeline and Gst is not None:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None

    def _handle_error(self, _bus, msg):
        err, dbg = msg.parse_error()
        if self.on_error:
            self.on_error(str(err), dbg)
        self.stop()

    def _handle_eos(self, _bus, _msg):
        if self.on_eos:
            self.on_eos()
        self.stop()

    def _handle_state(self, _bus, msg):
        if not self.pipeline or msg.src != self.pipeline:
            return
        old, new, _pending = msg.parse_state_changed()
        if self.on_status and Gst is not None:
            self.on_status(f"GStreamer state: {old.value_nick} -> {new.value_nick}")
