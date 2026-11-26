"""Tests for scripts/ux-score.py. Run: python3 -m unittest discover -s scripts/tests -p 'test_ux*.py'

Images are drawn here, so no binary fixtures are committed. The judge answers come from fixtures/judge-answer.txt.
"""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ux_score", HERE.parent / "ux-score.py")
ux = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ux)

IPHONE = (1206, 2622)
IPAD = (2064, 2752)


def page(size, bg, draw=None):
    img = Image.new("RGB", size, bg)
    if draw:
        draw(ImageDraw.Draw(img), size)
    return img


def save(img, folder, name):
    path = Path(folder) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    return str(path)


def text_rows(d, size, x0, x1, color=(20, 20, 20)):
    """Dashed lines that look like text: ink with gaps."""
    top, bottom = int(size[1] * 0.2), int(size[1] * 0.8)
    for y in range(top, bottom, 60):
        for x in range(x0, x1, 40):
            d.rectangle([x, y, x + 24, y + 16], fill=color)


def screen(path, device="iphone", name="empty-chat", variant="light", audit=None):
    return {"key": f"{device}:{name}@{variant}", "device": device, "screen": name, "variant": variant,
            "source": "screenshots", "png": path, "audit": audit}


class Rubric(unittest.TestCase):
    def test_criteria_come_from_the_headings(self):
        version, criteria, judged, text = ux.load_rubric()
        self.assertEqual(version, 1)
        self.assertEqual(criteria, ["native", "hierarchy", "spacing", "tap_targets", "contrast", "clutter",
                                    "consistency", "states", "space", "semantics"])
        self.assertNotIn("semantics", judged, "a PNG cannot show VoiceOver labels")
        self.assertIn("Liquid Glass", text)

    def test_every_owner_row_points_at_real_files(self):
        for _pattern, owner in ux.load_owners():
            for name in owner["files"]:
                self.assertTrue((ux.ROOT / name).exists(), name)

    def test_screens_find_their_owner(self):
        owners = ux.load_owners()
        self.assertEqual(ux.owner_of(owners, "hub/hub-search-llama")["lane"], "weekly-usage")
        self.assertEqual(ux.owner_of(owners, "drawer/drawer-open")["lane"], "chat-search")
        self.assertEqual(ux.owner_of(owners, "something-new")["lane"], "unassigned")


