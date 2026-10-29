"""Tests for render_chunks.py with a fake renderer (a Python script that writes small placeholder frames).

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
import render_chunks as rc  # noqa: E402

FAKE_RENDER = r'''
import sys
first, last, out, calls, modefile, device, log = sys.argv[1:8]
first, last = int(first), int(last)
with open(calls, "a", encoding="utf-8") as fh:
    fh.write("%d %d %s\n" % (first, last, device))
with open(modefile, "r", encoding="utf-8") as fh:
    mode = fh.read().split()
print("fake render", first, last, "log", log)
skip = int(mode[1]) if len(mode) > 1 else None
for n in range(first, last + 1):
    if mode[0] == "skip" and n == skip:
        continue
    if mode[0] == "crash_after" and n > skip:
        sys.exit(1)
    with open("%s/frame_%04d.png" % (out, n), "wb") as fh:
        fh.write(b"" if (mode[0] == "zero" and n == skip) else b"PNGDATA")
sys.exit(1 if mode[0] == "fail_after_all" else 0)
'''


def run_main(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = rc.main(argv)
        except SystemExit as exc:
            code = exc.code
    return code, out.getvalue(), err.getvalue()


class RenderChunksTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = os.path.realpath(self.tmp.name)
        self.jobs = os.path.join(self.dir, "jobs")
        os.makedirs(self.jobs)
        self.out = os.path.join(self.dir, "frames")
        self.state = os.path.join(self.jobs, "gpu0.json")
        self.calls = os.path.join(self.dir, "calls.txt")
        self.modefile = os.path.join(self.dir, "mode.txt")
        self.set_mode("ok")
        self.fake = os.path.join(self.dir, "fake_render.py")
        with open(self.fake, "w", encoding="utf-8") as fh:
            fh.write(FAKE_RENDER)

    def set_mode(self, text):
        with open(self.modefile, "w", encoding="utf-8") as fh:
            fh.write(text)

    def cmd_json(self, exe=None):
        return json.dumps([exe or sys.executable, self.fake, "{first}", "{last}", "{out}", self.calls,
                           self.modefile, "{device}", "{log}"])

    def plan_args(self, state=None, first=1, last=10, chunk=4, out=None, **extra):
        argv = ["plan", "--state", state or self.state, "--first", str(first), "--last", str(last),
                "--chunk", str(chunk), "--out", out or self.out, "--cmd", self.cmd_json()]
        for key, value in extra.items():
            argv += [f"--{key.replace('_', '-')}"] + ([] if value is True else [str(value)])
        return argv

    def plan(self, **kw):
        code, out, err = run_main(self.plan_args(**kw))
        self.assertEqual(code, 0, out + err)
        return out

    def load(self, path=None):
        with open(path or self.state, encoding="utf-8") as fh:
            return json.load(fh)

    def call_lines(self):
        if not os.path.exists(self.calls):
            return []
        with open(self.calls, encoding="utf-8") as fh:
            return [line.split() for line in fh.read().splitlines()]

    def put_frame(self, n, data=b"PNGDATA"):
        os.makedirs(self.out, exist_ok=True)
        with open(os.path.join(self.out, "frame_%04d.png" % n), "wb") as fh:
            fh.write(data)

    # ---- plan -----------------------------------------------------------------------------------------
    def test_plan_builds_chunks(self):
        self.plan(device="3")
        st = self.load()
        spans = [(c["first"], c["last"]) for c in st["chunks"]]
        self.assertEqual(spans, [(1, 4), (5, 8), (9, 10)])
        self.assertEqual({c["status"] for c in st["chunks"]}, {"todo"})
        self.assertEqual([c["index"] for c in st["chunks"]], [1, 2, 3])
        self.assertEqual(st["device"], "3")
        self.assertTrue(all(os.path.isabs(c["log"]) for c in st["chunks"]))
        self.assertEqual(len({c["log"] for c in st["chunks"]}), 3)
        self.assertTrue(all(c["started"] is None and c["seconds"] is None for c in st["chunks"]))

    def test_plan_single_frame_and_exact_multiple(self):
        self.plan(first=7, last=7, chunk=5)
        self.assertEqual(len(self.load()["chunks"]), 1)
        self.plan(first=0, last=7, chunk=4, force=True)
        self.assertEqual([(c["first"], c["last"]) for c in self.load()["chunks"]], [(0, 3), (4, 7)])

    def test_plan_refuses_relative_paths(self):
        for key, value in (("state", "rel.json"), ("out", "relframes"), ("logs", "rellogs")):
            with self.subTest(key=key):
                argv = self.plan_args()
                if key == "logs":
                    argv += ["--logs", value]
                else:
                    argv[argv.index(f"--{key}") + 1] = value
                code, _, err = run_main(argv)
                self.assertEqual(code, 2)
                self.assertIn("absolute", err)

    def test_plan_refuses_existing_state_unless_force(self):
        self.plan()
        code, _, err = run_main(self.plan_args())
        self.assertEqual(code, 2)
        self.assertIn("--force", err)
        self.plan(force=True)

    def test_plan_bad_numbers_pattern_and_cmd(self):
        cases = [self.plan_args(first=5, last=4), self.plan_args(chunk=0), self.plan_args(first=-1),
                 self.plan_args(pattern="frame.png"), self.plan_args(pattern="a_##_b_##.png"),
                 self.plan_args(pattern="sub/frame_####.png")]
        bad_cmds = ["not json", "[]", '"x"', '[1, 2]', '["python", "scene.py"]']
        for cmd in bad_cmds:
            argv = self.plan_args()
            argv[argv.index("--cmd") + 1] = cmd
            cases.append(argv)
        for argv in cases:
            with self.subTest(argv=argv[3:]):
                code, _, err = run_main(argv)
                self.assertEqual(code, 2)
                self.assertIn("render_chunks: ERROR", err)
        self.assertFalse(os.path.exists(self.state))

    def test_plan_refuses_out_in_git_work_tree(self):
        repo = os.path.join(self.dir, "repo")
        os.makedirs(os.path.join(repo, ".git"))
        inside = os.path.join(repo, "frames")
        code, _, err = run_main(self.plan_args(out=inside))
        self.assertEqual(code, 2)
        self.assertIn("git work tree", err)
        code, _, err = run_main(self.plan_args(out=inside, allow_in_repo=True))
        self.assertEqual(code, 0, err)

    def test_plan_warns_on_cloud_synced_out(self):
        code, _, err = run_main(self.plan_args(out=os.path.join(self.dir, "OneDrive", "frames")))
        self.assertEqual(code, 0)
        self.assertIn("WARNING", err)
        # Same segment list as render_common (review note: iCloudDrive was missing here).
        code, _, err = run_main(self.plan_args(out=os.path.join(self.dir, "iCloudDrive", "frames"),
                                               state=os.path.join(self.jobs, "icloud.json")))
        self.assertEqual(code, 0)
        self.assertIn("WARNING", err)

    def test_plan_overlap_with_other_state_same_out(self):
        self.plan(first=1, last=10)
        other = os.path.join(self.jobs, "gpu1.json")
        code, _, err = run_main(self.plan_args(state=other, first=10, last=20))
        self.assertEqual(code, 2)
        self.assertIn("overlap", err)
        code, _, err = run_main(self.plan_args(state=other, first=11, last=20, device="1"))
        self.assertEqual(code, 0, err)
        # same range but another output folder is fine
        third = os.path.join(self.jobs, "gpu2.json")
        code, _, err = run_main(self.plan_args(state=third, first=1, last=10, out=os.path.join(self.dir, "o2")))
        self.assertEqual(code, 0, err)
        # junk json files in the folder are ignored
        with open(os.path.join(self.jobs, "notes.json"), "w", encoding="utf-8") as fh:
            fh.write("{ not json")
        with open(os.path.join(self.jobs, "list.json"), "w", encoding="utf-8") as fh:
            fh.write("[1, 2]")
        fourth = os.path.join(self.jobs, "gpu3.json")
        code, _, err = run_main(self.plan_args(state=fourth, first=21, last=30))
        self.assertEqual(code, 0, err)

    def test_plan_force_may_replan_its_own_range(self):
        self.plan()
        code, _, err = run_main(self.plan_args(force=True))
        self.assertEqual(code, 0, err)

    # ---- run ------------------------------------------------------------------------------------------
    def test_run_renders_all_and_skips_on_rerun(self):
        self.plan(device="2")
        code, out, err = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0, out + err)
        self.assertIn("render_chunks: PASS", out)
        self.assertEqual(self.call_lines(), [["1", "4", "2"], ["5", "8", "2"], ["9", "10", "2"]])
        for n in range(1, 11):
            self.assertTrue(os.path.getsize(os.path.join(self.out, "frame_%04d.png" % n)) > 0)
        st = self.load()
        self.assertEqual({c["status"] for c in st["chunks"]}, {"done"})
        self.assertTrue(all(c["frames_rendered"] > 0 and c["seconds"] >= 0 for c in st["chunks"]))
        for c in st["chunks"]:
            with open(c["log"], encoding="utf-8") as fh:
                self.assertIn("fake render", fh.read())
        os.remove(self.calls)
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0)
        self.assertEqual(self.call_lines(), [])
        self.assertEqual([f for f in os.listdir(self.jobs) if ".tmp" in f], [])

    def test_run_rerenders_frames_deleted_from_a_done_chunk(self):
        # Regression: frames of a done chunk were deleted (to re-render after a scene change); run skipped
        # the chunk because its status was done, so nothing was rendered and the run still exited 0.
        self.plan()
        self.assertEqual(run_main(["run", "--state", self.state])[0], 0)
        os.remove(os.path.join(self.out, "frame_0006.png"))
        os.remove(self.calls)
        code, out, err = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0, out + err)
        self.assertEqual(self.call_lines(), [["6", "6", "0"]])
        self.assertTrue(os.path.getsize(os.path.join(self.out, "frame_0006.png")) > 0)

    def test_run_never_renders_present_frames_and_replaces_zero_size(self):
        self.plan(first=1, last=8, chunk=8)
        self.put_frame(1)
        self.put_frame(2)
        self.put_frame(4, b"")  # crash-truncated
        self.put_frame(5)
        code, out, err = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0, out + err)
        # missing: 3, 4, 6, 7, 8  -> two contiguous runs
        self.assertEqual([c[:2] for c in self.call_lines()], [["3", "4"], ["6", "8"]])
        self.assertEqual(self.load()["chunks"][0]["frames_rendered"], 5)

    def test_run_chunk_fully_present_is_done_without_command(self):
        self.plan(first=1, last=4, chunk=4)
        for n in range(1, 5):
            self.put_frame(n)
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0)
        self.assertEqual(self.call_lines(), [])
        chunk = self.load()["chunks"][0]
        self.assertEqual((chunk["status"], chunk["seconds"], chunk["frames_rendered"]), ("done", 0.0, 0))

    def test_failed_chunk_records_missing_and_resumes(self):
        self.plan(first=1, last=8, chunk=4)
        self.set_mode("skip 3")
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 1)
        self.assertIn("render_chunks: FAIL", out)
        st = self.load()
        self.assertEqual([c["status"] for c in st["chunks"]], ["failed", "done"])
        self.assertEqual(st["chunks"][0]["missing"], [3])
        self.assertEqual(st["chunks"][0]["frames_rendered"], 3)
        self.set_mode("ok")
        os.remove(self.calls)
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0, out)
        self.assertEqual(self.call_lines(), [["3", "3", "0"]])
        self.assertEqual({c["status"] for c in self.load()["chunks"]}, {"done"})

    def test_command_crash_midway_counts_progress(self):
        self.plan(first=1, last=6, chunk=6)
        self.set_mode("crash_after 2")
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 1)
        chunk = self.load()["chunks"][0]
        self.assertEqual(chunk["status"], "failed")
        self.assertEqual(chunk["missing"], [3, 4, 5, 6])
        self.assertEqual(chunk["returncodes"], [1])
        self.assertIn("4 frame(s) missing", out)

    def test_failed_command_with_every_frame_present_is_a_failure(self):
        # Regression (independent review): a chunk whose blender_run exited non-zero (a traceback after the
        # frames were written, a version mismatch with the lock) was marked done because every frame existed.
        self.plan(first=1, last=4, chunk=4)
        self.set_mode("fail_after_all")
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 1, out)
        chunk = self.load()["chunks"][0]
        self.assertEqual((chunk["status"], chunk["returncodes"], chunk["failed_rc"]), ("failed", [1], 1))
        self.assertIn("command returned 1", out)
        code, out, _ = run_main(["status", "--state", self.state])
        self.assertEqual(code, 1, out)
        # A re-run never passes frames a failed command wrote; it says to delete them and stays failed.
        os.remove(self.calls)
        self.set_mode("ok")
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 1, out)
        self.assertEqual(self.call_lines(), [])
        self.assertIn("delete them to render again", out)
        for n in range(1, 5):
            os.remove(os.path.join(self.out, "frame_%04d.png" % n))
        code, out, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0, out)
        self.assertEqual(self.call_lines(), [["1", "4", "0"]])
        self.assertNotIn("failed_rc", self.load()["chunks"][0])

    def test_zero_size_frame_written_by_command_is_a_failure(self):
        self.plan(first=1, last=3, chunk=3)
        self.set_mode("zero 2")
        code, _, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 1)
        self.assertEqual(self.load()["chunks"][0]["missing"], [2])

    def test_max_chunks_and_resume(self):
        self.plan()
        code, out, _ = run_main(["run", "--state", self.state, "--max-chunks", "1"])
        self.assertEqual(code, 1)
        self.assertEqual([c["status"] for c in self.load()["chunks"]], ["done", "todo", "todo"])
        code, _, _ = run_main(["run", "--state", self.state, "--max-chunks", "5"])
        self.assertEqual(code, 0)
        self.assertEqual(len(self.call_lines()), 3)

    def test_stop_on_fail_stops_and_default_continues(self):
        self.plan(first=1, last=12, chunk=4)
        self.set_mode("skip 2")
        run_main(["run", "--state", self.state, "--stop-on-fail"])
        self.assertEqual([c["status"] for c in self.load()["chunks"]], ["failed", "todo", "todo"])
        self.plan(force=True, first=1, last=12, chunk=4, out=os.path.join(self.dir, "other"))
        self.set_mode("skip 2")
        run_main(["run", "--state", self.state])
        statuses = [c["status"] for c in self.load()["chunks"]]
        self.assertEqual(statuses[0], "failed")
        self.assertNotIn("todo", statuses)

    def test_running_chunk_after_a_kill_is_run_again(self):
        self.plan(first=1, last=4, chunk=4)
        st = self.load()
        st["chunks"][0]["status"] = "running"
        with open(self.state, "w", encoding="utf-8") as fh:
            json.dump(st, fh)
        self.put_frame(1)
        code, _, _ = run_main(["run", "--state", self.state])
        self.assertEqual(code, 0)
        self.assertEqual([c[:2] for c in self.call_lines()], [["2", "4"]])

    def test_command_that_cannot_start_exits_2_and_marks_failed(self):
        code, _, _ = run_main(["plan", "--state", self.state, "--first", "1", "--last", "4", "--chunk", "4",
                               "--out", self.out, "--cmd",
                               json.dumps([os.path.join(self.dir, "no-such-exe.exe"), "{first}"])])
        self.assertEqual(code, 0)
        code, _, err = run_main(["run", "--state", self.state])
        self.assertEqual(code, 2)
        self.assertIn("cannot start", err)
        self.assertEqual(self.load()["chunks"][0]["status"], "failed")

    def test_bad_state_exits_2(self):
        absent = os.path.join(self.jobs, "absent.json")
        junk = os.path.join(self.jobs, "junk.json")
        with open(junk, "w", encoding="utf-8") as fh:
            fh.write("{ nope")
        self.plan()
        good = self.load()
        variants = {}
        variants["wrongtool"] = dict(good, tool="other")
        variants["nochunks"] = dict(good, chunks=[])
        variants["badstatus"] = dict(good, chunks=[dict(good["chunks"][0], status="weird")])
        # Regression (review note): a chunk without an index passed validation and crashed later (exit 1).
        variants["noindex"] = dict(good, chunks=[{k: v for k, v in good["chunks"][0].items() if k != "index"}])
        variants["badrange"] = dict(good, last=0)
        variants["relout"] = dict(good, out="rel")
        variants["nopattern"] = dict(good, pattern="frame.png")
        variants["badcmd"] = dict(good, cmd="python")
        variants["notdict"] = [1]
        paths = {absent: None, junk: None}
        for name, data in variants.items():
            path = os.path.join(self.jobs, f"{name}.json")
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh)
            paths[path] = None
        for path in paths:
            for sub in ("run", "status"):
                with self.subTest(state=os.path.basename(path), sub=sub):
                    code, _, err = run_main([sub, "--state", path])
                    self.assertEqual(code, 2)
                    self.assertIn("render_chunks: ERROR", err)
        code, _, err = run_main(["run", "--state", "rel.json"])
        self.assertEqual(code, 2)

    def test_argparse_errors_exit_2(self):
        for argv in ([], ["bogus"], ["run"], ["run", "--state", self.state, "--max-chunks", "x"]):
            with self.subTest(argv=argv):
                self.assertEqual(run_main(argv)[0], 2)
        self.plan()
        self.assertEqual(run_main(["run", "--state", self.state, "--max-chunks", "0"])[0], 2)

    # ---- status ---------------------------------------------------------------------------------------
    def test_status_all_done_and_json(self):
        self.plan()
        run_main(["run", "--state", self.state])
        report = os.path.join(self.dir, "status.json")
        code, out, _ = run_main(["status", "--state", self.state, "--json", report])
        self.assertEqual(code, 0, out)
        self.assertIn("frames present 10/10", out)
        self.assertIn("render_chunks: PASS", out)
        with open(report, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data["status"], "pass")
        self.assertEqual(data["frames_missing"], 0)
        self.assertGreaterEqual(data["seconds_per_frame"], 0)

    def test_status_before_run_has_no_measurement(self):
        self.plan()
        code, out, _ = run_main(["status", "--state", self.state])
        self.assertEqual(code, 1)
        self.assertIn("ETA unknown", out)
        self.assertIn("frames present 0/10", out)

    def test_status_measured_rate_and_eta(self):
        self.plan(first=1, last=10, chunk=5)
        st = self.load()
        st["chunks"][0].update(status="done", seconds=20.0, frames_rendered=5)
        with open(self.state, "w", encoding="utf-8") as fh:
            json.dump(st, fh)
        for n in range(1, 6):
            self.put_frame(n)
        code, out, _ = run_main(["status", "--state", self.state])
        self.assertEqual(code, 1)
        self.assertIn("4.000 s/frame over 5 frame(s) in 1 chunk(s)", out)
        self.assertIn("ETA 0:00:20 for 5 frame(s)", out)

    def test_status_done_chunk_with_deleted_frame_is_flagged(self):
        self.plan(first=1, last=4, chunk=4)
        run_main(["run", "--state", self.state])
        os.remove(os.path.join(self.out, "frame_0003.png"))
        code, out, _ = run_main(["status", "--state", self.state])
        self.assertEqual(code, 1)
        self.assertIn("done but 1 frame(s) are missing now", out)

    def test_helpers(self):
        self.assertEqual(rc.frame_name("shot_####.exr", 7), "shot_0007.exr")
        self.assertEqual(rc.frame_name("f#.png", 1234), "f1234.png")
        self.assertEqual(rc.runs_of([1, 2, 4, 7, 8, 9]), [(1, 2), (4, 4), (7, 9)])
        self.assertEqual(rc.runs_of([]), [])
        self.assertEqual(rc.fmt_duration(3725), "1:02:05")
        self.assertEqual(rc.expand(["a{first}-{last}", "{out}", "{device}", "{log}", "{x}"], 1, 2, "O", "D", "L"),
                         ["a1-2", "O", "D", "L", "{x}"])


if __name__ == "__main__":
    unittest.main()
