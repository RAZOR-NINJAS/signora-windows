"""Camera capture wrapper with single-frame buffering and graceful error reporting."""

import os
import time
from typing import Any, Optional, Tuple, Union

import cv2
import numpy as np

from signora.core.fake_camera import FakeCamera
from signora.platform_compat import get_camera_capture, is_windows


class CameraError(RuntimeError):
    """Raised when camera hardware or stream fails with actionable troubleshooting advice."""

    pass


class Camera:
    """Manages video capture lifecycle with single-frame queue and fps measurement."""

    def __init__(
        self,
        source: Union[int, str, Any] = 0,
        width: int = 1280,
        height: int = 720,
        buffer_size: int = 1,
        use_fake: bool = False,
    ):
        self.source = source
        self.target_width = width
        self.target_height = height
        self.buffer_size = max(1, int(buffer_size))
        self.use_fake = use_fake or os.environ.get("SIGNORA_FAKE_CAMERA", "0") in (
            "1",
            "true",
            "True",
        )
        self.cap: Optional[Union[cv2.VideoCapture, FakeCamera]] = None
        self.active_source: Union[int, str] = source
        self.backend = "synthetic" if self.use_fake else "unknown"
        self._fps_actual = 0.0
        self._frame_count = 0
        self._last_fps_calc = time.monotonic()

    def _candidate_sources(self) -> list:
        """Return the requested source followed by the other common camera indexes.

        Windows laptops frequently expose the built-in camera at index 1 after a
        USB webcam has been plugged in, so a stale index in settings used to make
        the engine exit even though a perfectly good camera was present.
        """
        source = int(self.source) if isinstance(self.source, str) and self.source.isdigit() else self.source
        candidates = [source]
        if isinstance(source, int):
            candidates.extend(idx for idx in (0, 1, 2, 3) if idx != source)
        return candidates

    @staticmethod
    def _prime(cap: cv2.VideoCapture, seconds: float = 2.0) -> bool:
        """Wait for a first real frame; some virtual devices open but never deliver."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                ret, frame = cap.read()
            except Exception:
                return False
            if ret and frame is not None:
                return True
            time.sleep(0.05)
        return False

    def open(self) -> None:
        """Open the first camera that actually delivers frames."""
        if self.use_fake:
            self.cap = FakeCamera(width=self.target_width, height=self.target_height)
            self.active_source = "synthetic"
            self.backend = "synthetic"
            return

        attempts = []
        for candidate in self._candidate_sources():
            cap = None
            try:
                cap = get_camera_capture(
                    candidate,
                    buffer_size=self.buffer_size,
                    width=self.target_width,
                    height=self.target_height,
                )
            except Exception as exc:
                attempts.append(f"{candidate}: {exc}")
                continue

            if cap is None or not cap.isOpened():
                attempts.append(f"{candidate}: no device")
                if cap is not None:
                    cap.release()
                continue

            if not self._prime(cap):
                attempts.append(f"{candidate}: opened but delivered no frames")
                cap.release()
                continue

            self.cap = cap
            self.active_source = candidate
            self.backend = "DirectShow" if is_windows() else "V4L2"
            print(
                f"[Camera] Using source {candidate} ({self.backend})",
                flush=True,
            )

            # Dimensions, target FPS, and strict zero-latency hardware buffer.
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.target_width)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.target_height)
            try:
                self.cap.set(cv2.CAP_PROP_FPS, 30)
            except Exception:
                pass
            try:
                self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            except Exception:
                pass
            return

        # If every real device failed, honour the explicit synthetic-camera opt-in.
        if os.environ.get("SIGNORA_ALLOW_FAKE_FALLBACK", "0") in ("1", "true", "True"):
            self.cap = FakeCamera(width=self.target_width, height=self.target_height)
            self.active_source = "synthetic"
            self.backend = "synthetic"
            return

        advice = (
            (
                "Ensure your camera is connected and not in use by another app.\n"
                "On Windows: Verify Settings -> Privacy & Security -> Camera permissions.\n"
                "On Linux: Verify your user belongs to the 'video' group (sudo usermod -a -G video $USER)."
            )
            if not is_windows()
            else (
                "Ensure your camera is connected and not blocked by Windows Privacy settings.\n"
                "Check: Settings -> Privacy & Security -> Camera -> Allow apps to access your camera."
            )
        )
        tried = "\n".join(f"  - {line}" for line in attempts) or "  - no camera indexes available"
        raise CameraError(
            f"Could not open any camera (requested '{self.source}'). Tried:\n{tried}\n{advice}"
        )

    def read(self) -> Tuple[bool, Optional[np.ndarray]]:
        """Read a single frame from the camera, strictly guaranteeing 16:9 aspect ratio and zero buffer lag."""
        if self.cap is None or not self.cap.isOpened():
            return False, None

        if self.use_fake:
            ret, frame = self.cap.read()
        else:
            # Drain internal V4L2/DirectShow ring buffers to eliminate any stale frame delay
            ret = self.cap.grab()
            if not ret:
                return False, None
            ret, frame = self.cap.retrieve()

        if ret and frame is not None:
            h, w = frame.shape[:2]

            # 1. Enforce strict 16:9 aspect ratio (crop centered if hardware returns 4:3 or other ratios)
            target_aspect = 16.0 / 9.0
            actual_aspect = float(w) / float(max(1, h))
            if abs(actual_aspect - target_aspect) > 0.02:
                if actual_aspect < target_aspect:
                    # Too tall (e.g. 4:3 640x480) -> crop top/bottom to 16:9
                    desired_h = int(w / target_aspect)
                    y_off = max(0, (h - desired_h) // 2)
                    frame = frame[y_off : y_off + desired_h, :]
                else:
                    # Too wide -> crop left/right to 16:9
                    desired_w = int(h * target_aspect)
                    x_off = max(0, (w - desired_w) // 2)
                    frame = frame[:, x_off : x_off + desired_w]

            # 2. Scale to requested target dimensions
            h, w = frame.shape[:2]
            if (w, h) != (self.target_width, self.target_height):
                frame = cv2.resize(
                    frame, (self.target_width, self.target_height), interpolation=cv2.INTER_LINEAR
                )

            self._frame_count += 1
            now = time.monotonic()
            elapsed = now - self._last_fps_calc
            if elapsed >= 1.0:
                self._fps_actual = self._frame_count / elapsed
                self._frame_count = 0
                self._last_fps_calc = now
            return True, frame

        return False, None

    @property
    def fps(self) -> float:
        """Return measured capture frame rate."""
        return self._fps_actual

    @property
    def is_opened(self) -> bool:
        """Return True if capture is active."""
        return self.cap is not None and self.cap.isOpened()

    def release(self) -> None:
        """Release camera hardware."""
        if self.cap is not None:
            self.cap.release()
            self.cap = None

    def __enter__(self) -> "Camera":
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.release()
