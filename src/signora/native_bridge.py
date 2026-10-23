"""Local bridge service for the native Windows Signora app.

The WinUI frontend owns the chrome, transcript, settings, and landmark overlay.
This process owns the camera and neural pipeline, streams clean frames over the
existing MJPEG server, and exposes landmarks/status as JSON on localhost.

Launch:
    python -m signora.native_bridge --mode isl --port 8899
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

from signora.asl.model import load_asl_predictor
from signora.core.debounce import DebounceEngine
from signora.core.hands import HandPipeline
from signora.core.motion import HandMotionTracker, match_sign_motion
from signora.core.spatial import SpatialPipeline
from signora.isl.config import (
    CONFIRM_THRESHOLD,
    DWELL_MS,
    REPEAT_COOLDOWN_MS,
    SMOOTH_MS,
    SPACE_COOLDOWN_MS,
    SPACE_DWELL_MS,
)
from signora.core.features import extract_features as extract_asl_features
from signora.isl.features import extract_features as extract_isl_features
from signora.isl.model import Predictor
from signora.isl.spatial import (
    SIGN_ANCHOR_MAP,
    detect_body_anchor,
    extract_spatial_features,
)
from signora.models.manifest import get_default_models_dir
from signora.platform_compat import get_quality_profile, probe_cameras
from signora.stream.server import WebStreamServer
from signora.tts.piper import PiperTTS

WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 720


def _point(p: Any) -> Dict[str, float]:
    return {
        "x": float(getattr(p, "x", 0.0)),
        "y": float(getattr(p, "y", 0.0)),
        "z": float(getattr(p, "z", 0.0)),
    }


def _points(points: Optional[List[Any]]) -> List[Dict[str, float]]:
    if not points:
        return []
    return [_point(p) for p in points]


def _as_hands(landmarks: Any, handedness: Any) -> List[Dict[str, Any]]:
    if not landmarks:
        return []
    if isinstance(landmarks, list) and landmarks and isinstance(landmarks[0], (list, tuple)):
        names = handedness if isinstance(handedness, list) else ["Right"] * len(landmarks)
        return [
            {"handedness": names[i] if i < len(names) else "Right", "points": _points(h)}
            for i, h in enumerate(landmarks)
        ]
    name = handedness if isinstance(handedness, str) else "Right"
    return [{"handedness": name, "points": _points(landmarks)}]


def _select_source(source: Any, use_fake: bool) -> Tuple[Any, bool]:
    """Resolve the requested camera.

    Probing every device used to run unconditionally; on Windows DirectShow it
    can block for tens of seconds, which made the desktop UI time out before the
    bridge was even listening. Probing is now opt-in (SIGNORA_PROBE_CAMERAS=1)
    and a missing camera is reported instead of silently replaced by a
    synthetic feed.
    """
    if use_fake or os.environ.get("SIGNORA_FAKE_CAMERA", "0") in ("1", "true", "True"):
        return source, True

    requested = int(source) if str(source).isdigit() else source

    if os.environ.get("SIGNORA_PROBE_CAMERAS", "0") not in ("1", "true", "True"):
        return requested, False

    try:
        cams = probe_cameras(max_probe=3)
    except Exception:
        cams = []
    indexes = {int(c["index"]) for c in cams}
    if isinstance(requested, int) and requested in indexes:
        return requested, False
    for idx in sorted(indexes):
        return idx, False
    return requested, False



def _report_camera_failure(source: Any, error: Optional[Exception]) -> None:
    detail = str(error) if error else "the camera opened but produced no frame within 20 seconds"
    print(f"[NativeBridge] Camera failed (source={source}): {detail}", file=sys.stderr, flush=True)
    print(
        "[NativeBridge] Set a different camera index in Signora Settings, and check "
        "Settings > Privacy & Security > Camera allows desktop apps.",
        file=sys.stderr,
        flush=True,
    )


def run_native_bridge(
    mode: str = "isl",
    source: Any = 0,
    port: int = 8899,
    no_tts: bool = False,
    dwell_ms: Optional[int] = None,
    fake_camera: bool = False,
    mirror: bool = True,
    threshold: Optional[float] = None,
) -> int:
    mode = mode.lower().strip()
    if mode not in ("asl", "isl", "body"):
        print(f"[NativeBridge] Unknown mode: {mode}", file=sys.stderr)
        return 2

    quality = get_quality_profile()
    high = quality == "high"

    # Bind the status port first: the desktop UI polls /api/health, and probing
    # cameras can take several seconds on Windows. If we probe first the UI
    # declares startup failed before the server ever answers.
    server = WebStreamServer(host="127.0.0.1", port=port)
    if not server.start():
        print(f"[NativeBridge] Could not bind http://127.0.0.1:{port}", file=sys.stderr)
        return 1

    source, use_fake = _select_source(source, fake_camera)

    print(f"[NativeBridge] mode={mode} source={source} port={port} quality={quality}", flush=True)
    if use_fake:
        print("[NativeBridge] No physical camera found; using synthetic camera.", flush=True)

    tts = PiperTTS(enabled=not no_tts)
    paused = False
    running = True

    def _stop(_signum: int, _frame: Any) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, _stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, _stop)

    # ---------------------------------------------------------------- ASL
    if mode == "asl":
        try:
            predictor = load_asl_predictor()
        except FileNotFoundError:
            print("[NativeBridge] ASL weights missing; downloading...", flush=True)
            from scripts.fetch_models import DEFAULT_MANIFEST, fetch_models

            fetch_models(DEFAULT_MANIFEST, get_default_models_dir())
            predictor = load_asl_predictor()
        engine = DebounceEngine(
            predictor=predictor,
            smooth_ms=SMOOTH_MS,
            dwell_ms=dwell_ms if dwell_ms is not None else DWELL_MS,
            space_dwell_ms=SPACE_DWELL_MS,
            threshold=threshold if threshold is not None else CONFIRM_THRESHOLD,
            repeat_cooldown_ms=REPEAT_COOLDOWN_MS,
            space_cooldown_ms=SPACE_COOLDOWN_MS,
        )
        pipe = HandPipeline(
            source=source,
            num_hands=1,
            mirror=mirror,
            detect_every=1,
            use_fake=use_fake,
            width=WINDOW_WIDTH,
            height=WINDOW_HEIGHT,
            inference_width=960 if high else 640,
        )
        if not pipe.started.wait(timeout=20) or pipe.error:
            _report_camera_failure(source, pipe.error)
            server.stop()
            return 1

        frame_count = 0
        fps = 0.0
        t0 = time.monotonic()
        try:
            while running:
                command = server.output.pop_command()
                while command is not None:
                    _apply_command(command, engine, tts, pause_setter=lambda v: None)
                    command = server.output.pop_command()

                frame, landmarks, handedness = pipe.read(timeout=1.0)
                if frame is None:
                    time.sleep(0.005)
                    continue

                now = time.monotonic()
                frame_count += 1
                if frame_count % 30 == 0:
                    elapsed = max(1e-6, now - t0)
                    fps = 30.0 / elapsed
                    t0 = now

                cand_label = None
                cand_prob = 0.0
                if landmarks:
                    hnd = handedness if isinstance(handedness, str) else "Right"
                    feats = extract_asl_features(landmarks, handedness=hnd)
                    probs = predictor.probs(feats)
                    if len(probs) > 0:
                        idx = int(np.argmax(probs))
                        cand_prob = float(probs[idx])
                        cand_label = predictor.labels[idx]

                st = engine.update(cand_label, cand_prob, landmarks=landmarks)
                if st.get("confirmed"):
                    _speak_confirmed(tts, st["confirmed"], engine.buffer)

                server.output.update_frame(frame, quality=88)
                server.output.update_status(
                    mode=mode,
                    active_sign=st.get("candidate") or "",
                    confidence=float(cand_prob),
                    dwell=float(st.get("dwell_progress") or 0.0),
                    transcript=engine.buffer,
                    sentence=engine.buffer.strip(),
                    fps=round(fps, 1),
                    hands=_as_hands(landmarks, handedness),
                    pose=[],
                    status="tracking" if landmarks else "searching",
                    delegate=pipe.delegate,
                    paused=paused,
                    quality=quality,
                )
        finally:
            pipe.close()
            tts.close()
            server.stop()
        return 0

    # ------------------------------------------------------------ ISL/Body
    spatial_ckpt = get_default_models_dir() / "isl_spatial_mlp.pt"
    use_spatial = spatial_ckpt.exists()
    predictor = Predictor(
        path=spatial_ckpt if use_spatial else None,
        enable_topology=True,
    )
    engine = DebounceEngine(
        predictor=predictor,
        smooth_ms=SMOOTH_MS,
        dwell_ms=dwell_ms if dwell_ms is not None else DWELL_MS,
        space_dwell_ms=SPACE_DWELL_MS,
        threshold=threshold if threshold is not None else CONFIRM_THRESHOLD,
        repeat_cooldown_ms=REPEAT_COOLDOWN_MS,
        space_cooldown_ms=SPACE_COOLDOWN_MS,
    )
    pipe = SpatialPipeline(
        source=source,
        mirror=mirror,
        detect_every=1,
        use_fake=use_fake,
        width=WINDOW_WIDTH,
        height=WINDOW_HEIGHT,
    )
    if not pipe.started.wait(timeout=20) or pipe.error:
        _report_camera_failure(source, pipe.error)
        server.stop()
        return 1

    motion_tracker = HandMotionTracker()
    frame_count = 0
    fps = 0.0
    t0 = time.monotonic()
    try:
        while running:
            command = server.output.pop_command()
            while command is not None:
                _apply_command(command, engine, tts, pause_setter=lambda v: None)
                command = server.output.pop_command()

            frame, landmarks, handedness, pose_lms = pipe.read(timeout=1.0)
            if frame is None:
                time.sleep(0.005)
                continue

            now = time.monotonic()
            frame_count += 1
            if frame_count % 30 == 0:
                elapsed = max(1e-6, now - t0)
                fps = 30.0 / elapsed
                t0 = now

            if mode == "body":
                server.output.update_frame(frame, quality=88)
                server.output.update_status(
                    mode=mode,
                    active_sign="",
                    confidence=0.0,
                    dwell=0.0,
                    transcript="",
                    sentence="",
                    fps=round(fps, 1),
                    hands=_as_hands(landmarks, handedness),
                    pose=_points(pose_lms),
                    anchor="BODY",
                    status="tracking" if pose_lms else "searching",
                    delegate=pipe.delegate,
                    paused=paused,
                    quality=quality,
                )
                continue

            cand_label = None
            cand_prob = 0.0
            active_anchor = "OPEN_SPACE"
            lms_list: List[Any] = []
            hnd_list: List[str] = []
            active_lms = None

            if landmarks:
                lms_list = (
                    landmarks
                    if isinstance(landmarks, list) and landmarks and isinstance(landmarks[0], (list, tuple))
                    else [landmarks]
                )
                hnd_list = handedness if isinstance(handedness, list) else [handedness]
                active_lms = lms_list[0]
                motion_state = motion_tracker.update(
                    lms_list, hnd_list, pose_landmarks=pose_lms, timestamp=now
                )

                if pose_lms and len(pose_lms) >= 25:
                    active_anchor, _, _ = detect_body_anchor(
                        lms_list[0], pose_lms, w=frame.shape[1], h=frame.shape[0]
                    )

                top_label, top_prob = predictor.predict_from_landmarks(
                    lms_list, hnd_list, body_anchor=active_anchor
                )
                if top_label:
                    cand_label, cand_prob = top_label, top_prob
                else:
                    feats = (
                        extract_spatial_features(lms_list, hnd_list, pose_lms)
                        if use_spatial
                        else extract_isl_features(lms_list, hnd_list)
                    )
                    if predictor.has_engine:
                        probs = predictor.probs(feats)
                        if len(probs) > 0 and predictor.labels:
                            idx = int(np.argmax(probs))
                            cand_prob = float(probs[idx])
                            cand_label = predictor.labels[idx]

                if cand_label:
                    required = SIGN_ANCHOR_MAP.get(cand_label.upper())
                    if required and pose_lms and len(pose_lms) >= 25:
                        if active_anchor == required:
                            cand_prob = min(1.0, cand_prob * 1.25)
                        elif active_anchor not in ("OPEN_SPACE", required):
                            cand_prob *= 0.85
                    _, motion_factor = match_sign_motion(cand_label, motion_state)
                    cand_prob = min(1.0, cand_prob * motion_factor)

            st = engine.update(cand_label, cand_prob, landmarks=active_lms)
            if st.get("confirmed"):
                _speak_confirmed(tts, st["confirmed"], engine.buffer)

            server.output.update_frame(frame, quality=88)
            server.output.update_status(
                mode=mode,
                active_sign=st.get("candidate") or "",
                confidence=float(cand_prob),
                dwell=float(st.get("dwell_progress") or 0.0),
                transcript=engine.buffer,
                sentence=engine.buffer.strip(),
                fps=round(fps, 1),
                hands=_as_hands(landmarks, handedness),
                pose=_points(pose_lms),
                anchor=active_anchor,
                status="tracking" if landmarks else "searching",
                delegate=pipe.delegate,
                paused=paused,
                quality=quality,
            )
    finally:
        pipe.close()
        tts.close()
        server.stop()
    return 0


def _speak_confirmed(tts: PiperTTS, confirmed: str, buffer: str) -> None:
    if not tts.is_ready:
        return
    if confirmed == "SPACE":
        words = buffer.strip().split()
        tts.speak_async(words[-1] if words else "space")
    else:
        tts.speak_async(confirmed)


def _apply_command(
    command: Dict[str, Any],
    engine: DebounceEngine,
    tts: PiperTTS,
    pause_setter: Any,
) -> None:
    action = str(command.get("action", "")).lower()
    if action == "clear":
        engine.clear()
    elif action == "backspace":
        engine.backspace()
    elif action == "space":
        if engine.buffer and not engine.buffer.endswith(" "):
            engine.buffer += " "
    elif action == "speak":
        if engine.buffer.strip() and tts.is_ready:
            tts.speak_async(engine.buffer.strip())
    elif action == "set":
        key = str(command.get("key", "")).lower()
        value = command.get("value")
        if key == "dwell" and value is not None:
            engine.set_dwell(int(value))
        elif key == "threshold" and value is not None:
            engine.set_threshold(float(value))
        elif key == "tts":
            tts.set_muted(not bool(value))


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Signora native Windows bridge")
    parser.add_argument("--mode", choices=["asl", "isl", "body"], default="isl")
    parser.add_argument("--source", default="0")
    parser.add_argument("--port", type=int, default=8899)
    parser.add_argument("--no-tts", action="store_true")
    parser.add_argument("--dwell", type=int, default=None)
    parser.add_argument("--fake-camera", action="store_true")
    parser.add_argument("--no-mirror", action="store_true", help="Disable camera mirroring")
    parser.add_argument("--threshold", type=float, default=None, help="Confidence threshold")
    args = parser.parse_args(argv)

    source: Any = int(args.source) if str(args.source).isdigit() else args.source
    return run_native_bridge(
        mode=args.mode,
        source=source,
        port=args.port,
        no_tts=args.no_tts,
        dwell_ms=args.dwell,
        fake_camera=args.fake_camera,
        mirror=not args.no_mirror,
        threshold=args.threshold,
    )


if __name__ == "__main__":
    raise SystemExit(main())
