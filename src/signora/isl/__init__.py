"""Indian Sign Language (ISL) two-handed recognition engine."""

from .config import FEATURE_DIM, STATIC_LETTERS, STATIC_WORDS, TRAIN_LABELS
from .features import extract_features
from .model import ISL_MLP, Predictor

__all__ = [
    "FEATURE_DIM",
    "STATIC_LETTERS",
    "STATIC_WORDS",
    "TRAIN_LABELS",
    "extract_features",
    "ISL_MLP",
    "Predictor",
    "run_isl_live",
]


def __getattr__(name: str):
    """Load the OpenCV live loop lazily for fast native-app startup."""
    if name == "run_isl_live":
        from .live import run_isl_live

        return run_isl_live
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