class Collect(unittest.TestCase):
    def test_simulator_names_become_device_tags(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ("iPhone-17-Pro-light-empty-chat.png", "iPad-Pro-13-inch-(M5)-dark-chat-markdown.png",
                         "iPad-mini-(A17-Pro)-light-hub.png", "Mac-dark-settings.png", "notes.png"):
                Image.new("RGB", (4, 4)).save(Path(tmp) / name)
            got = {(s["device"], s["variant"], s["screen"]) for s in ux.collect_screenshots(tmp)}
        self.assertEqual(got, {("iphone", "light", "empty-chat"), ("ipad-pro", "dark", "chat-markdown"),
                               ("ipad-mini", "light", "hub"), ("mac", "dark", "settings")})

    def test_device_override_tags_a_mac_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            Image.new("RGB", (4, 4)).save(Path(tmp) / "Designed-for-iPad-light-hub.png")
            self.assertEqual(ux.collect_screenshots(tmp, "mac")[0]["device"], "mac")

    def evidence(self, tmp, audited=True):
        dev = Path(tmp) / "iPhone-17-Pro"
        (dev / "drawer").mkdir(parents=True)
        for n, name in ((1, "drawer-open"), (2, "search-open")):
            Image.new("RGB", (4, 4)).save(dev / "drawer" / f"light-0{n}-{name}.png")
        rows = [f"drawer\tlight\t{n}\t{name}\tdrawer/light-0{n}-{name}.png" for n, name in ((1, "drawer-open"), (2, "search-open"))]
        (dev / "results.tsv").write_text("\n".join(rows) + "\n")
        if audited:
            (dev / "audited.tsv").write_text("drawer\tlight\tdrawer\t1\ndrawer\tlight\tsearch\t2\n")
        (dev / "audit.tsv").write_text("drawer\tlight\tdrawer\tContrast failed [Search chats]\t1\n"
                                       "drawer\tlight\tgone\tHit area is too small [x]\t9\n")
        return tmp

    def test_audit_attaches_to_the_step_it_ran_after(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = {s["screen"]: s for s in ux.collect_evidence(self.evidence(tmp))}
        self.assertEqual(found["drawer/drawer-open"]["audit"], ["Contrast failed [Search chats]"])
        self.assertEqual(found["drawer/search-open"]["audit"], [], "audited and clean is not unaudited")
        self.assertIsNone(found["drawer/audit:gone"]["png"], "a finding with no step keeps its numbers")

    def test_an_element_label_with_line_breaks_stays_one_finding(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.evidence(tmp, audited=False)
            dev = Path(tmp) / "iPhone-17-Pro"
            (dev / "audit.tsv").write_text("drawer\tlight\tdrawer\tContrast failed [Explain the code,\n\nthen point out bugs]\n"
                                           "drawer\tlight\tdrawer\tHit area is too small [x]\n")
            found = {s["screen"]: s for s in ux.collect_evidence(tmp)}
        self.assertEqual(found["drawer/drawer-open"]["audit"],
                         ["Contrast failed [Explain the code, then point out bugs]", "Hit area is too small [x]"])

    def test_a_step_without_an_audit_gets_no_audit_score(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = {s["screen"]: s for s in ux.collect_evidence(self.evidence(tmp, audited=False))}
        self.assertIsNone(found["drawer/search-open"]["audit"])


class Deterministic(unittest.TestCase):
    def test_audit_findings_lower_their_criterion(self):
        got = ux.audit_scores(["Contrast failed [a]", "Contrast failed [b]", "Hit area is too small [c]",
                               "Text clipped [d]", "Element has no description [e]"])
        self.assertEqual(got["contrast"][0], 3)
        self.assertEqual(got["tap_targets"][0], 4)
        self.assertEqual(got["hierarchy"][0], 4)
        self.assertEqual(got["semantics"][0], 4)

    def test_a_clean_audit_scores_five_but_never_claims_typography(self):
        got = ux.audit_scores([])
        self.assertEqual({k: v[0] for k, v in got.items()}, {"tap_targets": 5, "contrast": 5, "semantics": 5})

    def test_native_score_follows_the_ratchet_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "A.swift").write_text("Capsule().shadow(radius: 2).foregroundStyle(ARColor.ink)\nVStack {}\n")
            hits, per_file = ux.native_hits(tmp, ["A.swift", "Missing.swift"])
        self.assertEqual((hits, per_file), (1, {"A.swift": 1}), "a line counts once, like grep -c")
        self.assertEqual([ux.native_score(n) for n in (0, 2, 5, 10, 20, 21)], [5, 4, 3, 2, 1, 0])

    def test_blank_capture_zeroes_every_criterion(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = save(page(IPHONE, (255, 255, 255)), tmp, "blank.png")
            det, flags = ux.deterministic(screen(path), {"lane": "x", "files": []}, tmp, ["native", "contrast"])
        self.assertEqual(flags, ["capture_failed"])
        self.assertEqual(det["contrast"]["score"], 0)

    def test_the_wrong_appearance_fails_contrast(self):
        def body(d, size):
            text_rows(d, size, 100, 900)
        with tempfile.TemporaryDirectory() as tmp:
            path = save(page(IPHONE, (255, 255, 255), body), tmp, "a.png")
            det, _ = ux.deterministic(screen(path, variant="dark"), {"lane": "x", "files": []}, tmp, ["contrast"])
        self.assertEqual(det["contrast"]["score"], 0)
        self.assertIn("dark appearance requested", det["contrast"]["reasons"][0])

    def drawer(self, tmp, peek):
        def body(d, size):
            split = int(size[0] * 0.82)
            d.rectangle([split, 0, size[0], size[1]], fill=peek)
            text_rows(d, size, 60, split - 60)
        return save(page(IPHONE, (255, 255, 255), body), tmp, "drawer.png")

    def test_a_dimmed_peek_beside_the_drawer_is_flagged(self):
        with tempfile.TemporaryDirectory() as tmp:
            clear = ux.deterministic(screen(self.drawer(tmp, (255, 255, 255)), name="thread-list"),
                                     {"lane": "x", "files": []}, tmp, ["hierarchy"])[0]
            dim = ux.deterministic(screen(self.drawer(tmp, (110, 110, 110)), name="thread-list"),
                                   {"lane": "x", "files": []}, tmp, ["hierarchy"])[0]
        self.assertNotIn("hierarchy", clear)
        self.assertEqual(dim["hierarchy"]["score"], 0)
        self.assertIn("dimmed", dim["hierarchy"]["reasons"][0])

    def width_score(self, x0, x1, device="ipad-pro", size=IPAD):
        def body(d, s):
            text_rows(d, s, x0, x1)
        with tempfile.TemporaryDirectory() as tmp:
            path = save(page(size, (255, 255, 255), body), tmp, "w.png")
            det, _ = ux.deterministic(screen(path, device=device), {"lane": "x", "files": []}, tmp, ["space"])
        return det["space"]["score"]

    def test_stretched_chat_text_on_ipad_scores_low_and_a_readable_column_scores_five(self):
        self.assertLessEqual(self.width_score(40, 2040), 2)  # about 990 pt
        self.assertEqual(self.width_score(150, 1900), 4)  # about 875 pt
        self.assertEqual(self.width_score(300, 1700), 5)  # 700 pt

    def test_landscape_and_non_chat_screens_are_not_width_scored(self):
        def body(d, s):
            text_rows(d, s, 150, 2500)
        with tempfile.TemporaryDirectory() as tmp:
            path = save(page((2752, 2064), (255, 255, 255), body), tmp, "l.png")
            det, _ = ux.deterministic(screen(path, device="ipad-pro"), {"lane": "x", "files": []}, tmp, ["space"])
        self.assertNotIn("space", det)

    def test_full_width_hairlines_are_not_text(self):
        def body(d, s):
            for y in range(int(s[1] * 0.2), int(s[1] * 0.8), 200):
                d.rectangle([0, y, s[0], y + 3], fill=(200, 200, 200))
            text_rows(d, s, 300, 1700)
        self.assertEqual(self.width_score(300, 1700), 5)


JUDGE_ANSWER = (HERE / "fixtures" / "judge-answer.txt").read_text()


class Judge(unittest.TestCase):
    CRITERIA = ["native", "hierarchy", "spacing", "tap_targets", "contrast", "clutter", "consistency", "states", "space"]

    def test_parses_a_fenced_recorded_answer(self):
        got = ux.parse_judge(JUDGE_ANSWER, self.CRITERIA)
        self.assertEqual(got["scores"]["native"], 4.0)
        self.assertIsNone(got["scores"]["states"])
        self.assertIn("composer", got["top_fix"])
        self.assertTrue(got["reasons"]["contrast"].startswith("Subtitle"))

    def test_rejects_a_score_outside_the_scale(self):
        with self.assertRaises(ValueError):
            ux.parse_judge('{"scores": {"native": 9}}', self.CRITERIA)
        with self.assertRaises(ValueError):
            ux.parse_judge("sorry, I cannot see the image", self.CRITERIA)
        with self.assertRaises(ValueError):
            ux.parse_judge('{"scores": {}}', self.CRITERIA)

    def test_prompt_carries_the_rubric_the_image_and_the_second_run_reverses_the_order(self):
        _v, _c, judged, text = ux.load_rubric()
        meta = {"device": "iphone", "variant": "dark", "screen": "hub"}
        first = ux.build_messages(text, judged, meta, "data:image/jpeg;base64,AAA")
        second = ux.build_messages(text, judged, meta, "data:image/jpeg;base64,AAA", reverse=True)
        self.assertIn("Rubric version: 1", first[0]["content"])
        self.assertEqual(first[1]["content"][1]["image_url"]["url"], "data:image/jpeg;base64,AAA")
        self.assertIn("Screen: hub", first[1]["content"][0]["text"])
        a, b = first[0]["content"], second[0]["content"]
        self.assertLess(a.index('"native": "integer'), a.index('"space": "integer'))
        self.assertGreater(b.index('"native": "integer'), b.index('"space": "integer'))

    def test_two_runs_give_a_mean_and_a_spread(self):
        run_a = {"scores": {"native": 4.0, "space": 2.0}, "reasons": {"native": "a", "space": "b"}, "top_fix": "x"}
        run_b = {"scores": {"native": 5.0, "space": 2.0}, "reasons": {"native": "", "space": ""}, "top_fix": "y"}
        merged = ux.merge_runs([run_a, run_b], ["native", "space", "states"], "m")
        self.assertEqual(merged["criteria"]["native"]["score"], 4.5)
        self.assertEqual(merged["criteria"]["native"]["spread"], 1.0)
        self.assertEqual(merged["criteria"]["native"]["reason"], "a")
        self.assertNotIn("states", merged["criteria"])
        self.assertEqual(merged["spread"], 10.0)  # totals 60 and 70
        self.assertEqual(merged["top_fix"], "x", "the fix of the lower scoring run")

    def test_model_falls_back_to_a_vision_model_only_when_the_requested_one_cannot_see(self):
        catalog = {"data": [{"id": "a/text", "capabilities": ["chat"]}, {"id": "b/eyes", "capabilities": ["vision"]},
                            {"id": "anyrouter/auto", "capabilities": ["chat", "vision"]}]}
        self.assertEqual(ux.resolve_model("anyrouter/auto", catalog), "anyrouter/auto")
        self.assertEqual(ux.resolve_model("a/text", catalog), "b/eyes")
        self.assertEqual(ux.resolve_model("a/text", None), "a/text")


class Report(unittest.TestCase):
    def test_delta_is_marked_noise_inside_the_spread(self):
        self.assertEqual(ux.delta_text(80.0, 78.0, 3.0), "+2.0 (noise)")
        self.assertEqual(ux.delta_text(80.0, 74.0, 3.0), "+6.0")
        self.assertEqual(ux.delta_text(70.0, 72.5, 0.0), "-2.5")
        self.assertEqual(ux.delta_text(70.0, 70.01, 0.0), "=")
        self.assertEqual(ux.delta_text(70.0, None, 0.0), "new")

    def make_args(self, tmp, **extra):
        shots = Path(tmp) / "shots"
        shots.mkdir()
        def drawn(d, s):
            text_rows(d, s, 40, 2040)
        page(IPAD, (255, 255, 255), drawn).save(shots / "iPad-Pro-13-inch-light-chat-markdown.png")
        page(IPHONE, (255, 255, 255), lambda d, s: text_rows(d, s, 100, 900)).save(shots / "iPhone-17-Pro-light-empty-chat.png")
        base = dict(screenshots=str(shots), evidence=None, device=None, no_judge=False, max_judged=60,
                    model="anyrouter/auto", commit="abc", run_url="", repo=str(ux.ROOT))
        base.update(extra)
        return SimpleNamespace(**base)

    def test_without_a_key_only_deterministic_scores_are_reported_and_the_note_says_so(self):
        import os
        os.environ.pop("ANYROUTER_E2E_API_KEY", None)
        with tempfile.TemporaryDirectory() as tmp:
            result, raw = ux.run(self.make_args(tmp))
            text = ux.render(result, None)
        self.assertEqual(result["meta"]["judge"]["status"], "skipped")
        self.assertIn("ANYROUTER_E2E_API_KEY is not set", " ".join(result["meta"]["warnings"]))
        self.assertEqual(raw, [])
        self.assertIn("ipad-pro:chat-markdown", result["rows"])
        self.assertLessEqual(result["rows"]["ipad-pro:chat-markdown"]["criteria"]["space"], 2.0)
        width = [w for w in result["worst"] if (w["screen"], w["criterion"]) == ("ipad-pro:chat-markdown", "space")]
        self.assertEqual(width[0]["lane"], "chat-chrome")
        self.assertIn("## Five worst issues", text)
        json.dumps(result, default=list)

    def test_with_a_judge_the_scores_combine_and_the_next_run_shows_a_delta(self):
        answer = JUDGE_ANSWER
        calls = []

        def transport(payload):
            calls.append(payload)
            return {"choices": [{"message": {"content": answer}}]}
        with tempfile.TemporaryDirectory() as tmp:
            args = self.make_args(tmp)
            result, raw = ux.run(args, transport=transport, models_json=None)
            self.assertEqual(len(calls), 4, "two screenshots, two runs each")
            self.assertTrue(all(c["temperature"] == 0 for c in calls))
            self.assertEqual(len(raw), 4)
            row = result["rows"]["iphone:empty-chat"]
            self.assertEqual(row["criteria"]["contrast"], 3.0)
            self.assertEqual(row["spread"], 0.0)
            self.assertIn("composer", row["top_fix"])
            previous = json.loads(json.dumps(result, default=list))
            previous["rows"]["iphone:empty-chat"]["total"] -= 2
            text = ux.render(result, previous)
        self.assertIn("+2.0", text)
        self.assertIn("| iphone | 1 | ", text)


if __name__ == "__main__":
    unittest.main()
