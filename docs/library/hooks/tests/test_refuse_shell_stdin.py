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


ROOT = Path(__file__).resolve().parents[4]
SETTINGS = ROOT / ".claude" / "settings.json"


def settings_hook_commands():
    """Commands of the PreToolUse entries whose matcher covers both shells."""
    data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    found = []
    for entry in data["hooks"]["PreToolUse"]:
        if entry.get("matcher") == "Bash|PowerShell":
            found += [h["command"] for h in entry["hooks"] if h.get("type") == "command"]
    return found


class SettingsWiring(unittest.TestCase):
    """The hook as .claude/settings.json runs it: the configured command, fed the payload on stdin."""

    def wired_command(self):
        cmds = [c for c in settings_hook_commands() if "refuse_shell_stdin" in c]
        self.assertEqual(len(cmds), 1, "settings.json must wire refuse_shell_stdin once under Bash|PowerShell")
        return cmds[0]

    def run_wired(self, command, cwd=None):
        bash = os.environ.get("BASH_EXE") or "bash"
        env = dict(os.environ, CLAUDE_PROJECT_DIR=str(ROOT).replace("\\", "/"))
        env.pop("HOOK_CHECK_PCBNEW_GETWIDTH", None)
        return subprocess.run([bash, "-c", self.wired_command()], input=json.dumps(bash_payload(command, cwd)),
                              text=True, capture_output=True, env=env, check=False)

    def test_existing_guard_stays_wired(self):
        self.assertTrue(any("scripts/destructive-guard.sh" in c for c in settings_hook_commands()))

    def test_here_document_refused(self):
        result = self.run_wired("cat > f.py <<'EOF'\nprint(1)\nEOF")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("here-document", result.stderr)

    def test_python_stdin_refused(self):
        result = self.run_wired("python -")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("stdin", result.stderr)

    def test_git_commit_dash_f_file_passes(self):
        result = self.run_wired("git commit -F /tmp/msg.txt")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ordinary_commands_pass(self):
        for command in ("ls -la", "python tools/check_thing.py", 'python -c "print(1)"'):
            with self.subTest(command=command):
                self.assertEqual(self.run_wired(command).returncode, 0)


def bash_payload(command, cwd=None):
    return bash(command, cwd or "")


if __name__ == "__main__":
    unittest.main()
