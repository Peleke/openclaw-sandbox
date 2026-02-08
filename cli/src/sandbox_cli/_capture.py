"""Output capture utilities for MCP stdio transport safety.

Rich console output and subprocess stdout must not leak into the MCP
stdio channel.  This module provides helpers to capture or suppress
output so tool implementations stay transport-safe.
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
from dataclasses import dataclass
from typing import Callable

from rich.console import Console


@dataclass
class CapturedExec:
    """Result of a captured subprocess execution."""

    stdout: str
    stderr: str
    exit_code: int


def make_capture_console() -> Console:
    """Return a Rich console that writes to an in-memory buffer.

    The caller can retrieve the output via ``console.file.getvalue()``.
    """
    return Console(file=io.StringIO(), force_terminal=False)


@contextlib.contextmanager
def suppress_stdout():
    """Context manager that redirects ``sys.stdout`` to ``os.devnull``.

    Useful when calling functions that may print directly (not via Rich)
    or when ``subprocess.run`` inherits stdout.
    """
    devnull = open(os.devnull, "w")
    old_stdout = sys.stdout
    try:
        sys.stdout = devnull
        yield
    finally:
        sys.stdout = old_stdout
        devnull.close()


def run_captured(fn: Callable[..., object], *args: object, **kwargs: object) -> str:
    """Call *fn* with a capture console and return the output text.

    The function must accept a ``console`` keyword argument (matching
    the pattern used by ``print_post_bootstrap`` and ``print_status_report``).
    """
    cap = make_capture_console()
    fn(*args, console=cap, **kwargs)
    return cap.file.getvalue()


def _truncate(text: str, max_chars: int = 50_000) -> str:
    """Truncate *text* to *max_chars*, appending a marker if clipped."""
    if len(text) <= max_chars:
        return text
    return text[:max_chars] + "\n\n[output truncated]"
