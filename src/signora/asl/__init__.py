"""American Sign Language (ASL) fingerspelling module."""

from .config import FEATURE_DIM, LETTERS, SPECIAL_SIGNS, TRAIN_LABELS
from .model import SignMLP, load_asl_predictor

__all__ = [
    "FEATURE_DIM",
    "LETTERS",
    "SPECIAL_SIGNS",
    "TRAIN_LABELS",
    "SignMLP",
    "load_asl_predictor",
    "run_asl_live",
]


def __getattr__(name: str):
    """Load the live loop only when a caller actually runs it.

    The native Windows bridge imports ``load_asl_predictor`` at startup; eagerly
    importing ``live`` here pulls in the whole HUD/TTS stack for no reason.
    """
    if name == "run_asl_live":
        from .live import run_asl_live

        return run_asl_live
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
