#!/usr/bin/env python3
"""Draw an LTS or FSM from MeBi's plain-text dump with Graphviz.

The plugin writes each LTS and FSM it extracts as a plain-text dump when
`MeBi Config Output "DumpResults" True.` is set (plain text is the default
format: `MeBi Config Output Format Text.`), into `./_dumps/`. This reads one of
those and writes a Graphviz picture of it, so that a diagram needs nothing from
the plugin: only `dot` (Graphviz) on the PATH.

    scripts/dump2dot.py "_dumps/<...> | Finished Extracting LTS.txt"
    scripts/dump2dot.py --latest                    # the newest dump in _dumps/
    scripts/dump2dot.py --latest --rankdir LR -T pdf
    scripts/dump2dot.py DUMP --kind Select=green4 --kind Insert=blue3 --kind-default gray20

It writes `<name>.dot` and, unless `-T dot`, the picture (`-T png|pdf|svg`,
default png) into `./_diagrams/`, or where `-o` says, and prints the paths.

What is drawn follows the plugin's own `MeBi Draw`: a state and a label are
printed without the parentheses that enclose all of them, and the labels
without `Some` if every label that is not silent has it; a silent step is
dashed grey and labelled tau; parallel arrows share one, a label to a line; the
initial state has an arrow in and is bold, a state with no way out has a double
border, and an incomplete LTS says so under the picture. Colour is by *kind* of
label, the first word of it (`Insert ten` is `Insert`), and explicit: nothing is
coloured unless `--kind` or `--kind-default` says so. A silent step has no kind.

Where the label goes is `--labels`: `node` (the default) makes it a small node
on its arrow, so that the arrow runs through it and the layout keeps room for
it, and the label of an arrow back to an earlier state is half way along it;
`edge` leaves it to Graphviz's own edge labels, beside the arrow.

Layout time grows quickly with size, so a dump with more than `--max-states`
states (150 by default) is refused; raise it, or use 0 for no limit.

Only the Python standard library is needed. Graphviz is not bundled: install it
with your system's package manager, or `nix shell nixpkgs#graphviz`.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

TAU = "\u03c4"
# A silent step is TeX's \boldmath$\tau$: the mathematical bold italic small tau (U+1D749) in the fonts
# of TeX's math italic (Latin Modern Math is Computer Modern's), or the nearest to them.
TAU_MARKUP = '<FONT FACE="Latin Modern Math, STIX Two Math, Asana Math">\U0001d749</FONT>'
# How much longer the line from a label to the arrowhead is made than the other, in the units of an
# HTML-like label (a little under a point): Graphviz measures an arrow from border to border, head
# included, so that line is shorter by the head (10 * arrowsize points) and by the short way a tip stops
# from its node (about 2.5 points at this pen width). Measured at 11, growing down and right.
HEAD_ALLOWANCE = 11


# --- reading the dump ------------------------------------------------------


class Dump:
    """An LTS or FSM as the plugin's text dump holds it."""

    def __init__(self):
        self.kind = "LTS"  # or "FSM"
        self.origin = ""
        self.terms = ""
        self.initial = 0
        self.incomplete = False
        self.states = {}  # number -> printed term
        self.labels = {}  # number -> (printed term, silent)
        self.arrows = []  # (src, label number, dst), in the order given


HEADER = re.compile(
    r"^(LTS|FSM): (\d+) states, (\d+) labels, (\d+) (?:transitions|edges)"
    r"(, incomplete)?\. Initial state: (\d+)\.\s*$"
)
NUMBERED = re.compile(r"^\s+(\d+)\s\s(.*?)\s*$")
ARROW = re.compile(r"^\s+(\d+) -(\d+)-> (\d+)\s*$")


