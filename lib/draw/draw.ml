(* See the [.mli]. *)
type label =
  | Silent
  | Label of string

(* See the [.mli]. *)
type node =
  { id : int
  ; text : string
  ; initial : bool
  ; terminal : bool
  }

(* See the [.mli]. *)
type edge =
  { src : int
  ; label : label
  ; dst : int
  }

(* See the [.mli]. *)
type t =
  { nodes : node list
  ; edges : edge list
  ; incomplete : bool
  }

(* See the [.mli]. Two hyphens in a row would print as a dash, so the second
   follows an empty group. *)
let escape (s : string) : string =
  let b : Buffer.t = Buffer.create (String.length s * 2) in
  let after_hyphen : bool ref = ref false in
  String.iter
    (fun c ->
      (match c with
       | '-' ->
         if !after_hyphen then Buffer.add_string b "{}";
         Buffer.add_char b '-'
       | '\\' -> Buffer.add_string b "\\textbackslash{}"
       | '{' -> Buffer.add_string b "\\{"
       | '}' -> Buffer.add_string b "\\}"
       | '&' -> Buffer.add_string b "\\&"
       | '%' -> Buffer.add_string b "\\%"
       | '$' -> Buffer.add_string b "\\$"
       | '#' -> Buffer.add_string b "\\#"
       | '_' -> Buffer.add_string b "\\_"
       | '^' -> Buffer.add_string b "\\textasciicircum{}"
       | '~' -> Buffer.add_string b "\\textasciitilde{}"
       | '<' -> Buffer.add_string b "\\textless{}"
       | '>' -> Buffer.add_string b "\\textgreater{}"
       | '|' -> Buffer.add_string b "\\textbar{}"
       | '\n' | '\r' | '\t' -> Buffer.add_char b ' '
       | c -> Buffer.add_char b c);
      after_hyphen := Char.equal c '-')
    s;
  Buffer.contents b
;;

(* See the [.mli]. *)
let merge (edges : edge list) : (int * int * label list) list =
  let add (acc : ((int * int) * label list) list) (e : edge) =
    let key : int * int = e.src, e.dst in
    match List.assoc_opt key acc with
    | None -> (key, [ e.label ]) :: acc
    | Some ls when List.mem e.label ls -> acc
    | Some ls -> (key, ls @ [ e.label ]) :: List.remove_assoc key acc
  in
  List.fold_left add [] edges
  |> List.map (fun ((src, dst), ls) -> src, dst, ls)
  |> List.sort (fun (s, d, _) (s', d', _) -> compare (s, d) (s', d'))
;;

(** [label_text l] is [l] as LaTeX text. *)
let label_text : label -> string = function
  | Silent -> "$\\tau$"
  | Label s -> escape s
;;

(** [label_node labels] is the quoted label of an arrow with [labels]: the
    text in braces, so its commas and brackets are not options, one label to
    a line. *)
let label_node (labels : label list) : string =
  Printf.sprintf "\"{%s}\"" (String.concat "\\\\ " (List.map label_text labels))
;;

(** [node_line n] is the statement for the state [n]. *)
let node_line (n : node) : string =
  let styles : string list =
    (if n.initial then [ Draw_style.(use Initial) ] else [])
    @ if n.terminal then [ Draw_style.(use Terminal) ] else []
  in
  Printf.sprintf
    "    s%i[as={%s}%s];"
    n.id
    (escape n.text)
    (String.concat "" (List.map (fun s -> ", " ^ s) styles))
;;

(** [edge_options labels] is the style of an arrow with [labels]: the silent
    one if they are all silent. *)
let edge_options (labels : label list) : string =
  if List.for_all (fun l -> l = Silent) labels
  then Draw_style.(use Silent_edge)
  else Draw_style.(use Edge)
;;

(* See the [.mli]. *)
let picture (d : t) : string =
  let nodes : node list =
    List.sort (fun a b -> Int.compare a.id b.id) d.nodes
  in
  let arrows, loops =
    List.partition (fun (s, t, _) -> not (Int.equal s t)) (merge d.edges)
  in
  (* An arrow with one back between the same states would be drawn on top of
     it, so each of the two is bent. *)
  let has_opposite (s : int) (t : int) : bool =
    List.exists (fun (s', t', _) -> Int.equal s' t && Int.equal t' s) arrows
  in
  let arrow_line ((s, t, ls) : int * int * label list) : string =
    Printf.sprintf
      "    s%i ->[%s%s, %s] s%i;"
      s
      (edge_options ls)
      (if has_opposite s t then ", " ^ Draw_style.(use Two_way) else "")
      (label_node ls)
      t
  in
  let loop_line ((s, _, ls) : int * int * label list) : string =
    Printf.sprintf
      "  \\path (s%i) edge[%s, %s, %s] (s%i);"
      s
      (edge_options ls)
      Draw_style.(use Loop)
      (label_node ls)
      s
  in
  let caption : string list =
    if d.incomplete || List.is_empty nodes
    then
      [ Printf.sprintf
          "  \\node[%s%s] %s{%s};"
          Draw_style.(use Caption)
          (if List.is_empty nodes then "" else ", anchor=north")
          (if List.is_empty nodes
           then ""
           else "at (current bounding box.south) ")
          (if List.is_empty nodes
           then "Empty: no states."
           else "Incomplete: some states or transitions may be missing.")
      ]
    else []
  in
  let graph : string list =
    if List.is_empty nodes
    then []
    else
      [ Printf.sprintf
          "  \\graph[%s, nodes={%s}, edges={%s}]{"
          Draw_style.(use Layout)
          Draw_style.(use State)
          Draw_style.(use Edge)
      ]
      @ List.map node_line nodes
      @ List.map arrow_line arrows
      @ [ "  };" ]
  in
  String.concat
    "\n"
    ([ "% MeBi diagram: the states, then the arrows. Styles are named, not set,"
     ; "% here: see the style file."
     ; Printf.sprintf
         "\\begin{tikzpicture}[>=Stealth, every edge quotes/.style={%s}]"
         Draw_style.(use Label)
     ]
     @ graph
     @ List.map loop_line loops
     @ caption
     @ [ "\\end{tikzpicture}" ])
  ^ "\n"
;;

(* See the [.mli]. [\hoffset] and [\voffset] undo LaTeX's one-inch page
   origin, and [\pagewidth] and [\pageheight] are LuaTeX's: with the page
   exactly as large as the picture, no cropping tool is needed. *)
let wrapper ~(name : string) : string =
  String.concat
    "\n"
    [ "% Compile with LuaLaTeX, in this directory."
    ; "\\documentclass{article}"
    ; "\\usepackage{tikz}"
    ; "\\usetikzlibrary{graphs,graphdrawing,arrows.meta,quotes,automata}"
    ; "\\usegdlibrary{layered}"
    ; "\\pagestyle{empty}"
    ; "\\setlength{\\parindent}{0pt}"
    ; "\\newsavebox{\\mebibox}"
    ; "\\begin{document}"
    ; Printf.sprintf "\\input{%s.style.tikz}" name
    ; Printf.sprintf "\\sbox{\\mebibox}{\\input{%s.tikz}}" name
    ; "\\hoffset=-1in \\voffset=-1in"
    ; "\\pagewidth=\\wd\\mebibox"
    ; "\\pageheight=\\dimexpr\\ht\\mebibox+\\dp\\mebibox\\relax"
    ; "\\shipout\\copy\\mebibox"
    ; "\\end{document}"
    ]
  ^ "\n"
;;
