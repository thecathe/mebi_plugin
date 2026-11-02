(** Writing a diagram's files, and compiling them ([MeBi Draw]).

    A diagram is three files in one directory: [<name>.tikz], the picture
    ({!Draw.picture}); [<name>.style.tikz], its styles ({!Draw_style.tikzset});
    and [<name>.tex], a document that draws the two ({!Draw.wrapper}). The
    rest is made from those by programs this does not provide, and so may
    not find: [lualatex] for a PDF, then [pdftocairo] or [gs] for a PNG.
    Each runs as a child process that is killed at a time limit, so a layout
    that does not finish cannot hold the session. A program that is missing,
    fails or is killed leaves the files made so far, and is reported as a
    {!problem}, not raised.

    Contains no reference to the Rocq API. *)

(** What to make: the three source files only, those and the PDF, or those,
    the PDF and a PNG of it. *)
type format =
  | Tex
  | Pdf
  | Png

(** [format_name f] is [f] as [MeBi Config Draw Format] spells it: [TeX],
    [PDF] or [PNG]. Raises nothing. *)
val format_name : format -> string

(** [format_of_string s] is the {!format} {!format_name} gives [s], ignoring
    case, if there is one. Raises nothing. *)
val format_of_string : string -> format option

(** Which program lays a diagram out: [Luatex], the default, with TikZ's
    layered layout in a LuaLaTeX document, or [Graphviz], which writes DOT and
    has [dot] draw it. Nothing here needs either until a PDF or a PNG is
    asked for. *)
type engine =
  | Luatex
  | Graphviz

(** [engine_name e] is [e] as [MeBi Config Draw Engine] spells it: [LuaTeX] or
    [Graphviz]. Raises nothing. *)
val engine_name : engine -> string

(** [engine_of_string s] is the {!engine} {!engine_name} gives [s], ignoring
    case, if there is one. Raises nothing. *)
val engine_of_string : string -> engine option

(** Why a file was not made. *)
type problem =
  | Missing_tool of
      { tools : string list (** any one of these would do *)
      ; needed_for : string
      }
  | Failed of
      { tool : string
      ; detail : string (** the first error [tool] logged, or its exit code *)
      ; log : string option (** [tool]'s log, kept for the user to read *)
      }
  | Timed_out of
      { tool : string
      ; seconds : float
      }

(** [describe_problem p] is [p] as a sentence, saying what to do about it
    where there is something to do. Raises nothing. *)
val describe_problem : problem -> string

(** [valid_name s] is whether [s] can be a diagram's name: letters, digits,
    [-], [_] and [.], not starting with [-] or [.], so that TeX can open
    its files and no program takes it for an option. Raises nothing. *)
val valid_name : string -> bool

(** [name_of_term ~kind term] is a diagram's name made from what it is of:
    [kind] ([lts] or [fsm]), then [term] lower-cased, with each run of other
    characters one [-], cut to forty characters. A [term] with no letters or
    digits gives [kind]. Raises nothing. *)
val name_of_term : kind:string -> string -> string

(** [find_exe cmd] is the first executable file called [cmd] in the
    directories of [PATH], if there is one. Raises nothing. *)
val find_exe : string -> string option

(** How a child process ended. *)
type status =
  | Exited of int
  | Killed (** still running at the time limit, and killed *)
  | Unrunnable of string

(** [run ~timeout ~dir argv] runs [argv] with [dir] as its working
    directory and its input and output discarded, and waits at most
    [timeout] seconds for it to end. Raises nothing. *)
val run : timeout:float -> dir:string -> string list -> status

(** [write ?labels ?direction ~dir ~name ~style d] writes [d]'s three files
    into [dir], which it makes if need be, replacing any of the same names,
    and is their paths, in the order above. [labels] is where the arrows'
    labels go ({!Draw.picture}), and [direction] the way the layout grows
    ({!Draw_style.tikzset}).

    @raise Sys_error if the directory or a file cannot be made (propagated). *)
val write
  :  ?labels:Draw.labels
  -> ?direction:Draw_style.direction
  -> dir:string
  -> name:string
  -> style:Draw_style.t
  -> Draw.t
  -> string list

(** [render ~format ~timeout ~dir ~name] makes what [format] asks for beyond
    the files {!write} wrote, each program given [timeout] seconds, and is
    the files it made and why it did not make the others. Raises
    nothing. *)
val render
  :  format:format
  -> timeout:float
  -> dir:string
  -> name:string
  -> string list * problem list

(** [write_dot ?labels ?direction ~dir ~name ~style d] writes [d]'s DOT
    ({!Draw_dot.dot}) as [<name>.dot] into [dir], which it makes if need be,
    replacing a file of that name, and is its path, in a list. It is the
    Graphviz engine's only file but the picture: with {!Tex}, the whole
    diagram.

    @raise Sys_error if the directory or the file cannot be made (propagated).
*)
val write_dot
  :  ?labels:Draw.labels
  -> ?direction:Draw_style.direction
  -> dir:string
  -> name:string
  -> style:Draw_style.t
  -> Draw.t
  -> string list

(** [render_dot ~format ~timeout ~dir ~name] makes what [format] asks for from
    [<name>.dot] by Graphviz's [dot], killed at [timeout] seconds: a PDF for
    {!Pdf}, a PDF and a PNG for {!Png}, nothing for {!Tex}. It is the files it
    made and why it did not make the others: a missing [dot], one that fails
    (its message is discarded, so the problem says how to see it) or one that
    runs too long is a {!problem}, never raised. Raises nothing. *)
val render_dot
  :  format:format
  -> timeout:float
  -> dir:string
  -> name:string
  -> string list * problem list
