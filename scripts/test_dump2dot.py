#!/usr/bin/env python3
"""Tests for dump2dot.py. Run from the repository root:

    python3 -m unittest scripts/test_dump2dot.py -v

Everything but the last test needs no Graphviz; that one is skipped without `dot`.
"""

import os
import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dump2dot as d2d  # noqa: E402

# The five-state cycle of examples/Simple.v, as the plugin dumps it.
SIMPLE = """origin: MEBI.Examples.Simple, line 40: MeBi Run LTS
terms: init (by lts)
relations: lts (select, output, prepare, payment)
LTS: 5 states, 4 labels, 5 transitions. Initial state: 0.
states:
  0  Idle
  1  (Paid 0 coffee)
  2  (Paid 10 coffee)
  3  (Paid 20 coffee)
  4  (Ready coffee)
labels:
  0  (Some (Select coffee))
  1  (Some (Insert ten))
  2  None  (silent)
  3  (Some (Output coffee))
transitions:
  0 -0-> 1
  1 -1-> 2
  2 -1-> 3
  3 -2-> 4
  4 -3-> 0
"""

FSM = """origin: line 3: MeBi Run FSM
terms: old (by lts_old)
relations: lts_old (a)
FSM: 3 states, 2 labels, 4 edges. Initial state: 0.
states:
  0  (Idle, 0)
  1  (Busy, 0)
  2  (Done, 0)
labels:
  0  (Some go)
  1  (Some (stop now))
edges:
  0 -0-> 1
  0 -0-> 1
  1 -1-> 2
  1 -0-> 1
"""

INCOMPLETE = SIMPLE.replace("5 transitions. Initial", "5 transitions, incomplete. Initial")


def options(*argv):
    ap = d2d.make_parser()
    return d2d.normalise(ap.parse_args(list(argv)), ap)


class Parsing(unittest.TestCase):
    def test_lts(self):
        d = d2d.parse(SIMPLE)
        self.assertEqual(d.kind, "LTS")
        self.assertEqual(d.initial, 0)
        self.assertFalse(d.incomplete)
        self.assertEqual(len(d.states), 5)
        self.assertEqual(d.labels[2], ("None", True))
        self.assertEqual(d.labels[0], ("(Some (Select coffee))", False))
        self.assertEqual(d.arrows[0], (0, 0, 1))
        self.assertEqual(len(d.arrows), 5)

    def test_fsm_has_edges_not_transitions(self):
        d = d2d.parse(FSM)
        self.assertEqual(d.kind, "FSM")
        self.assertEqual(len(d.arrows), 4)

    def test_incomplete(self):
        self.assertTrue(d2d.parse(INCOMPLETE).incomplete)

    def test_not_a_dump(self):
        with self.assertRaises(ValueError):
            d2d.parse("Bisimilarity: initial states related: no.\nclasses:\n")

    def test_an_arrow_to_nowhere(self):
        with self.assertRaises(ValueError):
            d2d.parse(SIMPLE.replace("4 -3-> 0", "4 -3-> 9"))


class Tidying(unittest.TestCase):
    def test_unparen(self):
        self.assertEqual(d2d.unparen("(Idle, 0)"), "Idle, 0")
        self.assertEqual(d2d.unparen("((a))"), "a")
        self.assertEqual(d2d.unparen("(a) (b)"), "(a) (b)")
        self.assertEqual(d2d.unparen("f (a)"), "f (a)")
        self.assertEqual(d2d.unparen("()"), "()")

    def test_some_goes_when_every_label_has_it(self):
        states, labels = d2d.tidy(d2d.parse(SIMPLE))
        self.assertEqual(states[1], "Paid 0 coffee")
        self.assertEqual(labels[0], ("Select coffee", False))
        self.assertEqual(labels[2], (d2d.TAU, True))

    def test_some_stays_when_one_label_lacks_it(self):
        d = d2d.parse(SIMPLE.replace("(Some (Insert ten))", "(Insert ten)"))
        _, labels = d2d.tidy(d)
        self.assertEqual(labels[0], ("Some (Select coffee)", False))
        self.assertEqual(labels[1], ("Insert ten", False))

    def test_kind(self):
        self.assertEqual(d2d.kind_of([("Insert ten", False)]), "Insert")
        self.assertEqual(d2d.kind_of([("Insert ten", False), ("Insert twenty", False)]), "Insert")
        self.assertIsNone(d2d.kind_of([("Insert ten", False), ("Select tea", False)]))
        self.assertIsNone(d2d.kind_of([(d2d.TAU, True)]))
        self.assertEqual(d2d.kind_of([(d2d.TAU, True), ("Insert ten", False)]), "Insert")


