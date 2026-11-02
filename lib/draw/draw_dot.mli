(** A diagram as Graphviz DOT ([MeBi Draw] with the Graphviz engine).

    {!dot} writes the text of a DOT graph for a {!Draw.t}, and nothing here
    runs Graphviz: {!Draw_output.render_dot} does, as a child process that a
    missing, failing or slow [dot] cannot turn into an error. What it draws
    follows {!Draw.picture}: the same arrows (parallel ones merged), the
    same kinds and their colours ({!Draw_style.kind_colour}), the initial
    state bold and with an arrow in, a state with no way out with a double
    border, a silent step dashed and grey and labelled with a bold italic [τ]
    (in Latin Modern Math, the font of TeX's [$\tau$], or the nearest to it
    that is installed), and an incomplete diagram saying so. The look is Graphviz's own; the TikZ styles
    ({!Draw_style.component}) do not apply.

    Contains no reference to the Rocq API. *)

(** [colour c] is the colour [c], as {!Draw_style.set_kind} takes it (a colour
    name or an xcolor expression, such as [blue!75!black]), as Graphviz can
    read it: an xcolor expression over xcolor's own base colours becomes
    [#rrggbb] (a mix of [p]% of the first with the rest, as xcolor does; white
    if none is given), and so does a plain xcolor base colour name, such as
    [orange] or [teal], which Graphviz draws differently or does not know;
    anything else ([#rrggbb], or a name only Graphviz knows) is left as it is.
    Raises nothing. *)
val colour : string -> string

(** [q s] is [s] as a DOT string literal, quoted, with its quotes and
    backslashes escaped and its line breaks written as [\n]. Raises nothing. *)
val q : string -> string

(** [html s] is [s] as HTML-like label text: [&], [<], [>] and quotes
    escaped, line breaks spaces. Raises nothing. *)
val html : string -> string

(** [dot ?labels ?direction ?style d] is the DOT text of [d]. [direction]
    ({!Draw_style.Down} by default) is the graph's [rankdir]: top to bottom or
    left to right. [labels] says where an arrow's label goes
    ({!Draw.labels}, [On_edge] by default): as a small node on the arrow, which
    both halves of the arrow meet at the middle of its sides, so that the
    line passes straight through it, and the layout keeps room for it (an
    arrow back to an earlier state is laid out the other way round, its head
    at its target and each half as long as {!Draw.back_spans} says, so that
    its label is half way along it); or [Beside], as Graphviz's own edge
    label. A state's arrow to itself keeps an edge label either way. [style]
    ({!Draw_style.empty} by default) gives the colour of each kind and
    whether a coloured label has an outline ({!Draw_style.outline}); nothing is
    coloured that has no colour in it. Raises nothing. *)
val dot
  :  ?labels:Draw.labels
  -> ?direction:Draw_style.direction
  -> ?style:Draw_style.t
  -> Draw.t
  -> string
