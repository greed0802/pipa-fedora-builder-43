import shutil
import subprocess


REQUIRED_TOOLS = ("miracle-wifid", "miracle-sinkctl", "gst-launch-1.0", "iw")


def missing_tools() -> list[str]:
    return [tool for tool in REQUIRED_TOOLS if not shutil.which(tool)]


def iw_phy_text() -> str:
    result = subprocess.run(["iw", "phy"], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        result = subprocess.run(["iw", "dev"], capture_output=True, text=True, check=False)
    return result.stdout + ("\n" + result.stderr if result.stderr else "")


def has_p2p_support() -> bool | None:
    """Return True/False if detectable, None if unknown."""
    text = iw_phy_text()
    if not text.strip():
        return None
    lowered = text.lower()
    if "p2p-client" in lowered or "p2p-go" in lowered or "p2p-device" in lowered:
        return True
    if "supported interface modes" in lowered:
        return False
    return None