class Shape(unittest.TestCase):
    def test_parallel_arrows_are_one(self):
        d = d2d.parse(FSM)
        _, labels = d2d.tidy(d)
        arrows = d2d.merge(d, labels)
        self.assertEqual([(s, t) for s, t, _ in arrows], [(0, 1), (1, 2), (1, 1)])
        self.assertEqual(arrows[0][2], [("go", False)])  # the repeat is dropped

    def test_the_arrow_back_of_a_cycle(self):
        d = d2d.parse(SIMPLE)
        _, labels = d2d.tidy(d)
        arrows = d2d.merge(d, labels)
        self.assertEqual(d2d.back_arrows(d, arrows), {(4, 0)})
        self.assertEqual(d2d.longest_path(arrows, {(4, 0)}, 0, 4), 4)

    def test_the_search_starts_at_the_initial_state(self):
        d = d2d.parse(SIMPLE.replace("Initial state: 0", "Initial state: 2"))
        _, labels = d2d.tidy(d)
        arrows = d2d.merge(d, labels)
        self.assertEqual(d2d.back_arrows(d, arrows), {(1, 2)})

    def test_a_loop_is_not_an_arrow_back(self):
        d = d2d.parse(FSM)
        _, labels = d2d.tidy(d)
        self.assertEqual(d2d.back_arrows(d, d2d.merge(d, labels)), set())

    def test_the_longest_path_not_the_shortest(self):
        d = d2d.parse(SIMPLE)
        _, labels = d2d.tidy(d)
        arrows = d2d.merge(d, labels) + [(0, 3, [("x", False)])]  # a shortcut
        self.assertEqual(d2d.longest_path(arrows, {(4, 0)}, 0, 4), 4)


class Dot(unittest.TestCase):
    def dot(self, text, *argv):
        return d2d.to_dot(d2d.parse(text), options(*argv))

    def test_a_label_is_a_node_on_its_arrow_by_default(self):
        out = self.dot(SIMPLE)
        self.assertIn(">Select coffee</TD>", out)
        self.assertIn("s0 -> l1", out)
        self.assertIn("l1 -> s1", out)
        self.assertIn('headport="t:n"', out)
        self.assertIn('tailport="t:s"', out)

    def test_the_extra_line_for_the_arrowhead_is_on_the_side_of_the_head(self):
        cell = '<TD PORT="t" BGCOLOR="white" CELLPADDING="1">'
        pad = '<TR><TD HEIGHT="%d"></TD></TR>' % d2d.HEAD_ALLOWANCE
        down = self.dot(SIMPLE)
        # forward: after the label; the arrow back (l5): before it
        self.assertIn("<TR>" + cell + "Select coffee</TD></TR>" + pad, down)
        self.assertIn(pad + "<TR>" + cell + "Output coffee</TD></TR>", down)
        # growing right, the extra is a cell beside, not a row below
        right = self.dot(SIMPLE, "--rankdir", "LR")
        gap = '<TD WIDTH="%d"></TD>' % d2d.HEAD_ALLOWANCE
        self.assertIn(cell + "Select coffee</TD>" + gap + "</TR>", right)
        self.assertIn("<TR>" + gap + cell + "Output coffee</TD></TR>", right)
        # growing up or left, the head is at the other side
        up = self.dot(SIMPLE, "--rankdir", "BT")
        self.assertIn(pad + "<TR>" + cell + "Select coffee</TD></TR>", up)
        self.assertIn("<TR>" + cell + "Output coffee</TD></TR>" + pad, up)
        self.assertNotIn("margin=\"0.05", down)

    def test_an_outline_frames_the_text_alone(self):
        framed = self.dot(SIMPLE, "--kind", "Select=green4", "--outline")
        self.assertIn('BORDER="1" STYLE="ROUNDED" COLOR="green4">Select coffee</TD>', framed)
        self.assertNotIn("STYLE=\"ROUNDED\"", self.dot(SIMPLE, "--kind", "Select=green4"))

    def test_the_arrow_back_is_laid_out_the_other_way_with_its_head_at_the_target(self):
        out = self.dot(SIMPLE)
        self.assertIn("s0 -> l5 [dir=back, arrowtail=normal, arrowhead=none, minlen=4", out)
        self.assertIn("l5 -> s4 [arrowhead=none, minlen=4", out)

    def test_landscape_changes_the_ports(self):
        out = self.dot(SIMPLE, "--rankdir", "LR")
        self.assertIn("rankdir=LR", out)
        self.assertIn('headport="t:w"', out)
        self.assertIn('tailport="t:e"', out)

    def test_edge_labels_are_graphvizs_own(self):
        out = self.dot(SIMPLE, "--labels", "edge")
        self.assertIn('s0 -> s1 [label="Select coffee"', out)
        self.assertNotIn("l1", out)

    def test_nothing_is_coloured_unless_asked(self):
        out = self.dot(SIMPLE)
        self.assertNotIn("fontcolor", out.replace('fontcolor="gray50"', ""))

    def test_kinds_and_the_default_colour(self):
        out = self.dot(SIMPLE, "--kind", "Select=green4", "--kind-default", "black")
        self.assertIn('color="green4", fontcolor="green4"', out)
        self.assertIn('fontcolor="black"', out)       # Insert and Output take the default's
        self.assertIn('color="gray50"', out)           # the silent step keeps its own

    def test_the_silent_step_is_dashed_and_tau(self):
        out = self.dot(SIMPLE)
        self.assertIn("style=dashed", out)
        # TeX's bold math italic tau, in the fonts of TeX's math italic
        self.assertIn(d2d.TAU_MARKUP, out)
        self.assertIn("Latin Modern Math", d2d.TAU_MARKUP)

    def test_initial_terminal_and_incomplete(self):
        out = self.dot(INCOMPLETE)
        self.assertIn("start -> s0", out)
        self.assertIn("s0 [label=\"Idle\", penwidth=2.5]", out)
        self.assertIn("Incomplete", out)
        chain = "".join(self.dot(SIMPLE.replace("  4 -3-> 0\n", "")).split("\n"))
        self.assertIn("peripheries=2", chain)          # the state with no way out

    def test_a_loop_keeps_a_label_of_its_own(self):
        out = self.dot(FSM)
        self.assertIn('s1 -> s1 [label="go"', out)

    def test_markup_is_escaped_and_a_silent_step_among_labels_is_a_line(self):
        self.assertEqual(d2d.html('a<b&"c">'), "a&lt;b&amp;&quot;c&quot;&gt;")
        v = d2d.label_value([("x<y", False), (d2d.TAU, True)])
        self.assertEqual(v, "<x&lt;y<BR/>%s>" % d2d.TAU_MARKUP)
        self.assertEqual(d2d.label_value([("a", False), ("b", False)]), '"a\\nb"')

    def test_numbers(self):
        self.assertIn('label="1: Paid 0 coffee"', self.dot(SIMPLE, "--numbers"))

    def test_quotes_are_escaped(self):
        self.assertEqual(d2d.q('a"b\\c\nd'), '"a\\"b\\\\c\\nd"')


