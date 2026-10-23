"""Signora virtual webcam and meeting broadcast module."""

from signora.stream.server import WebStreamServer

__all__ = [
    "run_virtual_stream",
    "VirtualCameraManager",
    "WebStreamServer",
    "render_meeting_overlay",
    "get_v4l2_setup_instructions",
]


def __getattr__(name: str):
    """Keep the MJPEG server importable without loading the full pipeline."""
    if name == "run_virtual_stream":
        from signora.stream.pipeline import run_virtual_stream

        return run_virtual_stream
    if name == "VirtualCameraManager":
        from signora.stream.vcam import VirtualCameraManager

        return VirtualCameraManager
    if name == "get_v4l2_setup_instructions":
        from signora.stream.vcam import get_v4l2_setup_instructions

        return get_v4l2_setup_instructions
    if name == "render_meeting_overlay":
        from signora.stream.overlay import render_meeting_overlay

        return render_meeting_overlay
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
