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
type labels =
  | Beside
  | On_edge

(* See the [.mli]. *)
type t =
  { nodes : node list
  ; edges : edge list
  ; incomplete : bool
  }

(** [wraps s] is whether the ['('] that [s] starts with is closed by the [')']
    it ends with, and not before: the parentheses enclose all of [s]. *)
let wraps (s : string) : bool =
  let n : int = String.length s in
  if n < 2 || not (Char.equal s.[0] '(' && Char.equal s.[n - 1] ')')
  then false
  else (
    let depth : int ref = ref 0 in
    let closed_early : bool ref = ref false in
    String.iteri
      (fun i c ->
        (match c with '(' -> incr depth | ')' -> decr depth | _ -> ());
        if Int.equal !depth 0 && i < n - 1 then closed_early := true)
      s;
    (not !closed_early) && Int.equal !depth 0)
;;

(* See the [.mli]. *)
let unparen (s : string) : string =
  let rec go (s : string) : string =
    let s : string = String.trim s in
    if wraps s
    then (
      let inner : string = String.trim (String.sub s 1 (String.length s - 2)) in
      if String.equal inner "" then s else go inner)
    else s
  in
  go s
;;

(** [without_some s] is [x] if [s] is [Some x] (with or without parentheses
    round it or round [x]), and [None] if it is not. *)
let without_some (s : string) : string option =
  let u : string = unparen s in
  let prefix : string = "Some " in
  if String.starts_with ~prefix u
  then (
    let x : string =
      unparen
        (String.sub
           u
           (String.length prefix)
           (String.length u - String.length prefix))
    in
    if String.equal x "" then None else Some x)
  else None
;;

(* See the [.mli]. *)
let tidy (d : t) : t =
  let texts : string list =
    List.filter_map
      (fun (e : edge) ->
        match e.label with Label s -> Some s | Silent -> None)
      d.edges
  in
  let all_some : bool =
    (not (List.is_empty texts))
    && List.for_all (fun s -> Stdlib.Option.is_some (without_some s)) texts
  in
  let label : label -> label = function
    | Silent -> Silent
    | Label s ->
      (match all_some, without_some s with
       | true, Some x -> Label x
       | _ -> Label (unparen s))
  in
  { d with
    nodes =
      List.map (fun (n : node) -> { n with text = unparen n.text }) d.nodes
  ; edges =
      List.map (fun (e : edge) -> { e with label = label e.label }) d.edges
  }
;;

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

(* See the [.mli]. *)
let back_arrows (d : t) : (int * int) list =
  let arrows : (int * int * label list) list =
    List.filter (fun (s, t, _) -> not (Int.equal s t)) (merge d.edges)
  in
  let succs : (int, int list) Hashtbl.t = Hashtbl.create 64 in
  List.iter
    (fun (s, t, _) ->
      Hashtbl.replace
        succs
        s
        (t :: Stdlib.Option.value ~default:[] (Hashtbl.find_opt succs s)))
    (List.rev arrows);
  let next (u : int) : int list =
    Stdlib.Option.value ~default:[] (Hashtbl.find_opt succs u)
  in
  (* [true]: on the stack of the search; [false]: finished *)
  let state : (int, bool) Hashtbl.t = Hashtbl.create 64 in
  let back : (int * int) list ref = ref [] in
  let rec visit (u : int) : unit =
    Hashtbl.replace state u true;
    List.iter
      (fun v ->
        match Hashtbl.find_opt state v with
        | Some true -> back := (u, v) :: !back
        | Some false -> ()
        | None -> visit v)
      (next u);
    Hashtbl.replace state u false
  in
  let by_id : node list =
    List.sort (fun a b -> Int.compare a.id b.id) d.nodes
  in
  List.iter
    (fun (n : node) -> if not (Hashtbl.mem state n.id) then visit n.id)
    (List.filter (fun (n : node) -> n.initial) by_id @ by_id);
  List.sort compare !back
;;