def parse(text):
    """The Dump of a plain-text dump [text]. Raises ValueError if it is not one."""
    d = Dump()
    section = None
    seen_header = False
    for line in text.split("\n"):
        m = HEADER.match(line)
        if m:
            d.kind, d.incomplete, d.initial = m.group(1), bool(m.group(5)), int(m.group(6))
            seen_header = True
        elif line.startswith("origin:"):
            d.origin = line[len("origin:"):].strip()
        elif line.startswith("terms:"):
            d.terms = line[len("terms:"):].strip()
        elif line.strip() in ("states:", "labels:", "transitions:", "edges:"):
            section = line.strip()[:-1]
        elif section == "states" and NUMBERED.match(line):
            m = NUMBERED.match(line)
            d.states[int(m.group(1))] = m.group(2)
        elif section == "labels" and NUMBERED.match(line):
            m = NUMBERED.match(line)
            t = m.group(2)
            silent = t.endswith("(silent)")
            if silent:
                t = t[: -len("(silent)")].rstrip()
            d.labels[int(m.group(1))] = (t, silent)
        elif section in ("transitions", "edges") and ARROW.match(line):
            m = ARROW.match(line)
            d.arrows.append((int(m.group(1)), int(m.group(2)), int(m.group(3))))
    if not seen_header or not d.states:
        raise ValueError("this does not look like a MeBi plain-text dump of an LTS or FSM")
    for s, l, t in d.arrows:
        if s not in d.states or t not in d.states or l not in d.labels:
            raise ValueError("the dump has an arrow that names an unknown state or label")
    return d


# --- text fit for a picture (as the plugin's Draw.tidy) ---------------------


def wraps(s):
    """Whether the '(' that [s] starts with is closed by the ')' it ends with, and not before."""
    if len(s) < 2 or s[0] != "(" or s[-1] != ")":
        return False
    depth = 0
    for i, c in enumerate(s):
        depth += (c == "(") - (c == ")")
        if depth == 0 and i < len(s) - 1:
            return False
    return depth == 0


def unparen(s):
    s = s.strip()
    while wraps(s):
        inner = s[1:-1].strip()
        if inner == "":
            break
        s = inner
    return s


def without_some(s):
    u = unparen(s)
    if u.startswith("Some "):
        x = unparen(u[len("Some "):])
        return x or None
    return None


def tidy(d):
    """Return (state text by number, label (text, silent) by number)."""
    non_silent = [t for t, silent in d.labels.values() if not silent]
    all_some = bool(non_silent) and all(without_some(t) is not None for t in non_silent)
    labels = {}
    for n, (t, silent) in d.labels.items():
        if silent:
            labels[n] = (TAU, True)
        elif all_some:
            labels[n] = (without_some(t), False)
        else:
            labels[n] = (unparen(t), False)
    return {n: unparen(t) for n, t in d.states.items()}, labels


# --- the diagram ------------------------------------------------------------


def merge(d, labels):
    """Parallel arrows made one: [(src, dst, [label (text, silent)...])], first-seen order."""
    seen = {}
    order = []
    for s, l, t in d.arrows:
        key = (s, t)
        if key not in seen:
            seen[key] = []
            order.append(key)
        if labels[l] not in seen[key]:
            seen[key].append(labels[l])
    return [(s, t, seen[(s, t)]) for s, t in order]


def back_arrows(d, arrows):
    """The arrows (src, dst) that close a cycle: to a state a depth-first search from
    the initial state (then from each state it did not reach, by number) is still in."""
    succ = {}
    for s, t, _ in arrows:
        if s != t:
            succ.setdefault(s, []).append(t)
    state = {}  # 1: on the stack, 2: done
    back = set()
    for root in [d.initial] + sorted(d.states):
        if root in state or root not in d.states:
            continue
        state[root] = 1
        stack = [(root, iter(succ.get(root, [])))]
        while stack:
            u, it = stack[-1]
            for v in it:
                if state.get(v) == 1:
                    back.add((u, v))
                elif v not in state:
                    state[v] = 1
                    stack.append((v, iter(succ.get(v, []))))
                    break
            else:
                state[u] = 2
                stack.pop()
    return back


def longest_path(arrows, back, start, goal):
    """The most arrows on a path from [start] to [goal] without the back arrows (1 if none)."""
    succ = {}
    for s, t, _ in arrows:
        if s != t and (s, t) not in back:
            succ.setdefault(s, []).append(t)
    memo = {}

    def go(v):
        if v == goal:
            return 0
        if v in memo:
            return memo[v]
        best = None
        for w in succ.get(v, []):
            r = go(w)
            if r is not None and (best is None or r + 1 > best):
                best = r + 1
        memo[v] = best
        return best

    r = go(start)
    return max(1, r or 1)


