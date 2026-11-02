# `MeBi Draw`: how long LuaTeX's layout takes

Recorded 2026-11-01. This is what the default draw bound (50 states) and
the default time limit (60 seconds) rest on.

## Setup

AMD Ryzen 7 5700X (8 cores, 16 threads), 31GB RAM, Linux 7.2.9-zen1,
NixOS. TeX Live 2025 (LuaHBTeX 1.22.0, pgf 3.1.11a). Plugin at
`feat/draw-lts`.

Each figure is the wall time of `lualatex d.tex` on the `d.tex`,
`d.tikz` and `d.style.tikz` that `Draw_output.write` writes with the
default styles: the layered layout of `\graph` (`graphdrawing`), which is
where the time goes. One run each, in `systemd-run --user --scope -p
MemoryMax=3G -p MemorySwapMax=0` under `timeout`.

The graphs are synthetic: `N` states; each state has an arrow to one of
the next three, and, 40% of the time, a second to a random state; six
labels; seed 7 (`Random.init 7`). That is about 1.4 arrows a state, as in the
coffee machine (31 states, 42 transitions), and mostly forward, with some
arrows back.

## Results

| states | arrows | time | note |
|---:|---:|---:|---|
| 31 | 44 | 1.7 s | the size of the coffee machine |
| 50 | 68 | 2.7 s | the default bound |
| 60 | 81 | 3.4 s | |
| 75 | 108 | 11.7 s | |
| 100 | 145 | 20.8 s | |
| 150 | 206 | 87.7 s | scope's peak memory 219MB |

The coffee machine of `examples/CoffeeMachineSimple.v` (31 states, 42
transitions) took 2.5 s to compile with the first prototype's markup (see
below).

**It is time that limits it, not memory.** The 150-state run peaked at
219MB. Past 100 states the time grows faster than the size: 50 to 100 states
is 8 times as long, and 100 to 150 is 4 times.

The default time limit (60 s) therefore lets the default bound and
`Bounds Draw States 100` finish, and stops `150`: a larger bound needs
`MeBi Config Bounds Draw Time` raised with it. A program stopped at the
limit is killed and reported as a warning; the TeX files stay.

(That is for `Labels Beside`, the placement these figures were measured
with. The default has since become `Labels OnEdge`; see the next section,
which moves the limit.)

## Labels as nodes of the layout (2026-11-02)

`Labels OnEdge`, the default since `fix/draw-label-nodes`, makes each
arrow's label a node of the layout and the arrow two, so the layout has
about 2.4 times the nodes. Measured with the same generator, seed, and
command as above, against `Labels Beside` (one run each, one synthetic
graph per size):

| states | arrows | `Beside` | `OnEdge` | factor |
|---:|---:|---:|---:|---:|
| 31 | 44 | 1.7 s | 3.8 s | 2.2 |
| 50 | 68 | 2.7 s | 7.0 s | 2.6 |
| 60 | 81 | 3.3 s | 8.5 s | 2.6 |
| 75 | 108 | 11.5 s | 40.2 s | 3.5 |
| 100 | 145 | 20.5 s | 84.7 s | 4.1 |

A different host from the one above: an Intel Core Ultra 5 125U (14
threads), 14GB RAM, Linux 7.0.0-42-generic, TeX Live 2025 from Nix
(LuaHBTeX 1.22.0, pgf 3.1.11a). The `Beside` column reproduces the first
table's figures (1.7, 2.7, 11.5 against 11.7, 20.5 against 20.8), so the two
hosts are comparable for this purpose. Same cap (`MemoryMax=3G`).

Re-measured the same day with an arrow back to an earlier state laid out
the other way round and its label pinned half way (`fix/draw-back-edge-label`;
the synthetic graphs have such arrows): `OnEdge` 31 states 3.6 s, 50 states
6.4 s, 75 states 41.0 s. The same, within a run's noise, so the pinning
costs nothing measurable.

The factor grows with size, as the layout's time does. So the default bound
(50 states) stays far inside the 60 s limit, **but `Bounds Draw States 100`
no longer finishes under `OnEdge` without `Bounds Draw Time` raised** (84.7 s
against 60 s); `Labels Beside` still does. Memory was not measured for these
runs. Two figures the devlog had for label nodes were estimates and were
wrong: "about 20 s at 50 states" (7.0 s) and "about 1.8 times at 31 states"
(2.2 times).

## An earlier series, and what it says about the figures

The same afternoon, a first prototype (a throwaway `awk` turning the
plain-text dump into simpler markup: tiny fonts, tighter spacing, no braces
round labels) gave: 31 states 2.5 s, 50 states 2.7 s, 60 states 8.1 s, 75
states 13.3 s, 100 states 27.5 s; and 300 and 1000 states unfinished at
240 s. A 150-state run was killed (exit 137 from the shell that ran it); I
guessed the memory cap, but the re-run above needed 219MB, so the cause
was something else, not established.

The two series agree at 50 states and differ at 60 (8.1 s against 3.4 s).
So the time depends on the graph's shape, not only its size: a different
random graph of the same size, or different spacing, moves it by a factor
of two or more. **Treat each figure as rough**: one run, one graph, one
host.

## Not measured

- Graphs with many more arrows a state: the transitions bound exists for
  these, but its default is not based on a measurement.
- Real LTSs larger than the coffee machine. Those with many cycles may lay
  out differently from these mostly-forward graphs.
- The time of the rest of `MeBi Draw`: extraction, decoding the terms and
  writing the files. At these sizes it is small beside `lualatex`.

## Reproducing

Build the generator against the library (`dune build ./lib/draw`), in a
scratch directory:

```ocaml
(* gen N dir: N states, each with an arrow to one of the next three, and a
   second to a random state 40% of the time. *)
let () =
  let n = int_of_string Sys.argv.(1) and dir = Sys.argv.(2) in
  Random.init 7;
  let edges = ref [] in
  let label () = Draw.Label (Printf.sprintf "L%d" (Random.int 6)) in
  for i = 0 to n - 1 do
    let a = i + 1 + Random.int 3 in
    if a < n then edges := { Draw.src = i; label = label (); dst = a } :: !edges;
    if Random.float 1.0 < 0.4
    then edges := { Draw.src = i; label = label (); dst = Random.int n } :: !edges
  done;
  let nodes =
    List.init n (fun i ->
      { Draw.id = i; text = Printf.sprintf "(S, %d)" i; initial = (i = 0); terminal = false })
  in
  let d = { Draw.nodes; edges = List.rev !edges; incomplete = false } in
  ignore (Draw_output.write ~dir ~name:"d" ~style:Draw_style.empty d)
```

```sh
OBJ=_build/default/lib/draw
ocamlfind ocamlopt -package unix -linkpkg -I $OBJ/.draw.objs/byte \
  -I $OBJ/.draw.objs/native $OBJ/draw.cmxa gen.ml -o gen
mkdir n100 && ./gen 100 n100 && cd n100 && time lualatex d.tex
```

(The generator's random numbers, and so the exact graphs, depend on the
OCaml version; the shape of the result should not.)
