"""Shared test helpers for the hardware-pcb tools.

Each tool is a single self-contained script; the tests load it by file path so
they work under `python -I` (isolated mode does not put the script folder on
sys.path). Test fixtures are small, made-up documents written to temporary
folders.
"""

from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent.parent


def load_tool(name: str):
    """Import tools/<name>.py as a module without touching sys.path."""
    spec = importlib.util.spec_from_file_location(name, TOOLS_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def run_main(module, argv: list[str]) -> tuple[int, str]:
    """Run module.main(argv); return (exit code, captured stdout)."""
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        code = module.main(argv)
    return code, buffer.getvalue()


def of_level(findings, level: str) -> list:
    return [f for f in findings if f.level == level]


def joined(findings) -> str:
    return "\n".join(f"{f.check}: {f.message}" for f in findings)


class TempDirTestCase(unittest.TestCase):
    """A test case with a fresh temporary folder in self.root."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def write(self, relative: str, text: str | bytes) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(text, bytes):
            path.write_bytes(text)
        else:
            path.write_text(text, encoding="utf-8")
        return path
