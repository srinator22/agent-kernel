import tomllib
import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cc = load_tool("check_connectors")

BASE = """
[connector_matability]
round4 = ["round4"]
round6 = ["round6"]
usb = ["usb"]

[connector_hazard]
damaging_if_socket_drives = ["24V"]
onto_plug_classes = ["5V", "SIG", "GND"]
damaging_pairs = [["12V", "5V"]]

[derating]
current_continuous_factor = 0.7

[input]
port = "P1"
i_design_max = 20.0
status = "datasheet"

[[loads]]
name = "motor"
i_nominal = 4.0
i_peak = 8.0
status = "datasheet"

[[ports]]
id = "P1"
name = "Main input"
coding = "round4"
pins = { 1 = "24V", 2 = "GND" }
contacts_per_pole = 2
contact_rating_a = 15.0

[[ports]]
id = "P2"
name = "Motor"
coding = "round6"
pins = { 1 = "24V", 2 = "GND", 3 = "SIG" }
load = "motor"
contacts_per_pole = 1
contact_rating_a = 10.0
"""


def run(extra: str = "", base: str = BASE):
    return cc.run(tomllib.loads(base + extra))


def port(pid, coding, pins, **fields) -> str:
    pin_text = ", ".join(f'{k} = "{v}"' for k, v in pins.items())
    body = "".join(f"{k} = {v if not isinstance(v, str) else chr(34) + v + chr(34)}\n" for k, v in fields.items())
    return f'\n[[ports]]\nid = "{pid}"\ncoding = "{coding}"\npins = {{ {pin_text} }}\n{body}'


class CrossPlugTests(unittest.TestCase):
    def test_base_has_no_failure(self):
        findings = run()
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("P1 Main input: input i_design_max 20 A / 2 contact(s) = 10.00 A per contact vs 15 A rating (67%)",
                      joined(of_level(findings, "PASS")))

    def test_different_codings_never_mate(self):
        self.assertNotIn("cross_plug", [f.check.split(".")[1] for f in run()])

    def test_driving_socket_onto_a_vulnerable_plug_is_damaging(self):
        extra = port("P3", "round4", {1: "5V", 2: "GND"}, contact_rating_a=5.0)
        findings = run(extra)
        out = joined(of_level(findings, "FAIL"))
        self.assertIn("plug P3 into socket P1: DAMAGING, pin 1: socket 24V onto plug 5V", out)

    def test_the_pairing_is_directional_and_benign_ones_are_info(self):
        extra = port("P3", "round4", {1: "5V", 2: "GND"}, contact_rating_a=5.0)
        findings = run(extra)
        self.assertIn("plug P1 into socket P3: benign", joined(of_level(findings, "INFO")))

    def test_explicit_damaging_pair_table(self):
        extra = (port("P3", "round4", {1: "12V", 2: "GND"}, contact_rating_a=5.0)
                 + port("P4", "round4", {1: "5V", 2: "GND"}, contact_rating_a=5.0))
        out = joined(of_level(run(extra), "FAIL"))
        self.assertIn("plug P4 into socket P3: DAMAGING, pin 1: socket 12V onto plug 5V", out)

    def test_identical_ports_are_interchangeable_and_compared_once(self):
        extra = port("P3", "round4", {1: "24V", 2: "GND"}, contact_rating_a=15.0, load="motor")
        findings = run(extra)
        info = joined(of_level(findings, "INFO"))
        self.assertIn("ports P1, P3 (round4) are interchangeable - label the ports", info)

    def test_retired_ports_are_listed_not_compared(self):
        extra = port("P9", "round4", {1: "5V", 2: "GND"}, retired="replaced by P2")
        findings = run(extra)
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("retired rows, neither cross-plug compared nor rated: P9", joined(of_level(findings, "INFO")))

    def test_unknown_coding_and_unknown_mate_fail(self):
        self.assertIn("coding 'oval' has no connector_matability entry",
                      joined(of_level(run(port("P3", "oval", {1: "SIG"})), "FAIL")))
        bad = BASE.replace('usb = ["usb"]', 'usb = ["usb", "ghost"]')
        self.assertIn("mates with unknown coding 'ghost'", joined(of_level(run(base=bad), "FAIL")))

    def test_duplicate_port_id_fails(self):
        self.assertIn("port id P1 appears more than once", joined(of_level(run(port("P1", "round4", {1: "SIG"})), "FAIL")))


