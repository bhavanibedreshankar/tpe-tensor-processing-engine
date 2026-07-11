"""
Shared structured logging for all Python tooling (regression runner, test
generator, coverage merger, profiler, linter). Gives every tool the same
leveled, colorized console format plus optional per-run file logging under
sim/logs/, so regression output and interactive debugging look consistent.
"""
import logging
import sys
from pathlib import Path

_LEVEL_COLORS = {
    logging.DEBUG: "\033[90m",     # grey
    logging.INFO: "\033[36m",      # cyan
    logging.WARNING: "\033[33m",   # yellow
    logging.ERROR: "\033[31m",     # red
    logging.CRITICAL: "\033[1;31m",  # bold red
}
_RESET = "\033[0m"


class ColorFormatter(logging.Formatter):
    def __init__(self, use_color: bool = True):
        super().__init__(
            fmt="%(asctime)s %(levelname)-8s %(name)-16s %(message)s",
            datefmt="%H:%M:%S",
        )
        self.use_color = use_color

    def format(self, record: logging.LogRecord) -> str:
        msg = super().format(record)
        if self.use_color and record.levelno in _LEVEL_COLORS:
            return f"{_LEVEL_COLORS[record.levelno]}{msg}{_RESET}"
        return msg


def get_logger(name: str, log_file: "Path | None" = None, level: int = logging.INFO) -> logging.Logger:
    """Return a configured logger. Safe to call repeatedly for the same name."""
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger  # already configured

    logger.setLevel(level)
    logger.propagate = False

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(ColorFormatter(use_color=sys.stdout.isatty()))
    logger.addHandler(console)

    if log_file is not None:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_file, mode="w")
        file_handler.setFormatter(ColorFormatter(use_color=False))
        logger.addHandler(file_handler)

    return logger