class CommandLine(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="dump2dot-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.dump = self.tmp / "2026 | Finished Extracting LTS.txt"
        self.dump.write_text(SIMPLE, encoding="utf-8")

    def test_dot_only_writes_the_file(self):
        out = self.tmp / "out" / "pic"
        self.assertEqual(d2d.main([str(self.dump), "-T", "dot", "-o", str(out)]), 0)
        self.assertIn("digraph G", (self.tmp / "out" / "pic.dot").read_text(encoding="utf-8"))

    def test_a_bigger_dump_is_refused(self):
        with self.assertRaises(SystemExit) as e:
            d2d.main([str(self.dump), "-T", "dot", "-o", str(self.tmp / "x"), "--max-states", "3"])
        self.assertIn("over --max-states", str(e.exception))

    def test_latest_skips_what_is_not_a_graph(self):
        other = self.tmp / "2027 | Finished Merging FSMs.txt"
        other.write_text("Bisimilarity: initial states related: no.\n", encoding="utf-8")
        now = time.time()
        os.utime(self.dump, (now - 10, now - 10))
        os.utime(other, (now, now))  # newer, but not a graph
        self.assertEqual(d2d.latest_dump(self.tmp), self.dump)

    def test_the_name_comes_from_the_origin_and_the_term(self):
        self.assertEqual(d2d.base_name(d2d.parse(SIMPLE), self.dump), "Simple-init")

    def test_no_dot_says_so_and_keeps_the_file(self):
        out = self.tmp / "nodot"
        with self.assertRaises(SystemExit) as e:
            d2d.main([str(self.dump), "-o", str(out), "--dot", "no-such-graphviz-program"])
        self.assertIn("not on the PATH", str(e.exception))
        self.assertTrue((self.tmp / "nodot.dot").exists())

    @unittest.skipUnless(shutil.which("dot"), "no Graphviz (dot) on the PATH")
    def test_it_renders(self):
        out = self.tmp / "pic"
        self.assertEqual(d2d.main([str(self.dump), "-T", "svg", "-o", str(out), "--kind", "Select=green4"]), 0)
        self.assertIn("<svg", (self.tmp / "pic.svg").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
