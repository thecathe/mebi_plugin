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

(** [balanced opts] is whether the braces in [opts] close in order. Options
    with unbalanced braces would swallow the rest of the style file, so
    callers refuse them. Raises nothing. *)
val balanced : string -> bool

(** The user's own TikZ options, per {!component}. *)
type t

(** No component set: the built-in look. *)
val empty : t

(** [set c opts s] is [s] with [c]'s options [opts], which follow the
    default's and so win over it. An empty or blank [opts] clears [c]'s.
    Raises nothing. *)
val set : component -> string -> t -> t

(** [get c s] is the options [s] has for [c], or [""]. Raises nothing. *)
val get : component -> t -> string

(** [is_default s] is whether no component of [s] is set. Raises nothing. *)
val is_default : t -> bool

(** [describe s] is a sentence saying which components of [s] are set, and
    to what, for messages. Raises nothing. *)
val describe : t -> string

(** [tikzset ?direction s] is the contents of the diagram's style file: a
    [\tikzset] defining {!use}'s name for every {!component} from its
    {!default} and [s]'s options. [direction] ({!Down} by default) is the
    way the layout grows: it changes {!Layout}'s default (to add
    [grow=right] for {!Right}), and so can be overridden by the user's own
    options for it. The same arguments always give the same text. Raises
    nothing. *)
val tikzset : ?direction:direction -> t -> string
