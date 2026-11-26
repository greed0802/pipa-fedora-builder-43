from dataclasses import dataclass


@dataclass
class Config:
    sink_name: str = "Pipa Display"
    player: str = "auto"  # auto|gst|mpv
    gst_video_sink: str = "waylandsink sync=false"
    gst_audio_sink: str = "pulsesink sync=false"
    log_level: str = "debug"
    miracle_wifid_cmd: tuple[str, ...] = ("sudo", "miracle-wifid")
    miracle_sinkctl_cmd: tuple[str, ...] = ("sudo", "miracle-sinkctl")
