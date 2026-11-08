"""Tests for encode_verify.py with MP4 byte strings built in the test and a fake ffprobe.

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
No ffmpeg or network is used.
"""
import contextlib
import io
import json
import os
import struct
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import encode_verify as ev  # noqa: E402


# ---- MP4 builders ----------------------------------------------------------------------------------------
def box(typ, payload=b"", mode="normal"):
    if mode == "large":
        return struct.pack(">I4sQ", 1, typ, 16 + len(payload)) + payload
    if mode == "size0":
        return struct.pack(">I4s", 0, typ) + payload
    return struct.pack(">I4s", 8 + len(payload), typ) + payload


def mvhd(version=0, ts=1000, dur=1000):
    if version == 1:
        return box(b"mvhd", struct.pack(">B3sQQIQ", 1, b"\0" * 3, 0, 0, ts, dur) + b"\0" * 80)
    return box(b"mvhd", struct.pack(">B3sIIII", 0, b"\0" * 3, 0, 0, ts, dur) + b"\0" * 80)


def tkhd(version=0, w=640, h=360):
    tail = b"\0" * 8 + b"\0" * 8 + b"\0" * 36 + struct.pack(">II", w << 16, h << 16)
    # tail = reserved(8) + layer/alt/volume/reserved(8) + matrix(36) + width + height
    if version == 1:
        return box(b"tkhd", struct.pack(">B3sQQIIQ", 1, b"\0" * 3, 0, 0, 1, 0, 1000) + tail)
    return box(b"tkhd", struct.pack(">B3sIIIII", 0, b"\0" * 3, 0, 0, 1, 0, 1000) + tail)


def mdhd(version=0, ts=24, dur=24):
    if version == 1:
        return box(b"mdhd", struct.pack(">B3sQQIQHH", 1, b"\0" * 3, 0, 0, ts, dur, 0, 0))
    return box(b"mdhd", struct.pack(">B3sIIIIHH", 0, b"\0" * 3, 0, 0, ts, dur, 0, 0))


def hdlr(kind=b"vide"):
    return box(b"hdlr", struct.pack(">B3sI4s", 0, b"\0" * 3, 0, kind) + b"\0" * 12 + b"name\0")


def stsd(fourcc=b"avc1"):
    return box(b"stsd", struct.pack(">B3sI", 0, b"\0" * 3, 1) + box(fourcc, b"\0" * 78))


def stts(entries):
    body = struct.pack(">B3sI", 0, b"\0" * 3, len(entries))
    for count, delta in entries:
        body += struct.pack(">II", count, delta)
    return box(b"stts", body)


def stsz(sizes=None, fixed=0, count=0):
    if fixed:
        return box(b"stsz", struct.pack(">B3sII", 0, b"\0" * 3, fixed, count))
    body = struct.pack(">B3sII", 0, b"\0" * 3, 0, len(sizes)) + b"".join(struct.pack(">I", s) for s in sizes)
    return box(b"stsz", body)


def trak(kind=b"vide", version=0, w=640, h=360, ts=24, dur=24, codec=b"avc1", entries=None, sizes=None,
         fixed=0, count=0, drop=()):
    entries = [(24, 1)] if entries is None else entries
    sizes = [1000] * 24 if sizes is None and not fixed else sizes
    parts = {b"stsd": stsd(codec), b"stts": stts(entries),
             b"stsz": stsz(sizes, fixed, count)}
    stbl = box(b"stbl", b"".join(v for k, v in parts.items() if k not in drop))
    mdia = box(b"mdia", mdhd(version, ts, dur) + hdlr(kind) + box(b"minf", stbl))
    return box(b"trak", tkhd(version, w, h) + mdia)


def mp4(moov_children=None, version=0, moov_mode="normal", mdat_mode="normal", ftyp=True, moov_first=False,
        extra_top=b"", **trak_kwargs):
    kids = moov_children if moov_children is not None else mvhd(version) + trak(version=version, **trak_kwargs)
    moov = box(b"moov", kids, moov_mode)
    mdat = box(b"mdat", b"\0" * 64, mdat_mode)
    head = box(b"ftyp", b"isom" + struct.pack(">I", 512) + b"isomavc1") if ftyp else b""
    return head + ((moov + mdat) if moov_first else (mdat + moov)) + extra_top