(** [longest_path next ~target ~from] is the number of arrows on the longest
    path from [from] to [target] along [next], which must have no cycle, or
    [None] if there is none. *)
let longest_path (next : int -> int list) ~(target : int) ~(from : int)
  : int option
  =
  let memo : (int, int option) Hashtbl.t = Hashtbl.create 64 in
  let rec go (v : int) : int option =
    if Int.equal v target
    then Some 0
    else (
      match Hashtbl.find_opt memo v with
      | Some r -> r
      | None ->
        let r : int option =
          List.fold_left
            (fun best w ->
              match go w, best with
              | None, b -> b
              | Some n, None -> Some (n + 1)
              | Some n, Some b -> Some (Stdlib.Int.max b (n + 1)))
            None
            (next v)
        in
        Hashtbl.replace memo v r;
        r)
  in
  go from
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

(** [node_line n] is the statement for the state [n]. Its style is named
    here, not given to [\graph] for all its nodes, as a label drawn as a node
    of the layout ({!picture}) must not inherit the look of a state. *)
let node_line (n : node) : string =
  let styles : string list =
    match n.initial, n.terminal with
    | false, false -> [ Draw_style.(use State) ]
    | _ ->
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

(** [label_style labels] is the style of the label of an arrow with [labels]:
    the silent one if they are all silent. *)
let label_style (labels : label list) : string =
  if List.for_all (fun l -> l = Silent) labels
  then Draw_style.(use Silent_label)
  else Draw_style.(use Label)
;;

(* See the [.mli]. *)
let picture ?(labels : labels = On_edge) (d : t) : string =
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
  let back : (int * int) list = back_arrows d in
  (* The arrows without the back ones are acyclic: [next u] are the states
     they lead [u] on to. *)
  let next (u : int) : int list =
    List.filter_map
      (fun (s, t, _) ->
        if Int.equal s u && not (List.mem (s, t) back) then Some t else None)
      arrows
  in
  (* A label that is a node of the layout, [e<k>], on the arrow's way: the
     layout then keeps room for it, and the arrow runs through it.

     An arrow back to a state it follows is laid out the other way round,
     from that state to this one: the layout would otherwise put its label
     next to the state the arrow leaves, as it only ever reverses the half
     that closes the cycle. Its arrowhead is then not the layout's to know
     (it would read it as the arrow's direction), so it is added to the first
     half as a decoration. Both halves span as many layers as the longest
     path the arrow closes has arrows, which is half of what that path
     spans, so the label sits half way along it, when it can. *)
  let on_edge_lines (k : int) ((s, t, ls) : int * int * label list)
    : string list
    =
    let node : string =
      Printf.sprintf
        "    e%i[as={%s}, %s];"
        k
        (String.concat "\\\\ " (List.map label_text ls))
        (label_style ls)
    in
    if List.mem (s, t) back
    then (
      let half : int =
        Stdlib.Int.max
          1
          (Stdlib.Option.value ~default:1 (longest_path next ~target:s ~from:t))
      in
      [ node
      ; Printf.sprintf
          "    s%i --[%s, -, %s, minimum layers=%i] e%i --[%s, -, minimum \
           layers=%i] s%i;"
          t
          (edge_options ls)
          Draw_style.back_tip
          half
          k
          (edge_options ls)
          half
          s
      ])
    else
      [ node
      ; Printf.sprintf
          "    s%i ->[%s, -] e%i ->[%s] s%i;"
          s
          (edge_options ls)
          k
          (edge_options ls)
          t
      ]
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
          "  \\graph[%s, edges={%s}]{"
          Draw_style.(use Layout)
          Draw_style.(use Edge)
      ]
      @ List.map node_line nodes
      @ (match labels with
         | Beside -> List.map arrow_line arrows
         | On_edge -> List.concat (List.mapi on_edge_lines arrows))
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
    ; "\\usetikzlibrary{graphs,graphdrawing,arrows.meta,quotes,automata,decorations.markings}"
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
