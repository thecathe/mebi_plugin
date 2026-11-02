(* See the [.mli]. *)
type component =
  | Layout
  | State
  | Initial
  | Terminal
  | Edge
  | Label
  | Silent_edge
  | Silent_label
  | Two_way
  | Loop
  | Caption

(* See the [.mli]. *)
let components : component list =
  [ Layout
  ; State
  ; Initial
  ; Terminal
  ; Edge
  ; Label
  ; Silent_edge
  ; Silent_label
  ; Two_way
  ; Loop
  ; Caption
  ]
;;

(* See the [.mli]. *)
let name : component -> string = function
  | Layout -> "Layout"
  | State -> "State"
  | Initial -> "Initial"
  | Terminal -> "Terminal"
  | Edge -> "Edge"
  | Label -> "Label"
  | Silent_edge -> "SilentEdge"
  | Silent_label -> "SilentLabel"
  | Two_way -> "TwoWay"
  | Loop -> "Loop"
  | Caption -> "Caption"
;;

(* See the [.mli]. *)
let of_string (s : string) : component option =
  let lower : string = String.lowercase_ascii s in
  List.find_opt
    (fun (c : component) ->
      String.equal (String.lowercase_ascii (name c)) lower)
    components
;;

(* See the [.mli]. *)
let use : component -> string = function
  | Layout -> "mebi layout"
  | State -> "mebi state"
  | Initial -> "mebi initial"
  | Terminal -> "mebi terminal"
  | Edge -> "mebi edge"
  | Label -> "mebi label"
  | Silent_edge -> "mebi silent edge"
  | Silent_label -> "mebi silent label"
  | Two_way -> "mebi two-way"
  | Loop -> "mebi loop"
  | Caption -> "mebi caption"
;;

(* See the [.mli]. *)
type direction =
  | Down
  | Right

(* See the [.mli]. *)
let direction_name : direction -> string = function
  | Down -> "Down"
  | Right -> "Right"
;;

(* See the [.mli]. [initial] draws the arrow into the initial state (TikZ's
   [automata] library); [initial text=] leaves it unlabelled. *)
let default : component -> string = function
  | Layout -> "layered layout, level distance=18mm, sibling distance=12mm"
  | State ->
    "draw=black, fill=white, rounded corners=7pt, font=\\small, inner \
     xsep=4pt, inner ysep=2pt"
  | Initial -> "very thick, initial, initial text="
  | Terminal -> "double"
  | Edge -> "draw=black, ->, thin"
  | Label ->
    "font=\\footnotesize, auto, fill=white, inner sep=1pt, align=center, \
     text=black"
  | Silent_edge -> "dashed, draw=gray"
  | Silent_label -> "text=gray, font=\\large\\boldmath"
  | Two_way -> "bend left=18"
  | Loop -> "loop above"
  | Caption -> "font=\\footnotesize\\itshape, text=gray"
;;

(* See the [.mli]. *)
let balanced (opts : string) : bool =
  let depth : int ref = ref 0 in
  let ok : bool ref = ref true in
  String.iter
    (function
      | '{' -> incr depth
      | '}' ->
        decr depth;
        if !depth < 0 then ok := false
      | _ -> ())
    opts;
  !ok && Int.equal !depth 0
;;

(* See the [.mli]. At most one entry per component. *)
type t = (component * string) list

(* See the [.mli]. *)
let empty : t = []

(* See the [.mli]. *)
let get (c : component) (s : t) : string =
  Stdlib.Option.value (List.assoc_opt c s) ~default:""
;;

(* See the [.mli]. *)
let set (c : component) (opts : string) (s : t) : t =
  let rest : t = List.filter (fun (c', _) -> c' <> c) s in
  if String.equal (String.trim opts) "" then rest else (c, opts) :: rest
;;

(* See the [.mli]. *)
let is_default (s : t) : bool = List.is_empty s

(* See the [.mli]. In {!components}' order, whatever order they were set. *)
let describe (s : t) : string =
  match List.filter (fun c -> get c s <> "") components with
  | [] -> "every component has its default style"
  | set_ ->
    String.concat
      "; "
      (List.map (fun c -> Printf.sprintf "%s: %s" (name c) (get c s)) set_)
;;

(* See the [.mli]. *)
let back_tip : string = "mebi back tip"

(** [back_tip_definition] is what {!back_tip} is defined as: a decoration that
    draws an arrowhead at the start of the path, pointing back along it (not
    an arrow tip of the path's own, which the layered layout would read as the
    path's direction). *)
let back_tip_definition : string =
  "postaction={decorate, decoration={markings, mark=at position 0 with \
   {\\arrowreversed{>}}}}"
;;

(** [default_in direction c] is [default c], but for {!Layout} the one that
    grows in [direction]: the same distances, as the layers' own widths are
    already allowed for. *)
let default_in (direction : direction) (c : component) : string =
  match direction, c with
  | Right, Layout ->
    "layered layout, grow=right, level distance=18mm, sibling distance=12mm"
  | _ -> default c
;;

(** [join parts] is the non-blank [parts], comma separated. Raises nothing. *)
let join (parts : string list) : string =
  List.filter (fun p -> not (String.equal (String.trim p) "")) parts
  |> String.concat ", "
;;

(** [options direction c s] is [c]'s own TikZ options: its default, then the
    user's. *)
let options (direction : direction) (c : component) (s : t) : string =
  join [ default_in direction c; get c s ]
;;

(** [body c s] is what [c]'s style is defined as: the style it builds on,
    if any, then {!options}. A silent edge also has its label drawn in the
    silent label style, for that edge only. *)
let body (direction : direction) (c : component) (s : t) : string =
  let options : t -> string = options direction c in
  match c with
  | Initial | Terminal -> join [ use State; options s ]
  | Silent_edge ->
    join
      [ use Edge
      ; options s
      ; Printf.sprintf "every edge quotes/.style={%s}" (use Silent_label)
      ]
  | Silent_label -> join [ use Label; options s ]
  | Layout | State | Edge | Label | Two_way | Loop | Caption -> options s
;;

(** [key c] is the key [c]'s style is defined under. [\graph]'s own options
    are looked up under [graphs/], not [tikz/]. *)
let key (c : component) : string =
  match c with Layout -> "graphs/" ^ use c | _ -> use c
;;

(* See the [.mli]. *)
let tikzset ?(direction : direction = Down) (s : t) : string =
  String.concat
    "\n"
    ([ "% MeBi diagram styles, generated. The picture names these styles and"
     ; "% nothing else, so a document can define its own instead of loading"
     ; "% this file."
     ; "% Needs LuaLaTeX, with:"
     ; "%   \\usetikzlibrary{graphs,graphdrawing,arrows.meta,quotes,automata,"
     ; "%     decorations.markings}"
     ; "%   \\usegdlibrary{layered}"
     ; "\\tikzset{"
     ]
     @ [ String.concat
           ",\n"
           (List.map
              (fun c ->
                Printf.sprintf "  %s/.style={%s}" (key c) (body direction c s))
              components
            @ [ Printf.sprintf "  %s/.style={%s}" back_tip back_tip_definition ]
           )
       ; "}"
       ])
  ^ "\n"
;;
