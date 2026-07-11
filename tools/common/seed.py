"""Shared seed-override helper for every block's *_random_test. Lets
tools/regression.py sweep a single random-tier test across many distinct,
logged seeds (for daily/random regression) while every test still has a
sensible, reproducible default seed when run standalone via `make` (no
TPE_SEED set)."""
import os


def get_seed(default: int) -> int:
    val = os.environ.get("TPE_SEED")
    return int(val) if val is not None else default
