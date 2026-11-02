(** A state diagram as TikZ ([MeBi Draw]).

    The plugin builds a {!t} from an LTS or FSM, with its states and labels
    already printed as text, and this turns it into a TikZ picture laid out
    by LuaTeX's [graphdrawing] library (the layered layout). Nothing here
    says how anything looks: the picture names a style per kind of thing
    ({!Draw_style.use}), defined apart ({!Draw_style.tikzset}).

    Contains no reference to the Rocq API. *)

(** An arrow's label: a silent step, drawn as [τ], or a label as printed. *)
type label =
  | Silent
  | Label of string

(** A state: [id] is its number in the plain-text dump of the same LTS or
    FSM, [text] its term as printed, and [terminal] whether it has no
    outgoing arrow. *)
type node =
  { id : int
  ; text : string
  ; initial : bool
  ; terminal : bool
  }

(** An arrow from the state numbered [src] to the one numbered [dst]. *)
type edge =
  { src : int
  ; label : label
  ; dst : int
  }

(** Where an arrow's label is drawn. [On_edge]: as a node of the layout, on the
    arrow's way, so that the layout keeps room for it and the arrow runs
    through it. [Beside]: as TikZ places a quoted label, beside the last
    stretch of the arrow, with no room kept; it costs less layout time, and
    labels can then cover each other or be taken for another arrow's. *)
type labels =
  | Beside
  | On_edge

(** A diagram. [incomplete] says the LTS or FSM it is of is not the whole
    system, which the picture notes. *)
type t =
  { nodes : node list
  ; edges : edge list
  ; incomplete : bool
  }

(** [unparen s] is [s] without the parentheses that enclose all of it, if
    any: ["(Idle, 0)"] is ["Idle, 0"], and ["((a))"] is ["a"], but ["(a) (b)"]
    and ["f (a)"] are as they are, and so is ["()"], which would leave
    nothing to draw. Surrounding spaces go too. Raises nothing. *)
val unparen : string -> string

(** [tidy d] is [d] with its text made fit for a picture. The printed terms
    of a state and a label come wrapped in parentheses, which a state's box
    and a label's place on its arrow make redundant, so each is {!unparen}'d.
    And if every label that is not silent is [Some x], the wrapper says
    nothing (a silent step is drawn as [τ], and was [None]), so each is
    drawn as [x]. A label that is not [Some x] stops that, so that a
    diagram with a bare [None] or a label of another form is left as it is.
    Raises nothing. *)
val tidy : t -> t

(** [escape s] is [s] as LaTeX text: its special characters are written so
    that they print as themselves, and its line breaks and tabs become
    spaces. Raises nothing. *)
val escape : string -> string

(** [merge edges] is [edges] with those between the same two states made one,
    as [(src, dst, labels)], the labels in the order they were given and
    without repeats, sorted by [(src, dst)]. Raises nothing. *)
val merge : edge list -> (int * int * label list) list

(** [back_arrows d] are the arrows of [d], as [(src, dst)], that close a
    cycle: found by a depth-first search from the initial state, then from
    each state it did not reach, in the order of their numbers, they are the
    arrows to a state the search is still inside. Without them the rest are
    acyclic. A state's arrow to itself is not one. Raises nothing. *)
val back_arrows : t -> (int * int) list

(** [picture d] is [d]'s TikZ [tikzpicture], to [\input] into a document
    that has loaded the libraries {!Draw_style.tikzset} lists, and either its
    style file or styles of its own. Every state is a node named [s<id>],
    with its style named on it (not given to [\graph] for all its nodes, so
    that a label's node does not inherit it); arrows between the same two
    states share one, labelled with all of theirs, one to a line; a state's
    arrow to itself is drawn after the layout, as the layered layout leaves
    it out, with its label beside it. [labels] says where the other arrows'
    labels go ({!labels}, [On_edge] by default). On the edge, a label is a
    node [e<k>], and the arrow is two, [s -> e<k> -> t]: the two arrows of a
    pair of states are then not bent apart, as each has a label node to
    itself. An arrow in {!back_arrows} is laid out from its target to its
    source, each half spanning as many layers as the longest path it closes
    has arrows, so that its label sits half way along it; its arrowhead is a
    decoration of the first half ({!Draw_style.back_tip}), which the layout
    does not read as the arrow's direction. Raises nothing. *)
val picture : ?labels:labels -> t -> string

(** [wrapper ~name] is a LuaLaTeX document that draws [name].tikz with
    [name].style.tikz, on a page exactly as large as the picture, to be
    compiled in the files' directory. It does not need [standalone]. Raises
    nothing. *)
val wrapper : name:string -> string
