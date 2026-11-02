(** The look of a diagram ([MeBi Config Draw Style]).

    A diagram's TikZ picture ({!Draw.picture}) never says how anything is
    drawn: it only names a style for each kind of thing in it, such as
    [mebi state] or [mebi silent edge]. What those names mean is defined
    apart, in the diagram's style file ({!tikzset}), from a built-in default
    for each {!component} followed by the user's own TikZ options for it.
    Later TikZ options win, so the user's override a default's.

    That keeps the look configurable at two levels. From Rocq, by setting
    options per component. And from LaTeX, by leaving the style file out
    and defining the same names in the document the picture is [\input]
    into.

    Contains no reference to the Rocq API. *)

(** The kinds of thing in a diagram, each with a style of its own. *)
type component =
  | Layout (** how the graph is laid out: the [\graph] options *)
  | State (** every state; {!Initial} and {!Terminal} build on it *)
  | Initial (** the initial state *)
  | Terminal (** a state with no outgoing edge *)
  | Edge (** every arrow; {!Silent_edge} builds on it *)
  | Label (** an arrow's label; {!Silent_label} builds on it *)
  | Silent_edge (** an arrow whose labels are all silent *)
  | Silent_label (** the label of a {!Silent_edge} *)
  | Two_way
  (** each of two arrows between the same two states, in opposite
      directions, which would otherwise be drawn on top of each other *)
  | Loop (** where a state's arrow to itself leaves and returns *)
  | Caption (** the note under an incomplete diagram *)

(** Every {!component}, in the order {!tikzset} defines them. *)
val components : component list

(** [name c] is [c]'s name in [MeBi Config Draw Style]: [Layout], [State],
    [Initial], [Terminal], [Edge], [Label], [SilentEdge], [SilentLabel],
    [TwoWay], [Loop] or [Caption]. Raises nothing. *)
val name : component -> string

(** [of_string s] is the {!component} {!name} gives [s], ignoring case, if
    there is one. Raises nothing. *)
val of_string : string -> component option

(** [use c] is the TikZ style name the picture applies for [c], such as
    ["mebi state"]. Raises nothing. *)
val use : component -> string

(** [default c] is the TikZ options [c] has before anyone sets any, for a
    layout that grows {!Down}. Raises nothing. *)
val default : component -> string

(** Which way the layered layout grows: [Down], each layer below the one
    before it (the default), or [Right], each to the right of the one before,
    which makes a picture wider than it is tall. *)
type direction =
  | Down
  | Right

(** [direction_name d] is [Down] or [Right]. Raises nothing. *)
val direction_name : direction -> string

(** The name of the style a back arrow's first half adds ({!Draw.back_arrows}):
    a decoration that draws its arrowhead, pointing back along the path. It
    is not a {!component}, since it has no look to configure; it is defined,
    once, in {!tikzset}. *)
val back_tip : string

(** The names of three styles an arrow's halves add on the edge
    ({!Draw.picture}): {!forward} to each half of an arrow between two states,
    and {!back_first}, {!back_second} to the halves of an arrow back
    ({!Draw.back_arrows}), its target's and its source's. Each says which side
    of its two ends the half leaves from and arrives at ([tail anchor] and
    [head anchor]), as {!tikzset} defines them for the layout's direction.
    They are not {!component}s. *)
val forward : string

val back_first : string
val back_second : string

(** [balanced opts] is whether the braces in [opts] close in order. Options
    with unbalanced braces would swallow the rest of the style file, so
    callers refuse them. Raises nothing. *)
val balanced : string -> bool

(** A kind of label, the colour of which can be set: [Named k] is the labels
    whose first word is [k] (the kind of [Insert ten] is [Insert]), and
    [Default] those whose kind has no colour of its own. *)
type kind =
  | Named of string
  | Default

(** [valid_kind k] is whether [k] can be the name of a kind: letters, digits,
    [-] and [.] only, as it becomes part of a TikZ style name. *)
val valid_kind : string -> bool

(** [kind_name k] is [k]'s name in [MeBi Config Draw Kind]: the word itself, or
    [Default]. Raises nothing. *)
val kind_name : kind -> string

(** [use_kind k] is the TikZ style name the picture gives an arrow of kind [k]
    (such as ["mebi kind Insert"]), and {!use_kind_label} the one for its
    label. They are defined in {!tikzset} for a kind with a colour, and only
    then. Raises nothing. *)
val use_kind : kind -> string

val use_kind_label : kind -> string

(** The user's own TikZ options, per {!component}, and the colour of each kind
    of label. *)
type t

(** No component set: the built-in look. *)
val empty : t

(** [set c opts s] is [s] with [c]'s options [opts], which follow the
    default's and so win over it. An empty or blank [opts] clears [c]'s.
    Raises nothing. *)
val set : component -> string -> t -> t

(** [get c s] is the options [s] has for [c], or [""]. Raises nothing. *)
val get : component -> t -> string

(** [set_kind k colour s] is [s] with [k]'s colour [colour], a colour name or
    an xcolor expression, such as [red] or [blue!75!black]: it colours the
    arrows of that kind and their labels' text (and, with {!set_outline}, a
    light frame round the labels). A blank [colour] clears it. Nothing is coloured that was not
    given a colour. Raises nothing. *)
val set_kind : kind -> string -> t -> t

(** [kind_colour k s] is [k]'s colour in [s], if it has one. Raises nothing. *)
val kind_colour : kind -> t -> string option

(** [kinds s] are the kinds of [s] with a colour, with it: the named ones by
    name, then {!Default}. Raises nothing. *)
val kinds : t -> (kind * string) list

(** [set_outline b s] is [s] with the coloured outline of a kind's labels
    on ([true]) or off ([false], the default): a light frame, 40% of the
    kind's colour, with rounded corners. Raises nothing. *)
val set_outline : bool -> t -> t

(** [outline s] is whether [s] has the outline on. Raises nothing. *)
val outline : t -> bool

(** [is_default s] is whether nothing of [s] is set: no component's options,
    no kind's colour and no outline. Raises nothing. *)
val is_default : t -> bool

(** [describe s] is a sentence saying which components of [s] are set, and the
    kinds with a colour, and to what, for messages. Raises nothing. *)
val describe : t -> string

(** [tikzset ?direction s] is the contents of the diagram's style file: a
    [\tikzset] defining {!use}'s name for every {!component} from its
    {!default} and [s]'s options. [direction] ({!Down} by default) is the
    way the layout grows: it changes {!Layout}'s default (for {!Right}, to add
    [grow=right] and a larger level distance), and so can be overridden by
    the user's own options for it. The same arguments always give the same text. Raises
    nothing. *)
val tikzset : ?direction:direction -> t -> string
