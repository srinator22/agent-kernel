"""Tests for refuse_shell_stdin.py: its own self-test plus hook JSON fed through the real script.

Run: python -I -m unittest discover -s docs/library/hooks/tests
Fixtures are written inline to a temporary folder; nothing outside it is touched.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parent.parent / "refuse_shell_stdin.py"


def run_hook(payload, args=(), env_extra=None, raw=None):
    env = {k: v for k, v in os.environ.items() if k != "HOOK_CHECK_PCBNEW_GETWIDTH"}
    env.update(env_extra or {})
    text = raw if raw is not None else json.dumps(payload)
    return subprocess.run([sys.executable, "-I", str(HOOK), *args], input=text, text=True,
                          capture_output=True, env=env, check=False)


def bash(command, cwd=""):
    return {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd}


class SelfTest(unittest.TestCase):
    def test_self_test_passes(self):
        result = subprocess.run([sys.executable, "-I", str(HOOK), "--self-test"], text=True,
                                capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test: PASS", result.stdout)

    def test_help_works(self):
        result = subprocess.run([sys.executable, "-I", str(HOOK), "--help"], text=True,
                                capture_output=True, check=False)
        self.assertEqual(result.returncode, 0)
        self.assertIn("PreToolUse", result.stdout)


class StdinAndHeredoc(unittest.TestCase):
    def test_python_dash_is_refused(self):
        result = run_hook(bash("echo 1 | python -"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("stdin", result.stderr)

    def test_heredoc_is_refused(self):
        result = run_hook(bash("cat > f.txt <<'EOF'\nx\nEOF"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("here-document", result.stderr)

    def test_normal_commands_run(self):
        for command in ("python tools/x.py --arg", "python -c \"print(1)\"", "git status", "cat <<< hi", ""):
            with self.subTest(command=command):
                self.assertEqual(run_hook(bash(command)).returncode, 0)

    def test_refusal_message_is_generic(self):
        message = run_hook(bash("python -")).stderr
        for token in ("DM-", "DEFECT_MEMORY", ".claude/hooks"):
            self.assertNotIn(token, message)

    def test_malformed_input_never_refuses(self):
        self.assertEqual(run_hook(None, raw="not json").returncode, 0)
        self.assertEqual(run_hook(None, raw="[1, 2]").returncode, 0)
        self.assertEqual(run_hook({"tool_input": "string"}).returncode, 0)
        self.assertEqual(run_hook({"tool_input": {"command": 7}}).returncode, 0)
        self.assertEqual(run_hook({}).returncode, 0)


class OptionalPcbnewRule(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = self.tmp.name
        Path(self.dir, "bad.py").write_text("import pcbnew\nprint(t.GetWidth())\n", encoding="utf-8")
        Path(self.dir, "ok.py").write_text("import pcbnew\nprint(t.GetWidth(pcbnew.F_Cu))\n", encoding="utf-8")

    def test_off_by_default(self):
        self.assertEqual(run_hook(bash("python bad.py", self.dir)).returncode, 0)

    def test_flag_enables(self):
        result = run_hook(bash("python bad.py", self.dir), args=["--check-pcbnew-getwidth"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("GetWidth", result.stderr)
        self.assertIn("line 2", result.stderr)

    def test_env_enables(self):
        result = run_hook(bash("python bad.py", self.dir), env_extra={"HOOK_CHECK_PCBNEW_GETWIDTH": "1"})
        self.assertEqual(result.returncode, 2)

    def test_env_zero_is_off(self):
        result = run_hook(bash("python bad.py", self.dir), env_extra={"HOOK_CHECK_PCBNEW_GETWIDTH": "0"})
        self.assertEqual(result.returncode, 0)

    def test_guarded_script_passes_when_enabled(self):
        result = run_hook(bash("python ok.py", self.dir), args=["--check-pcbnew-getwidth"])
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
