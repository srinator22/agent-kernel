"""Tests for blender_run.py using fake Blender executables (Python scripts run with sys.executable).

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
No Blender, GPU or network is used.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import blender_run  # noqa: E402

FAKE_TEMPLATE = r'''
import json, runpy, sys, traceback
args = sys.argv[1:]
VERSION_LINE = %(version_line)r
VERSION_LAST = %(version_last)r
if VERSION_LINE and not VERSION_LAST:
    print(VERSION_LINE)
print("ARGV " + json.dumps(args))
sys.stdout.flush()
exit_code = 0
IGNORE_SCRIPT = %(ignore_script)r
if "-P" in args and not IGNORE_SCRIPT:
    script = args[args.index("-P") + 1]
    extra = args[args.index("--") + 1:] if "--" in args else []
    sys.argv = [script] + extra
    try:
        runpy.run_path(script, run_name="__main__")
    except SystemExit as exc:
        exit_code = exc.code if isinstance(exc.code, int) else 1
    except BaseException:
        traceback.print_exc()
        exit_code = int(args[args.index("--python-exit-code") + 1]) if "--python-exit-code" in args else 0
if VERSION_LINE and VERSION_LAST:  # Blender 5.2.3 in -b mode prints its banner after the script output
    print(VERSION_LINE)
sys.exit(exit_code)
'''


def run_main(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = blender_run.main(argv)
        except SystemExit as exc:  # argparse
            code = exc.code
    return code, out.getvalue(), err.getvalue()


class BlenderRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = os.path.realpath(self.tmp.name)
        self.log = os.path.join(self.dir, "logs", "run.log")  # parent does not exist yet
        self.record = os.path.join(self.dir, "run.json")

    def write(self, name, text):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return path

    def fake(self, name="fake_blender.py", version_line="Blender 5.2.3 (hash abc)", ignore_script=False,
             version_last=False):
        return self.write(name, FAKE_TEMPLATE % {"version_line": version_line, "ignore_script": ignore_script,
                                                 "version_last": version_last})

    def test_version_banner_after_long_script_output(self):
        # Regression: 5.2.3 prints the banner after the script; a scan of only the first lines missed it.
        script = self.write("chatty.py", "for i in range(40):\n    print('line', i)\n")
        fake = self.fake(version_line="Blender 5.2.3 LTS (hash e13b728c6880 built 2026-10-22 01:37:16)",
                         version_last=True)
        code, out, err = run_main(["--blender-cmd", self.cmd(fake),
                                   "--log", self.log, "--record", self.record, script])
        self.assertEqual(code, 0, out + err)
        with open(self.record, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh)["blender_version"], "5.2.3")

    def test_script_text_mentioning_blender_is_not_the_banner(self):
        script = self.write("talk.py", "print('Blender 4.5 is the old LTS')\n")
        fake = self.fake(version_line="Blender 5.2.3 LTS (hash abc built x)", version_last=True)
        code, out, err = run_main(["--blender-cmd", self.cmd(fake),
                                   "--log", self.log, "--record", self.record, script])
        self.assertEqual(code, 0, out + err)
        with open(self.record, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh)["blender_version"], "5.2.3")

    def cmd(self, fake):
        return json.dumps([sys.executable, fake])

    def lock(self, fake, version="5.2.3", sha256=None, name="blender.lock.json", path=None):
        # The lock path must be one executable; use a launcher script path that exists for the file check.
        data = {"version": version, "path": path or fake}
        if sha256:
            data["sha256"] = sha256
        return self.write(name, json.dumps(data))

    def test_pass_records_argv_and_version(self):
        script = self.write("ok.py", "import sys\nprint('script args', sys.argv[1:])\n")
        code, out, err = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log,
                                   "--record", self.record, script, "--", "a", "7"])
        self.assertEqual(code, 0, out + err)
        self.assertIn("blender_run: PASS", out)
        with open(self.log, encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("script args ['a', '7']", text)
        with open(self.record, encoding="utf-8") as fh:
            rec = json.load(fh)
        self.assertEqual(rec["status"], "pass")
        self.assertEqual(rec["blender_version"], "5.2.3")
        self.assertEqual(rec["returncode"], 0)
        argv = rec["argv"]
        tail = argv[argv.index("-b"):]
        self.assertEqual(tail, ["-b", "--factory-startup", "--python-exit-code", "1", "-P",
                                os.path.abspath(script), "--", "a", "7"])
        self.assertTrue(rec["start"] and rec["end"] and rec["cwd"])
        self.assertGreaterEqual(rec["seconds"], 0)

    def test_blend_goes_after_b(self):
        script = self.write("ok.py", "pass\n")
        blend = self.write("scene.blend", "x")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--blend", blend, "--log", self.log,
                                 "--record", self.record, script])
        self.assertEqual(code, 0, out)
        with open(self.record, encoding="utf-8") as fh:
            argv = json.load(fh)["argv"]
        i = argv.index("-b")
        self.assertEqual(argv[i + 1], os.path.abspath(blend))
        self.assertEqual(argv[i + 2], "--factory-startup")
        self.assertEqual(argv[-1], "--")

    def test_traceback_fails_with_line_number(self):
        script = self.write("boom.py", "raise ValueError('boom')\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log, script])
        self.assertEqual(code, 1)
        self.assertIn("traceback", out)
        self.assertIn("log line", out)
        self.assertIn("returncode", out)
        self.assertIn("blender_run: FAIL", out)

    def test_traceback_in_log_fails_even_with_rc_zero(self):
        # The script prints a traceback header but the process still exits 0.
        script = self.write("quiet.py", "print('Traceback (most recent call last):')\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log, script])
        self.assertEqual(code, 1)
        self.assertIn("traceback", out)
        self.assertNotIn("returncode", out)

    def test_error_line_fails_with_rc_zero(self):
        script = self.write("err.py", "print('Error: Python: something broke')\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log, script])
        self.assertEqual(code, 1)
        self.assertIn("script-error", out)

    def test_error_text_mid_line_is_not_a_finding(self):
        script = self.write("fine.py", "print('no Error: here and no trace')\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log, script])
        self.assertEqual(code, 0, out)

    def test_nonzero_return_code(self):
        script = self.write("exit3.py", "import sys\nsys.exit(3)\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log, script])
        self.assertEqual(code, 1)
        self.assertIn("return code 3", out)

    def test_many_errors_are_capped_and_counted(self):
        script = self.write("many.py", "for i in range(120):\n    print('Error: item', i)\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log, script])
        self.assertEqual(code, 1)
        self.assertIn("70 more log finding(s) not listed", out)
        self.assertEqual(out.count("script-error"), blender_run.MAX_LOG_FINDINGS)

    def test_timeout_kills_and_fails(self):
        script = self.write("slow.py", "import time\ntime.sleep(60)\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log,
                                 "--timeout", "1", script])
        self.assertEqual(code, 1)
        self.assertIn("timeout", out)

    def test_lock_version_match_and_prefix(self):
        self.assertTrue(blender_run.versions_agree("5.2.3", "5.2.3"))
        self.assertTrue(blender_run.versions_agree("5.2", "5.2.3"))
        self.assertFalse(blender_run.versions_agree("5.3", "5.2.3"))
        self.assertFalse(blender_run.versions_agree("5.2.30", "5.2.3"))
        self.assertFalse(blender_run.versions_agree("5.2.3.1", "5.2.3"))

    def test_lock_mismatch_and_missing_line_are_findings(self):
        # Drive execute() directly with the lock version so the fake command list can be used.
        script = self.write("ok.py", "pass\n")
        exe = [sys.executable, self.fake(version_line="Blender 4.2.0 (hash x)")]
        result = blender_run.execute(exe, "5.2.3", None, script, [], self.log, 30)
        kinds = [f["kind"] for f in result["findings"]]
        self.assertEqual(kinds, ["version"])
        self.assertIn("4.2.0", result["findings"][0]["text"])
        self.assertEqual(result["findings"][0]["line"], 1)
        exe = [sys.executable, self.fake(name="fake_nover.py", version_line="")]
        result = blender_run.execute(exe, "5.2.3", None, script, [], self.log, 30)
        self.assertEqual([f["kind"] for f in result["findings"]], ["version"])
        self.assertIn("cannot confirm", result["findings"][0]["text"])
        result = blender_run.execute(exe, None, None, script, [], self.log, 30)
        self.assertEqual(result["findings"], [])

    def test_lock_end_to_end_with_executable_script(self):
        # A lock whose path is a real executable file: use a tiny launcher that re-runs the fake.
        fake = self.fake()
        if os.name == "nt":
            launcher = self.write("blender.cmd", '@echo off\r\n"%s" "%s" %%*\r\n' % (sys.executable, fake))
        else:
            launcher = self.write("blender.sh", '#!/bin/sh\nexec "%s" "%s" "$@"\n' % (sys.executable, fake))
            os.chmod(launcher, 0o755)
        script = self.write("ok.py", "pass\n")
        lock = self.lock(launcher, version="5.2.3", sha256=blender_run.sha256_file(launcher))
        code, out, err = run_main(["--lock", lock, "--log", self.log, script])
        self.assertEqual(code, 0, out + err)
        lock = self.lock(launcher, version="5.9.9", name="other.lock.json")
        code, out, _ = run_main(["--lock", lock, "--log", self.log, script])
        self.assertEqual(code, 1)
        self.assertIn("lock pins 5.9.9", out)

    def test_lock_problems_exit_2(self):
        script = self.write("ok.py", "pass\n")
        fake = self.fake()
        missing = self.lock(fake, path=os.path.join(self.dir, "nope.exe"), name="a.json")
        code, _, err = run_main(["--lock", missing, "--log", self.log, script])
        self.assertEqual(code, 2)
        self.assertIn("blender_run: ERROR", err)
        badhash = self.lock(fake, sha256="0" * 64, name="b.json")
        code, _, err = run_main(["--lock", badhash, "--log", self.log, script])
        self.assertEqual(code, 2)
        self.assertIn("sha256", err)
        notjson = self.write("c.json", "{ nope")
        self.assertEqual(run_main(["--lock", notjson, "--log", self.log, script])[0], 2)
        nover = self.write("d.json", json.dumps({"path": fake}))
        self.assertEqual(run_main(["--lock", nover, "--log", self.log, script])[0], 2)
        self.assertEqual(run_main(["--lock", os.path.join(self.dir, "absent.json"), "--log", self.log,
                                   script])[0], 2)
        arr = self.write("e.json", "[1]")
        self.assertEqual(run_main(["--lock", arr, "--log", self.log, script])[0], 2)

    def test_bad_arguments_exit_2(self):
        fake = self.fake()
        cmd = self.cmd(fake)
        script = self.write("ok.py", "pass\n")
        cases = [
            ["--blender-cmd", cmd, script],  # no --log
            ["--blender-cmd", cmd, "--log", "relative.log", script],
            ["--blender-cmd", cmd, "--log", self.log],  # no script
            ["--blender-cmd", cmd, "--log", self.log, os.path.join(self.dir, "missing.py")],
            ["--blender-cmd", "not json", "--log", self.log, script],
            ["--blender-cmd", "[]", "--log", self.log, script],
            ["--blender-cmd", '["a", 3]', "--log", self.log, script],
            ["--blender-cmd", cmd, "--log", self.log, "--blend", os.path.join(self.dir, "x.blend"), script],
            ["--blender-cmd", cmd, "--log", self.log, "--timeout", "0", script],
            ["--blender", os.path.join(self.dir, "no-such-blender.exe"), "--log", self.log, script],
            ["--blender-cmd", json.dumps([os.path.join(self.dir, "no-such-exe.exe")]), "--log", self.log,
             script],
            [],  # nothing at all
            ["--blender", "a", "--blender-cmd", cmd, "--log", self.log, script],  # exclusive
        ]
        for argv in cases:
            with self.subTest(argv=argv):
                code, out, _ = run_main(argv)
                self.assertEqual(code, 2)
                self.assertNotIn("PASS", out)

    def test_help_exits_zero(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            with self.assertRaises(SystemExit) as ctx:
                blender_run.main(["--help"])
        self.assertEqual(ctx.exception.code, 0)
        self.assertIn("--self-test", out.getvalue())

    def test_empty_script_and_empty_output_pass(self):
        script = self.write("empty.py", "")
        fake = self.fake(version_line="")
        code, out, _ = run_main(["--blender-cmd", self.cmd(fake), "--log", self.log, script])
        self.assertEqual(code, 0, out)

    def test_script_args_with_dashes_pass_through(self):
        script = self.write("echo.py", "import sys\nprint('ARGS', sys.argv[1:])\n")
        code, out, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--log", self.log, script,
                                 "--", "--frames", "1-3", "--", "x"])
        self.assertEqual(code, 0, out)
        with open(self.log, encoding="utf-8") as fh:
            self.assertIn("ARGS ['--frames', '1-3', '--', 'x']", fh.read())

    def test_self_test_detects_failure(self):
        code, out, err = run_main(["--blender-cmd", self.cmd(self.fake()), "--self-test"])
        self.assertEqual(code, 0, out + err)
        self.assertIn("failure detected", out)

    def test_self_test_writes_its_record(self):
        # Regression: --self-test returned before --record was written, so the gate left no record.
        code, out, err = run_main(["--blender-cmd", self.cmd(self.fake()), "--self-test", "--log", self.log,
                                   "--record", self.record])
        self.assertEqual(code, 0, out + err)
        with open(self.record, encoding="utf-8") as fh:
            rec = json.load(fh)
        self.assertEqual((rec["self_test"], rec["status"], rec["blender_version"]), (True, "pass", "5.2.3"))
        self.assertNotEqual(rec["returncode"], 0)

    def test_self_test_fails_when_exception_goes_unnoticed(self):
        # A "Blender" that ignores the script exits 0 with a clean log: the gate must report it.
        fake = self.fake(name="fake_deaf.py", ignore_script=True)
        code, out, _ = run_main(["--blender-cmd", self.cmd(fake), "--self-test", "--log", self.log])
        self.assertEqual(code, 1)
        self.assertIn("blender_run: FAIL", out)

    def test_self_test_cannot_run_is_2(self):
        missing = json.dumps([os.path.join(self.dir, "no-such-exe.exe")])
        code, _, err = run_main(["--blender-cmd", missing, "--self-test"])
        self.assertEqual(code, 2)
        self.assertIn("blender_run: ERROR", err)
        code, _, _ = run_main(["--blender-cmd", self.cmd(self.fake()), "--self-test", "extra.py"])
        self.assertEqual(code, 2)

    def test_self_test_leaves_no_temp_folder(self):
        before = {n for n in os.listdir(tempfile.gettempdir()) if n.startswith("blender_run_selftest_")}
        run_main(["--blender-cmd", self.cmd(self.fake()), "--self-test"])
        after = {n for n in os.listdir(tempfile.gettempdir()) if n.startswith("blender_run_selftest_")}
        self.assertEqual(after - before, set())


if __name__ == "__main__":
    unittest.main()