FAKE_FFPROBE = r'''
import sys
sys.stdout.write(%(stdout)r)
sys.stderr.write(%(stderr)r)
sys.exit(%(rc)d)
'''


def run_main(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = ev.main(argv)
        except SystemExit as exc:
            code = exc.code
    return code, out.getvalue(), err.getvalue()


class EncodeVerifyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = os.path.realpath(self.tmp.name)
        self.n = 0

    def file(self, data, name=None):
        self.n += 1
        path = os.path.join(self.dir, name or f"f{self.n}.mp4")
        with open(path, "wb") as fh:
            fh.write(data)
        return path

    def verify(self, data, *argv):
        return run_main([self.file(data), "--no-ffprobe", *argv])

    def ffprobe_cmd(self, stdout="", stderr="", rc=0):
        path = os.path.join(self.dir, f"fake_ffprobe{self.n}.py")
        self.n += 1
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(FAKE_FFPROBE % {"stdout": stdout, "stderr": stderr, "rc": rc})
        return json.dumps([sys.executable, path])

    @staticmethod
    def probe_json(**over):
        stream = {"codec_name": "h264", "width": 640, "height": 360, "r_frame_rate": "24/1",
                  "nb_read_packets": "24"}
        stream.update(over)
        return json.dumps({"streams": [stream]})

    # ---- good files -------------------------------------------------------------------------------------
    def test_good_v0_file_passes_with_all_checks(self):
        code, out, err = self.verify(mp4(), "--frames", "24", "--fps", "24", "--width", "640", "--height", "360",
                                     "--codec", "avc1", "--min-kbps", "150", "--max-kbps", "250")
        self.assertEqual(code, 0, out + err)
        self.assertIn("encode_verify: PASS frames=24 fps=24 640x360 codec=avc1", out)
        self.assertIn("192.0 kbps", out)

    def test_good_v1_headers_and_box_forms(self):
        variants = {
            "v1": mp4(version=1),
            "largesize_moov": mp4(moov_mode="large"),
            "largesize_mdat": mp4(mdat_mode="large"),
            "size0_mdat": mp4(mdat_mode="size0", moov_first=True),
            "moov_first": mp4(moov_first=True),
            "trailing_zero_padding": mp4(extra_top=b"\0\0\0\0"),
        }
        for name, data in variants.items():
            with self.subTest(name=name):
                code, out, err = self.verify(data, "--frames", "24", "--fps", "24")
                self.assertEqual(code, 0, out + err)

    def test_fixed_stsz_and_fractional_fps(self):
        data = mp4(ts=30000, dur=30030, entries=[(30, 1001)], sizes=None, fixed=500, count=30)
        code, out, _ = self.verify(data, "--frames", "30", "--fps", "30000/1001")
        self.assertEqual(code, 0, out)
        self.assertIn("fps=29.97", out)

    def test_video_track_chosen_after_audio_track(self):
        audio = trak(kind=b"soun", w=0, h=0, codec=b"mp4a")
        moov = mvhd() + audio + trak()
        code, out, _ = self.verify(mp4(moov_children=moov), "--frames", "24")
        self.assertEqual(code, 0, out)

    # ---- findings (exit 1) ------------------------------------------------------------------------------
    def test_each_finding_exits_1(self):
        cases = {
            "frame count": (mp4(), ["--frames", "25"], "frame count 24, expected 25"),
            "fps": (mp4(), ["--fps", "25"], "fps 24.0000, expected 25.0000"),
            "width": (mp4(), ["--width", "1920"], "width 640, expected 1920"),
            "height": (mp4(), ["--height", "1080"], "height 360, expected 1080"),
            "codec": (mp4(), ["--codec", "hvc1"], "codec avc1, expected hvc1"),
            "bitrate low": (mp4(), ["--min-kbps", "300"], "below the minimum"),
            "bitrate high": (mp4(), ["--max-kbps", "100"], "above the maximum"),
            "duration": (mp4(dur=48), [], "duration 2.0000 s differs"),
            "stsz count": (mp4(sizes=[1000] * 23), [], "stts counts 24 samples but stsz counts 23"),
            "vfr": (mp4(entries=[(23, 1), (1, 2)], dur=25), [], "variable frame rate"),
        }
        for name, (data, argv, text) in cases.items():
            with self.subTest(name=name):
                code, out, _ = self.verify(data, *argv)
                self.assertEqual(code, 1, out)
                self.assertIn(text, out)
                self.assertIn("encode_verify: FAIL", out)

    def test_duration_tolerance_is_in_frames(self):
        data = mp4(ts=24000, dur=24000 + 480, entries=[(24, 1000)])  # 480/24000 s = 0.48 frame at 24 fps
        self.assertEqual(self.verify(data)[0], 0)
        self.assertEqual(self.verify(data, "--duration-tol", "0.4")[0], 1)

    def test_fps_within_tolerance_passes(self):
        data = mp4(ts=24000, dur=24000, entries=[(24, 1000)])
        self.assertEqual(self.verify(data, "--fps", "24.0005")[0], 0)

    def test_several_findings_are_counted(self):
        code, out, _ = self.verify(mp4(), "--frames", "1", "--width", "1", "--codec", "x")
        self.assertEqual(code, 1)
        self.assertIn("FAIL 3 finding(s)", out)

    def test_zero_media_duration_is_a_finding_and_bitrate_falls_back_to_stts(self):
        code, out, _ = self.verify(mp4(dur=0), "--min-kbps", "1")
        self.assertEqual(code, 1)
        self.assertIn("duration 0.0000 s differs", out)
        self.assertNotIn("below the minimum", out)
        self.assertIn("192.0 kbps", out)

    # ---- could not run (exit 2) -------------------------------------------------------------------------
    def test_unusable_files_exit_2(self):
        good = mp4()
        cases = {
            "empty": b"",
            "garbage": b"this is not an mp4 file at all, just text bytes",
            "no ftyp": mp4(ftyp=False),
            "no moov": box(b"ftyp", b"isom" + b"\0" * 8) + box(b"mdat", b"\0" * 16),
            "fragmented moof": good + box(b"moof", b"\0" * 16),
            "fragmented mvex": mp4(moov_children=mvhd() + trak() + box(b"mvex", box(b"trex", b"\0" * 24))),
            "no video track": mp4(moov_children=mvhd() + trak(kind=b"soun", codec=b"mp4a")),
            "no tracks": mp4(moov_children=mvhd()),
            "no stts": mp4(drop=(b"stts",)),
            "no stsz": mp4(drop=(b"stsz",)),
            "truncated moov": good[:-20],
            "truncated header": good + b"\0\0\0\x20mo",
            "truncated mdat": box(b"ftyp", b"isom" + b"\0" * 8) + struct.pack(">I4s", 1000, b"mdat") + b"\0" * 10,
            "bad size": box(b"ftyp", b"isom" + b"\0" * 8) + struct.pack(">I4s", 4, b"free"),
            "zero timescale": mp4(ts=0),
        }
        cases["huge stts count"] = good.replace(struct.pack(">B3sII", 0, b"\0" * 3, 1, 24),
                                                struct.pack(">B3sII", 0, b"\0" * 3, 10 ** 6, 24))
        for name, data in cases.items():
            with self.subTest(name=name):
                code, out, err = self.verify(data)
                self.assertEqual(code, 2, out + err)
                self.assertIn("encode_verify: ERROR", err)
                self.assertNotIn("PASS", out)

    def test_every_truncation_point_is_exit_2_or_valid_never_a_crash(self):
        data = mp4()
        path = os.path.join(self.dir, "cut.mp4")
        for cut in range(0, len(data), 7):
            with open(path, "wb") as fh:
                fh.write(data[:cut])
            code, out, err = run_main([path, "--no-ffprobe"])
            self.assertIn(code, (0, 1, 2), (cut, out, err))
            if cut < len(data) - 8:
                self.assertEqual(code, 2, (cut, out, err))

    def test_missing_file_and_directory_exit_2(self):
        self.assertEqual(run_main([os.path.join(self.dir, "none.mp4"), "--no-ffprobe"])[0], 2)
        self.assertEqual(run_main([self.dir, "--no-ffprobe"])[0], 2)

    def test_bad_arguments_exit_2(self):
        path = self.file(mp4())
        for argv in ([], [path, "--fps", "abc"], [path, "--fps", "0"], [path, "--fps", "1/0"],
                     [path, "--min-kbps", "10", "--max-kbps", "5"], [path, "--frames", "-1"],
                     [path, "--duration-tol", "-1"], [path, "--frames", "x"],
                     [path, "--ffprobe-cmd", "not json"], [path, "--ffprobe-cmd", "[]"]):
            with self.subTest(argv=argv):
                self.assertEqual(run_main(argv)[0], 2)

    # ---- ffprobe ----------------------------------------------------------------------------------------
    def test_ffprobe_agreement_passes(self):
        path = self.file(mp4())
        code, out, err = run_main([path, "--ffprobe-cmd", self.ffprobe_cmd(self.probe_json())])
        self.assertEqual(code, 0, out + err)
        self.assertIn("ffprobe cross-checked", out)

    def test_ffprobe_disagreements_are_findings(self):
        path = self.file(mp4())
        for over, text in (({"nb_read_packets": "25"}, "packets"), ({"width": 1280}, "resolution"),
                           ({"r_frame_rate": "25/1"}, "r_frame_rate"), ({"codec_name": "hevc"}, "codec"),
                           ({"nb_read_packets": "n/a"}, "unusable")):
            with self.subTest(over=over):
                code, out, _ = run_main([path, "--ffprobe-cmd", self.ffprobe_cmd(self.probe_json(**over))])
                self.assertEqual(code, 1, out)
                self.assertIn(text, out)

    def test_ffprobe_failure_modes_are_findings(self):
        path = self.file(mp4())
        cases = [self.ffprobe_cmd(rc=1, stderr="bad file"), self.ffprobe_cmd(stdout="not json"),
                 self.ffprobe_cmd(stdout='{"streams": []}'),
                 json.dumps([os.path.join(self.dir, "no-such-ffprobe.exe")])]
        for cmd in cases:
            with self.subTest(cmd=cmd[-40:]):
                code, out, _ = run_main([path, "--ffprobe-cmd", cmd])
                self.assertEqual(code, 1, out)
                self.assertIn("ffprobe", out)

    def test_ffprobe_rate_not_compared_for_vfr_but_vfr_is_a_finding(self):
        path = self.file(mp4(entries=[(23, 1), (1, 2)], dur=25))
        code, out, _ = run_main([path, "--ffprobe-cmd", self.ffprobe_cmd(self.probe_json(r_frame_rate="24/1"))])
        self.assertEqual(code, 1)
        self.assertIn("variable frame rate", out)
        self.assertNotIn("r_frame_rate", out)

    def test_ffprobe_absent_is_not_a_failure(self):
        path = self.file(mp4())
        with mock.patch.object(ev.shutil, "which", return_value=None):
            code, out, _ = run_main([path])
        self.assertEqual(code, 0)
        self.assertIn("ffprobe not on PATH; parser only", out)

    def test_ffprobe_on_path_is_used_unless_disabled(self):
        path = self.file(mp4())
        missing = os.path.join(self.dir, "no-such-ffprobe.exe")
        with mock.patch.object(ev.shutil, "which", return_value=missing):
            code, out, _ = run_main([path])
            self.assertEqual(code, 1)
            self.assertIn("ffprobe could not run", out)
            code, out, _ = run_main([path, "--no-ffprobe"])
            self.assertEqual(code, 0)
            self.assertIn("--no-ffprobe", out)

    def test_json_report(self):
        report = os.path.join(self.dir, "report.json")
        code, _, _ = self.verify(mp4(), "--frames", "99", "--json", report)
        self.assertEqual(code, 1)
        with open(report, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data["tool"], "encode_verify")
        self.assertEqual(data["status"], "fail")
        self.assertEqual(data["facts"]["frames_stts"], 24)
        self.assertEqual(len(data["findings"]), 1)

    def test_parse_rate(self):
        self.assertAlmostEqual(ev.parse_rate("30000/1001"), 29.97003, places=4)
        self.assertEqual(ev.parse_rate("24"), 24.0)


if __name__ == "__main__":
    unittest.main()
