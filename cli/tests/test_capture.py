"""Tests for _capture — output capture utilities."""

import io
import sys

from sandbox_cli._capture import (
    CapturedExec,
    _truncate,
    make_capture_console,
    run_captured,
    suppress_stdout,
)


# ── make_capture_console ─────────────────────────────────────────────────


class TestMakeCaptureConsole:
    def test_writes_to_buffer(self):
        console = make_capture_console()
        console.print("hello")
        output = console.file.getvalue()
        assert "hello" in output

    def test_no_stdout_leak(self, capsys):
        console = make_capture_console()
        console.print("secret")
        captured = capsys.readouterr()
        assert "secret" not in captured.out

    def test_buffer_is_stringio(self):
        console = make_capture_console()
        assert isinstance(console.file, io.StringIO)

    def test_multiple_writes(self):
        console = make_capture_console()
        console.print("first")
        console.print("second")
        output = console.file.getvalue()
        assert "first" in output
        assert "second" in output


# ── suppress_stdout ──────────────────────────────────────────────────────


class TestSuppressStdout:
    def test_suppresses_print(self, capsys):
        with suppress_stdout():
            print("hidden")
        captured = capsys.readouterr()
        assert "hidden" not in captured.out

    def test_restores_stdout(self):
        original = sys.stdout
        with suppress_stdout():
            pass
        assert sys.stdout is original

    def test_restores_stdout_on_exception(self):
        original = sys.stdout
        try:
            with suppress_stdout():
                raise ValueError("boom")
        except ValueError:
            pass
        assert sys.stdout is original


# ── run_captured ─────────────────────────────────────────────────────────


class TestRunCaptured:
    def test_captures_console_output(self):
        def fn(console=None):
            console.print("captured text")

        output = run_captured(fn)
        assert "captured text" in output

    def test_passes_args(self):
        def fn(x, y, console=None):
            console.print(f"{x + y}")

        output = run_captured(fn, 3, 4)
        assert "7" in output

    def test_passes_kwargs(self):
        def fn(msg="", console=None):
            console.print(msg)

        output = run_captured(fn, msg="kwarg-value")
        assert "kwarg-value" in output


# ── _truncate ────────────────────────────────────────────────────────────


class TestTruncate:
    def test_no_op_under_limit(self):
        text = "short"
        assert _truncate(text, max_chars=100) == text

    def test_truncates_over_limit(self):
        text = "a" * 200
        result = _truncate(text, max_chars=50)
        assert len(result) < 200
        assert result.endswith("[output truncated]")

    def test_exact_limit(self):
        text = "x" * 100
        assert _truncate(text, max_chars=100) == text

    def test_empty_string(self):
        assert _truncate("", max_chars=100) == ""


# ── CapturedExec ─────────────────────────────────────────────────────────


class TestCapturedExec:
    def test_fields(self):
        c = CapturedExec(stdout="out", stderr="err", exit_code=0)
        assert c.stdout == "out"
        assert c.stderr == "err"
        assert c.exit_code == 0