def first_word(text):
    return text.split(" ", 1)[0] if text else ""


def kind_of(labels):
    """The kind of an arrow with [labels]: their first word, if they share it; none if silent."""
    words = {first_word(t) for t, silent in labels if not silent}
    return words.pop() if len(words) == 1 and "" not in words else None


def q(s):
    """A DOT string literal."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def html(s):
    """[s] as HTML-like label text."""
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;").replace("\n", " "))


def label_markup(ls):
    """The labels [ls] (text, silent) as the text of an HTML-like label, a line each."""
    return "<BR/>".join(TAU_MARKUP if silent else html(t) for t, silent in ls)


def label_value(ls):
    """The value of a DOT label for the labels [ls] (text, silent), a line each. A silent step is a
    bold italic tau in a math font, which a plain string cannot be: when one is among them the value
    is an HTML-like label, <...>; otherwise a quoted string."""
    if any(silent for _, silent in ls):
        return "<" + label_markup(ls) + ">"
    return q("\n".join(t for t, _ in ls))


def label_node(ls, rankdir, after, frame=None):
    """The HTML-like label of the node that is the label [ls] of an arrow: the text in a cell with a
    port, t, for the arrow's halves, and HEAD_ALLOWANCE of nothing after it (below, or to its right:
    [after]) or before it, which makes the line to the arrowhead as long as the other."""
    border = ' BORDER="1" STYLE="ROUNDED" COLOR=%s' % q(frame) if frame else ""
    cell = '<TD PORT="t" BGCOLOR="white" CELLPADDING="1"%s>%s</TD>' % (border, label_markup(ls))
    if rankdir in ("TB", "BT"):
        pad = '<TR><TD HEIGHT="%d"></TD></TR>' % HEAD_ALLOWANCE
        rows = "<TR>" + cell + "</TR>" + pad if after else pad + "<TR>" + cell + "</TR>"
    else:
        pad = '<TD WIDTH="%d"></TD>' % HEAD_ALLOWANCE
        rows = "<TR>" + cell + pad + "</TR>" if after else "<TR>" + pad + cell + "</TR>"
    return '<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0">' + rows + "</TABLE>>"


def to_dot(d, opts):
    states, labels = tidy(d)
    arrows = merge(d, labels)
    back = back_arrows(d, arrows)
    colour_of = dict(opts.kind)

    def arrow_colour(ls):
        if all(silent for _, silent in ls):
            return "gray50"
        k = kind_of(ls)
        return colour_of.get(k, opts.kind_default) if k in colour_of or opts.kind_default else None

    font = ["fontname=%s" % q(opts.font)] if opts.font else []
    out = ["digraph G {"]
    out.append("  graph [rankdir=%s, nodesep=%s, ranksep=%s, splines=true%s];"
               % (opts.rankdir, opts.nodesep, opts.ranksep, ", " + ", ".join(font) if font else ""))
    out.append("  node [shape=box, style=\"rounded,filled\", fillcolor=white, fontsize=%s, margin=\"0.12,0.06\", height=0, width=0%s];"
               % (opts.fontsize, ", " + ", ".join(font) if font else ""))
    out.append("  edge [fontsize=%s, penwidth=1.4, arrowsize=0.8%s];"
               % (opts.fontsize - 1, ", " + ", ".join(font) if font else ""))
    has_out = {s for s, _, _ in arrows}
    numbered = (lambda n, t: "%d: %s" % (n, t)) if opts.numbers else (lambda n, t: t)
    for n in sorted(states):
        attrs = ["label=%s" % q(numbered(n, states[n]))]
        if n == d.initial:
            attrs.append("penwidth=2.5")
        if n not in has_out:
            attrs.append("peripheries=2")
        out.append("  s%d [%s];" % (n, ", ".join(attrs)))
    out.append("  start [shape=point, width=0.08, label=\"\"];")
    out.append("  start -> s%d [arrowsize=0.8];" % d.initial)
    k = 0
    for s, t, ls in arrows:
        colour = arrow_colour(ls)
        silent = all(sil for _, sil in ls)
        text = label_value(ls)
        cattr = ["color=%s" % q(colour), "fontcolor=%s" % q(colour)] if colour else []
        sattr = ["style=dashed"] if silent else []
        if s == t or opts.labels == "edge":
            # Graphviz makes a loop only as high as the gap to the next layer allows, a flat sliver at this
            # layer spacing: growing down it leaves the state's top right corner and comes back to its bottom
            # right one, so it is as high as the state and round (growing right it is round already)
            ports = ", tailport=ne, headport=se" if s == t and opts.rankdir in ("TB", "BT") else ""
            out.append("  s%d -> s%d [label=%s%s%s];" % (s, t, text, ports, "".join(", " + a for a in cattr + sattr)))
            continue
        k += 1
        is_back = (s, t) in back
        # the head is at the target, so the extra line is on the label's side towards it: the side the
        # arrow leaves by, for an arrow that goes the way the layout grows, and the side it arrives by
        # for an arrow back
        grows_forward = opts.rankdir in ("TB", "LR")
        frame = colour if opts.outline and colour and not silent else None
        lbl_attrs = ["shape=plain", "label=%s" % label_node(ls, opts.rankdir, grows_forward != is_back, frame)]
        if colour:
            lbl_attrs.append("fontcolor=%s" % q(colour))
        if silent:
            lbl_attrs.append("fontsize=%d" % (opts.fontsize + 3))
        out.append("  l%d [%s];" % (k, ", ".join(lbl_attrs)))
        ea = "".join(", " + a for a in cattr + sattr)
        into, outof = {"TB": ("n", "s"), "BT": ("s", "n"), "LR": ("w", "e"), "RL": ("e", "w")}[opts.rankdir]
        # both halves meet the text's cell at the middle of its sides, so that the line goes straight
        # through the label
        pi = ', headport="t:%s"' % into
        po = ', tailport="t:%s"' % outof
        if is_back:
            half = longest_path(arrows, back, t, s)
            # laid out target -> source, so that the label sits half way; the head is at the target
            out.append("  s%d -> l%d [dir=back, arrowtail=normal, arrowhead=none, minlen=%d%s%s];" % (t, k, half, ea, pi))
            out.append("  l%d -> s%d [arrowhead=none, minlen=%d%s%s];" % (k, s, half, ea, po))
        else:
            out.append("  s%d -> l%d [arrowhead=none, weight=8%s%s];" % (s, k, ea, pi))
            out.append("  l%d -> s%d [weight=8%s%s];" % (k, t, ea, po))
    if d.incomplete:
        out.append("  label=%s; labelloc=b; fontsize=%d;"
                   % (q("Incomplete: some states or transitions may be missing."), opts.fontsize - 1))
    out.append("}")
    return "\n".join(out) + "\n"


# --- command line -----------------------------------------------------------


def is_graph_dump(path):
    """Whether [path] is a dump of an LTS or FSM (and not, say, a bisimilarity result)."""
    try:
        with open(path, encoding="utf-8") as f:
            return any(HEADER.match(line) for _, line in zip(range(12), f))
    except (OSError, UnicodeDecodeError):
        return False


def latest_dump(directory):
    cands = [p for p in Path(directory).glob("*.txt") if is_graph_dump(p)]
    if not cands:
        sys.exit("no LTS or FSM dump in %s (set `MeBi Config Output \"DumpResults\" True.`)" % directory)
    return max(cands, key=lambda p: p.stat().st_mtime)


def base_name(d, path):
    stem = d.origin.split(",")[0].split(".")[-1] if d.origin else ""
    term = d.terms.split(" ")[0] if d.terms else ""
    name = "-".join(x for x in (stem, term) if x) or Path(path).stem
    return re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-") or "diagram"


def make_parser():
    ap = argparse.ArgumentParser(description="Draw an LTS or FSM from MeBi's plain-text dump with Graphviz.",
                                 epilog="See the top of this file for the details.")
    ap.add_argument("dump", nargs="?", help="a plain-text dump (or a directory: its newest dump)")
    ap.add_argument("--latest", nargs="?", const="_dumps", metavar="DIR", help="the newest dump in DIR (default _dumps)")
    ap.add_argument("-T", dest="format", default="png", choices=["png", "pdf", "svg", "dot"])
    ap.add_argument("-o", dest="out", help="where to write, without the extension (default ./_diagrams/<name>)")
    ap.add_argument("--rankdir", default="TB", choices=["TB", "LR", "BT", "RL"], help="TB: down; LR: to the right (landscape)")
    ap.add_argument("--labels", default="node", choices=["node", "edge"])
    ap.add_argument("--kind", action="append", default=[], metavar="KIND=COLOUR", help="colour the arrows and labels of a kind")
    ap.add_argument("--kind-default", metavar="COLOUR", help="the colour of the kinds with none of their own")
    ap.add_argument("--outline", action="store_true", help="a thin frame, in the kind's colour, round a coloured label")
    ap.add_argument("--numbers", action="store_true", help="show each state's number in the dump, to cross-reference it")
    ap.add_argument("--font", help="a font name Graphviz can find (default its own)")
    ap.add_argument("--fontsize", type=int, default=11)
    ap.add_argument("--nodesep", default="0.3")
    ap.add_argument("--ranksep", default="0.25")
    ap.add_argument("--dpi", default="150", help="for png")
    ap.add_argument("--max-states", type=int, default=150, help="refuse a bigger dump (0: no limit)")
    ap.add_argument("--timeout", type=int, default=300, help="seconds dot may take")
    ap.add_argument("--dot", default=os.environ.get("DOT", "dot"), help="the dot program (or $DOT)")
    return ap


def normalise(a, ap):
    """Turn the --kind strings of [a] into (kind, colour) pairs; [ap] reports a bad one."""
    kinds = []
    for k in a.kind:
        if "=" not in k:
            ap.error("--kind wants KIND=COLOUR, not %r" % k)
        name, colour = k.split("=", 1)
        kinds.append((name, colour))
    a.kind = kinds
    a.kind_default = a.kind_default or None
    return a


def main(argv=None):
    ap = make_parser()
    a = ap.parse_args(argv)

    if a.latest is not None:
        path = latest_dump(a.latest)
    elif a.dump:
        path = Path(a.dump)
        if path.is_dir():
            path = latest_dump(path)
    else:
        ap.error("give a dump, or --latest")
    try:
        d = parse(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        sys.exit("%s: %s" % (path, e))
    if a.max_states and len(d.states) > a.max_states:
        sys.exit("%s has %d states, over --max-states %d: the layout's time grows quickly with size; raise it, or 0 for none"
                 % (path.name, len(d.states), a.max_states))
    normalise(a, ap)

    base = Path(a.out) if a.out else Path("_diagrams") / base_name(d, path)
    base.parent.mkdir(parents=True, exist_ok=True)
    dot_path = base.with_suffix(".dot") if base.suffix == "" else Path(str(base) + ".dot")
    dot_path.write_text(to_dot(d, a), encoding="utf-8")
    print(dot_path)
    if a.format == "dot":
        return 0
    exe = shutil.which(a.dot) if os.sep not in a.dot else a.dot
    if not exe:
        sys.exit("`dot` (Graphviz) is not on the PATH, so only %s was written. Install Graphviz, or `nix shell nixpkgs#graphviz`, "
                 "or give --dot." % dot_path)
    target = Path(str(base) + "." + a.format)
    cmd = [exe, "-T" + a.format, str(dot_path), "-o", str(target)]
    if a.format == "png":
        cmd.insert(1, "-Gdpi=" + a.dpi)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=a.timeout)
    except subprocess.TimeoutExpired:
        sys.exit("dot ran past %d s and was stopped; %s is kept" % (a.timeout, dot_path))
    if r.returncode:
        sys.exit("dot failed: %s" % r.stderr.strip())
    print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
