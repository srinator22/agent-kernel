"""Tests for refuse_shell_stdin.py: its own self-test plus hook JSON fed through the real script.

Run: python -I -m unittest discover -s scripts/hooks/tests (tests/template/test_shell_stdin_hook.sh runs it)
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


class LongCommandWarning(unittest.TestCase):
    """--warn-long: a long command still runs, and the model gets one line of context about it."""

    def context(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        if not result.stdout.strip():
            return None
        out = json.loads(result.stdout)
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "PreToolUse")
        self.assertNotIn("permissionDecision", out["hookSpecificOutput"])
        return out["hookSpecificOutput"]["additionalContext"]

    def test_long_command_gets_context_and_runs(self):
        text = self.context(run_hook(bash("echo " + "x" * 4100), args=["--warn-long"]))
        self.assertIsNotNone(text)
        self.assertIn("4105 bytes", text)
        self.assertIn("write", text)

    def test_limit_is_bytes_not_characters(self):
        # 2050 two-byte characters: 4100 bytes, 2055 characters with the echo.
        self.assertIsNotNone(self.context(run_hook(bash("echo " + "é" * 2050), args=["--warn-long"])))

    def test_at_the_limit_is_silent(self):
        self.assertIsNone(self.context(run_hook(bash("x" * 4096), args=["--warn-long"])))
        self.assertIsNone(self.context(run_hook(bash("echo short"), args=["--warn-long"])))

    def test_off_without_the_flag(self):
        result = run_hook(bash("echo " + "x" * 5000))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_refusal_wins_over_the_warning(self):
        result = run_hook(bash("cat > f <<EOF\n" + "x" * 5000 + "\nEOF"), args=["--warn-long"])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_malformed_input_prints_nothing(self):
        for raw in ("not json", "[1]", json.dumps({"tool_input": {"command": 7}})):
            with self.subTest(raw=raw):
                result = run_hook(None, args=["--warn-long"], raw=raw)
                self.assertEqual((result.returncode, result.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
