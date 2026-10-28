"""Tests for render_bundle.py (delivery folder, copies, README, sha256 manifest and its verification).

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
No network is used; everything happens in temporary folders.
"""
import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import render_bundle as rb  # noqa: E402


def run_main(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = rb.main(argv)
        except SystemExit as exc:
            code = exc.code
    return code, out.getvalue(), err.getvalue()


@contextlib.contextmanager
def chdir(path):
    old = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(old)


class RenderBundleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = os.path.realpath(self.tmp.name)
        self.dest = os.path.join(self.dir, "deliveries")
        self.work = os.path.join(self.dir, "work")
        os.makedirs(self.work)
        self.video = self.write("work/final.mp4", b"FAKEVIDEO" * 10)

    def write(self, rel, data):
        path = os.path.join(self.dir, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(data if isinstance(data, bytes) else data.encode("utf-8"))
        return path

    def bundle(self, *extra, version="v1", video=None, dest=None):
        return run_main(["--dest", dest or self.dest, "--version", version, "--video", video or self.video,
                         *extra])

    def folder(self, version="v1"):
        return os.path.join(self.dest, version)

    def listing(self, version="v1"):
        root = self.folder(version)
        found = []
        for base, _, files in os.walk(root):
            for f in files:
                found.append(os.path.relpath(os.path.join(base, f), root).replace(os.sep, "/"))
        return sorted(found)

    def read(self, rel, version="v1"):
        with open(os.path.join(self.folder(version), *rel.split("/")), "r", encoding="utf-8") as fh:
            return fh.read()

    # ---- happy path -------------------------------------------------------------------------------------
    def test_full_bundle_contents_readme_and_manifest(self):
        script = self.write("work/scene.py", "print('scene')\n")
        preset = self.write("work/presets/final.json", "{}")
        self.write("work/presets/sub/deep.json", "[]")
        commands = self.write("work/commands.txt", "python blender_run.py scene.py\npython render_chunks.py run\n")
        record = self.write("work/run1.json", json.dumps({"blender_version": "5.2.3", "returncode": 0}))
        code, out, err = self.bundle("--include", script, "--include", os.path.dirname(preset),
                                     "--commands", commands, "--record", record, "--note", "cold viewer passed")
        self.assertEqual(code, 0, out + err)
        self.assertIn("render_bundle: PASS", out)
        self.assertIn("manifest verified", out)
        self.assertEqual(self.listing(), [
            "MANIFEST.sha256", "README.txt", "final.mp4", "records/run1.json", "source/presets/final.json",
            "source/presets/sub/deep.json", "source/scene.py"])
        with open(os.path.join(self.folder(), "final.mp4"), "rb") as fh:
            self.assertEqual(fh.read(), b"FAKEVIDEO" * 10)
        readme = self.read("README.txt")
        self.assertIn("Delivery v1", readme)
        self.assertIn("Blender version: 5.2.3 (from run1.json)", readme)
        self.assertIn("python blender_run.py scene.py\npython render_chunks.py run", readme)
        self.assertIn("Note: cold viewer passed", readme)
        self.assertIn("sha256sum -c MANIFEST.sha256", readme)
        manifest = self.read("MANIFEST.sha256").splitlines()
        self.assertEqual(len(manifest), 6)  # every file except the manifest itself
        for line in manifest:
            digest, rel = line.split("  ", 1)
            with open(os.path.join(self.folder(), *rel.split("/")), "rb") as fh:
                self.assertEqual(digest, hashlib.sha256(fh.read()).hexdigest())
        self.assertEqual([line.split("  ", 1)[1] for line in manifest], sorted(l.split("  ", 1)[1] for l in manifest))
        self.assertNotIn("MANIFEST.sha256", self.read("MANIFEST.sha256"))

    def test_minimal_bundle(self):
        code, out, err = self.bundle()
        self.assertEqual(code, 0, out + err)
        self.assertEqual(self.listing(), ["MANIFEST.sha256", "README.txt", "final.mp4"])
        readme = self.read("README.txt")
        self.assertIn("not recorded", readme)
        self.assertIn("(no commands file was given)", readme)

    def test_empty_video_and_empty_include_folder(self):
        empty = self.write("work/empty.mp4", b"")
        os.makedirs(os.path.join(self.dir, "work", "emptydir"))
        code, out, _ = self.bundle("--include", os.path.join(self.dir, "work", "emptydir"), video=empty)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.listing(), ["MANIFEST.sha256", "README.txt", "empty.mp4"])

    def test_relative_includes_keep_their_names(self):
        self.write("work/render/scenes/a.py", "a")
        self.write("work/render/presets/p.json", "{}")
        self.write("work/outside.txt", "o")
        os.makedirs(os.path.join(self.work, "sub"))
        with chdir(self.work):
            code, out, err = self.bundle("--include", "render/scenes/a.py", "--include", "render/presets",
                                         "--include", "./outside.txt")
        self.assertEqual(code, 0, out + err)
        self.assertEqual([p for p in self.listing() if p.startswith("source/")],
                         ["source/outside.txt", "source/render/presets/p.json", "source/render/scenes/a.py"])
        with chdir(os.path.join(self.work, "sub")):
            code, out, _ = self.bundle("--include", "../outside.txt", version="v2")
        self.assertEqual(code, 0, out)
        self.assertEqual([p for p in self.listing("v2") if p.startswith("source/")], ["source/outside.txt"])

    def test_cache_and_git_folders_are_skipped(self):
        self.write("work/src/keep.py", "k")
        self.write("work/src/__pycache__/keep.pyc", "c")
        self.write("work/src/.git/config", "g")
        code, out, _ = self.bundle("--include", os.path.join(self.work, "src"))
        self.assertEqual(code, 0, out)
        self.assertEqual([p for p in self.listing() if p.startswith("source/")], ["source/src/keep.py"])

    def test_records_with_disagreeing_or_missing_versions(self):
        a = self.write("work/a.json", json.dumps({"blender_version": "5.2.3"}))
        b = self.write("work/b.json", json.dumps({"version": "5.3.0"}))
        c = self.write("work/c.json", json.dumps({"returncode": 0}))
        code, out, _ = self.bundle("--record", a, "--record", b, "--record", c)
        self.assertEqual(code, 0, out)
        readme = self.read("README.txt")
        self.assertIn("WARNING the records disagree", readme)
        self.assertIn("5.2.3 in a.json", readme)
        self.assertIn("5.3.0 in b.json", readme)

    def test_json_report(self):
        report = os.path.join(self.dir, "bundle.json")
        code, _, _ = self.bundle("--json", report)
        self.assertEqual(code, 0)
        with open(report, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data["status"], "pass")
        self.assertIn("final.mp4", data["files"])
        self.assertGreater(data["bytes"], 0)

    # ---- refusals (exit 2) ------------------------------------------------------------------------------
    def test_existing_version_is_never_overwritten(self):
        self.assertEqual(self.bundle()[0], 0)
        marker = os.path.join(self.folder(), "keep.me")
        with open(marker, "w", encoding="utf-8") as fh:
            fh.write("precious")
        code, _, err = self.bundle()
        self.assertEqual(code, 2)
        self.assertIn("never overwritten", err)
        with open(marker, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "precious")

    def test_dest_must_be_absolute_and_outside_git(self):
        code, _, err = self.bundle(dest="relative_dest")
        self.assertEqual(code, 2)
        self.assertIn("absolute", err)
        repo = os.path.join(self.dir, "repo")
        os.makedirs(os.path.join(repo, ".git"))
        inside = os.path.join(repo, "deliveries")
        code, _, err = self.bundle(dest=inside)
        self.assertEqual(code, 2)
        self.assertIn("git work tree", err)
        self.assertFalse(os.path.exists(inside))
        code, out, err = self.bundle("--allow-in-repo", dest=inside)
        self.assertEqual(code, 0, out + err)

    def test_cloud_synced_dest_warns(self):
        code, _, err = self.bundle(dest=os.path.join(self.dir, "Dropbox", "out"))
        self.assertEqual(code, 0)
        self.assertIn("WARNING", err)

    def test_bad_version_names(self):
        for name in ("", "../x", "a/b", "a\\b", ".hidden", "a b", "x" * 65, "-lead", "v1:2"):
            with self.subTest(version=name):
                code, _, err = self.bundle(version=name)
                self.assertEqual(code, 2)
        self.assertFalse(os.path.exists(self.dest))

    def test_missing_or_wrong_inputs_create_nothing(self):
        text = self.write("work/c.txt", "x")
        bad_utf8 = self.write("work/bad.txt", b"\xff\xfe\x00bad")
        not_json = self.write("work/r.json", "{ nope")
        a_list = self.write("work/l.json", "[1]")
        cases = {
            "video missing": dict(video=os.path.join(self.dir, "none.mp4")),
            "video is dir": dict(video=self.work),
            "include missing": dict(extra=["--include", os.path.join(self.dir, "none.py")]),
            "commands missing": dict(extra=["--commands", os.path.join(self.dir, "none.txt")]),
            "commands not utf8": dict(extra=["--commands", bad_utf8]),
            "record missing": dict(extra=["--record", os.path.join(self.dir, "none.json")]),
            "record not json": dict(extra=["--record", not_json]),
            "record not object": dict(extra=["--record", a_list]),
            "record duplicate name": dict(extra=["--record", text.replace("c.txt", "r.json"), "--record", not_json]),
            "reserved video name": dict(video=self.write("work/README.txt", "x")),
            "same include twice": dict(extra=["--include", text, "--include", text]),
        }
        for name, case in cases.items():
            with self.subTest(name=name):
                code, out, err = self.bundle(*case.get("extra", []), video=case.get("video"))
                self.assertEqual(code, 2, out + err)
                self.assertIn("render_bundle: ERROR", err)
                self.assertFalse(os.path.exists(self.folder()), "nothing may be created on a refusal")

    def test_two_includes_landing_on_one_name_are_refused(self):
        a = self.write("work/one/x.py", "1")
        b = self.write("work/two/x.py", "2")
        code, _, err = self.bundle("--include", a, "--include", b)
        self.assertEqual(code, 2)
        self.assertIn("source/x.py", err)
        self.assertFalse(os.path.exists(self.folder()))

    def test_include_containing_the_delivery_folder_is_refused(self):
        os.makedirs(self.dest)
        code, _, err = self.bundle("--include", self.dest)
        self.assertEqual(code, 2)
        self.assertIn("contains the delivery folder", err)
        code, _, err = run_main(["--dest", os.path.join(self.work, "out"), "--version", "v1", "--video",
                                 self.video, "--include", self.work])
        self.assertEqual(code, 2)

    def test_argparse_errors_exit_2(self):
        for argv in ([], ["--dest", self.dest], ["--dest", self.dest, "--version", "v1"]):
            with self.subTest(argv=argv):
                self.assertEqual(run_main(argv)[0], 2)

    # ---- verification -----------------------------------------------------------------------------------
    def test_manifest_mismatch_after_writing_exits_1_and_keeps_folder(self):
        real = rb.write_manifest

        def corrupting(root):
            files = real(root)
            with open(os.path.join(root, "final.mp4"), "ab") as fh:
                fh.write(b"tampered")
            return files

        with mock.patch.object(rb, "write_manifest", corrupting):
            code, out, _ = self.bundle()
        self.assertEqual(code, 1)
        self.assertIn("final.mp4: sha256 differs", out)
        self.assertIn("render_bundle: FAIL 1 finding(s)", out)
        self.assertTrue(os.path.isdir(self.folder()))

    def test_verify_manifest_directly(self):
        self.assertEqual(self.bundle()[0], 0)
        root = self.folder()
        self.assertEqual(rb.verify_manifest(root), [])
        extra = os.path.join(root, "extra.txt")
        with open(extra, "w", encoding="utf-8") as fh:
            fh.write("x")
        self.assertEqual(rb.verify_manifest(root), ["extra.txt: present but not listed"])
        os.remove(extra)
        os.remove(os.path.join(root, "final.mp4"))
        self.assertEqual(rb.verify_manifest(root), ["final.mp4: listed but missing"])
        with open(os.path.join(root, "MANIFEST.sha256"), "w", encoding="utf-8") as fh:
            fh.write("garbage line\n")
        problems = rb.verify_manifest(root)
        self.assertIn("manifest line 1 is malformed", problems)

    def test_copy_failure_removes_the_partial_folder(self):
        real = rb.shutil.copy2
        calls = {"n": 0}

        def flaky(src, dst, *a, **k):
            calls["n"] += 1
            if calls["n"] == 2:
                raise OSError("disk full (test)")
            return real(src, dst, *a, **k)

        extra = self.write("work/s.py", "s")
        with mock.patch.object(rb.shutil, "copy2", flaky):
            code, _, err = self.bundle("--include", extra)
        self.assertEqual(code, 2)
        self.assertIn("disk full", err)
        self.assertFalse(os.path.exists(self.folder()))
        self.assertEqual(self.bundle()[0], 0)  # the name is free again


if __name__ == "__main__":
    unittest.main()