class ContactLoadingTests(unittest.TestCase):
    def test_over_rating_fails_and_high_loading_warns(self):
        over = BASE.replace("contact_rating_a = 10.0", "contact_rating_a = 7.0")
        self.assertIn("P2 Motor: motor i_peak 8 A / 1 contact(s) = 8.00 A per contact vs 7 A rating (114%): over rating",
                      joined(of_level(run(base=over), "FAIL")))
        warn = BASE.replace("contact_rating_a = 10.0", "contact_rating_a = 9.0")
        self.assertIn("above 80% of rating", joined(of_level(run(base=warn), "WARN")))

    def test_contacts_per_pole_share_the_current(self):
        shared = BASE.replace("contacts_per_pole = 1", "contacts_per_pole = 2")
        self.assertIn("4.00 A per contact", joined(of_level(run(base=shared), "PASS")))

    def test_uncertain_current_warns_even_within_rating(self):
        text = BASE.replace('status = "datasheet"\n\n[[loads]]', 'status = "estimate"\n\n[[loads]]')
        findings = run(base=text)
        self.assertIn("within rating but the current is estimate", joined(of_level(findings, "WARN")))

    def test_pending_current_warns(self):
        text = BASE.replace("i_peak = 8.0", 'i_peak = "pending"')
        self.assertIn("loading not computed", joined(of_level(run(base=text), "WARN")))

    def test_unmapped_port_is_listed_once(self):
        findings = run(port("P3", "usb", {1: "5V"}, contact_rating_a=1.0))
        self.assertIn("contact loading not checked: P3", joined(of_level(findings, "INFO")))

    def test_unknown_load_is_an_error(self):
        with self.assertRaises(cc.ToolError):
            run(base=BASE.replace('load = "motor"', 'load = "ghost"'))


HEADER = """
[[parts]]
ref = "J5"
i_cont_a = 8.0
status = "datasheet"

[[ports]]
id = "H1"
name = "Pigtail header"
kind = "header"
coding = "hdr6"
part = "J5"
circuits = 6
contacts = [
  { net = "VBUS", pins = [1, 2], loads = { motor = 1 }, current = "peak" },
  { net = "SIG", pins = [3, 4], signal = true },
]
"""


class HeaderTests(unittest.TestCase):
    def test_header_per_circuit_current_against_the_derated_part_rating(self):
        # 8 A over 2 circuits = 4 A each against 0.7 x 8 = 5.6 A.
        findings = self.header_run(HEADER)
        out = joined(of_level(findings, "PASS"))
        self.assertIn("H1 Pigtail header: worst VBUS 8.00 A over 2 circuit(s) = 4.00 A per circuit vs 8 A x 0.7 = 5.60 A derated (71%)", out)
        self.assertIn("2 signal circuit(s) not rated", out)

    def header_run(self, header: str):
        text = BASE.replace('usb = ["usb"]', 'usb = ["usb"]\nhdr6 = ["hdr6"]')
        return run(header, text)

    def test_header_fits(self):
        findings = self.header_run(HEADER)
        self.assertEqual(of_level(findings, "FAIL"), [])

    def test_header_over_derated_rating_fails(self):
        findings = self.header_run(HEADER.replace("i_cont_a = 8.0", "i_cont_a = 5.0"))
        self.assertIn("over the derated rating", joined(of_level(findings, "FAIL")))

    def test_header_pin_problems_fail(self):
        outside = self.header_run(HEADER.replace("pins = [1, 2]", "pins = [1, 9]"))
        self.assertIn("pin 9 is outside 1 to 6", joined(of_level(outside, "FAIL")))
        twice = self.header_run(HEADER.replace("pins = [3, 4]", "pins = [2, 4]"))
        self.assertIn("pin 2 is listed for VBUS and SIG", joined(of_level(twice, "FAIL")))

    def test_header_without_a_part_row_fails_and_unknown_load_fails(self):
        no_part = self.header_run(HEADER.replace('part = "J5"', 'part = "J99"'))
        self.assertIn("no [[parts]] row for J99", joined(of_level(no_part, "FAIL")))
        no_load = self.header_run(HEADER.replace("motor = 1", "ghost = 1"))
        self.assertIn("unknown load or field ghost.i_peak", joined(of_level(no_load, "FAIL")))

    def test_two_headers_with_the_same_coding_fail(self):
        second = HEADER.replace('id = "H1"', 'id = "H2"').replace('[[parts]]\nref = "J5"\ni_cont_a = 8.0\nstatus = "datasheet"\n\n', "")
        findings = self.header_run(HEADER + second)
        self.assertIn("headers H1, H2 share coding 'hdr6'", joined(of_level(findings, "FAIL")))

    def test_signal_only_header_has_nothing_to_rate(self):
        signal = HEADER.replace("{ net = \"VBUS\", pins = [1, 2], loads = { motor = 1 }, current = \"peak\" },", "")
        self.assertIn("no power contact to rate", joined(of_level(self.header_run(signal), "INFO")))

    def test_header_needs_the_derating_factor(self):
        text = BASE.replace("[derating]\ncurrent_continuous_factor = 0.7\n", "").replace('usb = ["usb"]', 'usb = ["usb"]\nhdr6 = ["hdr6"]')
        with self.assertRaises(cc.ToolError):
            run(HEADER, text)


class CommandLineTests(TempDirTestCase):
    def test_exit_codes(self):
        path = self.write("parameters.toml", BASE)
        code, out = run_main(cc, ["--params", str(path)])
        self.assertEqual(code, 0, out)
        bad = self.write("bad.toml", BASE.replace("contact_rating_a = 10.0", "contact_rating_a = 1.0"))
        self.assertEqual(run_main(cc, ["--params", str(bad)])[0], 1)
        self.assertEqual(run_main(cc, ["--params", str(self.root / "none.toml")])[0], 2)
        self.write("noports.toml", "[a]\nb = 1\n")
        self.assertEqual(run_main(cc, ["--params", str(self.root / "noports.toml")])[0], 2)


if __name__ == "__main__":
    unittest.main()
