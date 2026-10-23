"""Tests for core camera capture and synthetic test camera."""

import numpy as np

from signora.core.camera import Camera
from signora.core.fake_camera import FakeCamera


def test_fake_camera_generation():
    fake = FakeCamera(width=640, height=480, fps=30)
    assert fake.isOpened()

    ret, frame = fake.read()
    assert ret is True
    assert isinstance(frame, np.ndarray)
    assert frame.shape == (480, 640, 3)
    assert frame.dtype == np.uint8

    fake.release()
    assert not fake.isOpened()


def test_camera_lifecycle_with_fake():
    cam = Camera(source=0, width=320, height=240, use_fake=True)
    with cam:
        assert cam.is_opened
        ret, frame = cam.read()
        assert ret is True
        assert frame is not None
        assert frame.shape == (240, 320, 3)
        assert cam.fps >= 0.0

    assert not cam.is_opened


class _FakeCapture:
    """Minimal cv2.VideoCapture stand-in for the fallback tests."""

    def __init__(self, opened: bool = True, frames: int = 2):
        self.opened = opened
        self.frames = frames
        self.released = False

    def isOpened(self) -> bool:
        return self.opened

    def read(self):
        if self.frames > 0:
            self.frames -= 1
            return True, np.zeros((720, 1280, 3), dtype=np.uint8)
        return False, None

    def set(self, *args, **kwargs):
        return True

    def release(self) -> None:
        self.released = True
        self.opened = False


def test_camera_falls_back_to_a_working_index(monkeypatch):
    """A stale index in settings must not kill the engine when another camera works."""
    seen = []

    def fake_capture(source, **kwargs):
        seen.append(source)
        if source == 0:
            return _FakeCapture(opened=False)
        return _FakeCapture(opened=True, frames=2)

    monkeypatch.setattr("signora.core.camera.get_camera_capture", fake_capture)

    cam = Camera(source=0, use_fake=False)
    cam.open()

    assert cam.active_source == 1
    assert cam.is_opened
    cam.release()
    assert seen[0] == 0 and 1 in seen


def test_camera_skips_a_device_that_never_delivers(monkeypatch):
    """Virtual devices can open without producing frames; keep looking."""
    seen = []

    def fake_capture(source, **kwargs):
        seen.append(source)
        if source == 0:
            return _FakeCapture(opened=True, frames=0)
        return _FakeCapture(opened=True, frames=2)

    monkeypatch.setattr("signora.core.camera.get_camera_capture", fake_capture)
    monkeypatch.setattr(Camera, "_prime", staticmethod(lambda cap, seconds=2.0: cap.read()[0]))

    cam = Camera(source=0, use_fake=False)
    cam.open()

    assert cam.active_source == 1
    cam.release()
    assert seen[0] == 0 and 1 in seen
