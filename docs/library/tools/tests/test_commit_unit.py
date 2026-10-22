"""Tests for commit_unit.py against throwaway git repositories (a local bare repository is the remote).

Run: python -I -m unittest discover -s docs/library/tools/tests
No network, no global git configuration, nothing outside the temporary folders is touched.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent / "commit_unit.py"
GIT = shutil.which("git")
PY = f'"{sys.executable}"'


def clean_env():
    env = dict(os.environ)
    env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_TERMINAL_PROMPT": "0",
                "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
                "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"})
    return env


def git(cwd, *args):
    done = subprocess.run([GIT, *args], cwd=cwd, env=clean_env(), text=True, capture_output=True, check=False)
    if done.returncode != 0:
        raise AssertionError(f"git {args} failed: {done.stdout}{done.stderr}")
    return done.stdout.strip()


@unittest.skipUnless(GIT, "git is not installed")
class CommitUnitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.remote = base / "remote.git"
        self.repo = base / "repo"
        self.repo.mkdir()
        git(base, "init", "-q", "--bare", "-b", "main", str(self.remote))
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "remote", "add", "origin", str(self.remote))
        self.write("owned/a.txt", "a\n")
        self.write("other/b.txt", "b\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "init")
        git(self.repo, "push", "-q", "origin", "main")
        self.msg = base / "msg.txt"
        self.msg.write_text("feat: change a\n\nbody line\n", encoding="utf-8")

    def write(self, rel, text):
        p = self.repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def run_tool(self, *extra, paths=("owned/a.txt",), msg=None, allowed=("owned",)):
        argv = [sys.executable, "-I", str(TOOL), "--root", str(self.repo), "-F", str(msg or self.msg)]
        for a in allowed:
            argv += ["--allowed", a]
        argv += list(extra) + ["--", *paths]
        return subprocess.run(argv, cwd=self.repo, env=clean_env(), text=True, capture_output=True, check=False)

    def head_files(self):
        return set(git(self.repo, "show", "--format=", "--name-only", "HEAD").split())

    def test_help_works(self):
        done = subprocess.run([sys.executable, "-I", str(TOOL), "--help"], text=True, capture_output=True)
        self.assertEqual(done.returncode, 0)
        self.assertIn("--gate-cmd", done.stdout)

    def test_commit_and_push_only_the_named_path(self):
        self.write("owned/a.txt", "a2\n")
        self.write("other/b.txt", "b2\n")            # unrelated edit stays out
        git(self.repo, "add", "other/b.txt")         # and so does an unrelated staged file
        done = self.run_tool("--gate-cmd", f'{PY} -c "import sys; sys.exit(0)"')
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("pushed to origin", done.stdout)
        self.assertEqual(self.head_files(), {"owned/a.txt"})
        self.assertEqual(git(self.repo, "log", "-1", "--format=%B").splitlines()[0], "feat: change a")
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), git(self.remote, "rev-parse", "main"))
        self.assertIn("other/b.txt", git(self.repo, "diff", "--cached", "--name-only"))

    def test_failing_gate_refuses_and_commits_nothing(self):
        self.write("owned/a.txt", "a2\n")
        before = git(self.repo, "rev-parse", "HEAD")
        done = self.run_tool("--gate-cmd", f'{PY} -c "print(\'gate says no\'); import sys; sys.exit(3)"')
        self.assertEqual(done.returncode, 1)
        self.assertIn("gate says no", done.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), before)

    def test_gate_pass_regex_is_required_in_the_output(self):
        self.write("owned/a.txt", "a2\n")
        silent = self.run_tool("--gate-cmd", f'{PY} -c "pass"', "--gate-pass-regex", "^Overall: PASS$")
        self.assertEqual(silent.returncode, 1)
        loud = self.run_tool("--gate-cmd", f'{PY} -c "print(\'Overall: PASS\')"',
                             "--gate-pass-regex", "^Overall: PASS$", "--no-push")
        self.assertEqual(loud.returncode, 0, loud.stdout + loud.stderr)
        self.assertIn("not pushed", loud.stdout)

    def test_path_outside_allowed_is_refused_before_the_gate(self):
        self.write("other/b.txt", "b2\n")
        marker = Path(self.tmp.name) / "gate_ran"
        gate = f'{PY} -c "open(r\'{marker}\', \'w\').close()"'
        done = self.run_tool("--gate-cmd", gate, paths=("other/b.txt",))
        self.assertEqual(done.returncode, 2)
        self.assertIn("outside the allowed paths", done.stderr)
        self.assertFalse(marker.exists())

    def test_path_outside_root_is_refused(self):
        done = self.run_tool("--gate-cmd", f'{PY} -c "pass"', paths=("../elsewhere.txt",), allowed=())
        self.assertEqual(done.returncode, 2)
        self.assertIn("outside the repository root", done.stderr)

    def test_unknown_path_is_refused_before_the_gate(self):
        marker = Path(self.tmp.name) / "gate_ran"
        gate = f'{PY} -c "open(r\'{marker}\', \'w\').close()"'
        done = self.run_tool("--gate-cmd", gate, paths=("owned/typo.txt",))
        self.assertEqual(done.returncode, 2)
        self.assertIn("not in the working tree or the index", done.stderr)
        self.assertFalse(marker.exists())

    def test_missing_message_file_and_empty_message_are_refused(self):
        done = self.run_tool("--gate-cmd", f'{PY} -c "pass"', msg=Path(self.tmp.name) / "none.txt")
        self.assertEqual(done.returncode, 2)
        empty = Path(self.tmp.name) / "empty.txt"
        empty.write_text("  \n", encoding="utf-8")
        done = self.run_tool("--gate-cmd", f'{PY} -c "pass"', msg=empty)
        self.assertEqual(done.returncode, 2)

    def test_no_gate_and_no_skip_is_refused(self):
        self.write("owned/a.txt", "a2\n")
        self.assertEqual(self.run_tool().returncode, 2)

    def test_skip_gate_needs_a_reason_and_writes_the_footer(self):
        self.write("owned/a.txt", "a2\n")
        self.assertEqual(self.run_tool("--skip-gate").returncode, 2)
        done = self.run_tool("--skip-gate", "--reason", "docs only", "--no-push")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("gate skipped: docs only", git(self.repo, "log", "-1", "--format=%B"))
        self.assertNotIn("gate skipped", self.msg.read_text(encoding="utf-8"))

    def test_file_edited_during_the_gate_is_refused(self):
        self.write("owned/a.txt", "a2\n")
        before = git(self.repo, "rev-parse", "HEAD")
        gate = f'{PY} -c "open(r\'{self.repo / "owned" / "a.txt"}\', \'a\').write(\'late edit\\n\')"'
        done = self.run_tool("--gate-cmd", gate)
        self.assertEqual(done.returncode, 1)
        self.assertIn("changed during the gate: owned/a.txt", done.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), before)

    def test_staged_deletion_is_committed_without_git_add(self):
        git(self.repo, "rm", "-q", "owned/a.txt")
        done = self.run_tool("--skip-gate", "--reason", "deletion", "--no-push")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("committed without git add", done.stdout)
        self.assertEqual(self.head_files(), {"owned/a.txt"})
        self.assertFalse((self.repo / "owned" / "a.txt").exists())

    def test_folder_path_commits_new_files_under_it(self):
        self.write("owned/new/c.txt", "c\n")
        done = self.run_tool("--skip-gate", "--reason", "new file", "--no-push", paths=("owned",))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.head_files(), {"owned/new/c.txt"})

    def test_dry_run_commits_nothing(self):
        self.write("owned/a.txt", "a2\n")
        before = git(self.repo, "rev-parse", "HEAD")
        done = self.run_tool("--gate-cmd", f'{PY} -c "pass"', "--dry-run")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), before)

    def test_non_fast_forward_push_is_reported_and_commit_kept_local(self):
        other = Path(self.tmp.name) / "other_clone"
        git(Path(self.tmp.name), "clone", "-q", str(self.remote), str(other))
        (other / "other").mkdir(exist_ok=True)
        (other / "other" / "z.txt").write_text("z\n", encoding="utf-8")
        git(other, "add", "-A")
        git(other, "commit", "-q", "-m", "remote moves")
        git(other, "push", "-q", "origin", "main")
        self.write("owned/a.txt", "a2\n")
        done = self.run_tool("--skip-gate", "--reason", "x")
        self.assertEqual(done.returncode, 1)
        self.assertIn("push to origin FAILED", done.stderr)
        self.assertEqual(git(self.repo, "log", "-1", "--format=%s"), "feat: change a")
        self.assertNotEqual(git(self.repo, "rev-parse", "HEAD"), git(self.remote, "rev-parse", "main"))

    def test_force_options_never_reach_git(self):
        sys.path.insert(0, str(TOOL.parent))
        self.addCleanup(sys.path.remove, str(TOOL.parent))
        import commit_unit
        for bad in (["git", "push", "--force"], ["git", "push", "-f"], ["git", "push", "origin", "+main"]):
            with self.assertRaises(RuntimeError):
                commit_unit._refuse_force(bad)
        commit_unit._refuse_force(["git", "commit", "-q", "--", "-f-named-file"])  # after -- is a path


if __name__ == "__main__":
    unittest.main()
