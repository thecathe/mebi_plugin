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

(** A diagram. [incomplete] says the LTS or FSM it is of is not the whole
    system, which the picture notes. *)
type t =
  { nodes : node list
  ; edges : edge list
  ; incomplete : bool
  }

(** [escape s] is [s] as LaTeX text: its special characters are written so
    that they print as themselves, and its line breaks and tabs become
    spaces. Raises nothing. *)
val escape : string -> string

(** [merge edges] is [edges] with those between the same two states made one,
    as [(src, dst, labels)], the labels in the order they were given and
    without repeats, sorted by [(src, dst)]. Raises nothing. *)
val merge : edge list -> (int * int * label list) list

(** [picture d] is [d]'s TikZ [tikzpicture], to [\input] into a document
    that has loaded the libraries {!Draw_style.tikzset} lists, and either its
    style file or styles of its own. Every state is a node named [s<id>];
    arrows between the same two states share one, labelled with all of
    theirs, one to a line; a state's arrow to itself is drawn after the
    layout, as the layered layout leaves it out. Raises nothing. *)
val picture : t -> string

(** [wrapper ~name] is a LuaLaTeX document that draws [name].tikz with
    [name].style.tikz, on a page exactly as large as the picture, to be
    compiled in the files' directory. It does not need [standalone]. Raises
    nothing. *)
val wrapper : name:string -> string
