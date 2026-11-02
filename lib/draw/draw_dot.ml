(** xcolor's base colours, as red, green and blue out of 255 ([\definecolor]
    of xcolor: [orange] is half green, [teal] is [0,0.5,0.5], and so on). *)
let base_colours : (string * (int * int * int)) list =
  [ "red", (255, 0, 0)
  ; "green", (0, 255, 0)
  ; "blue", (0, 0, 255)
  ; "cyan", (0, 255, 255)
  ; "magenta", (255, 0, 255)
  ; "yellow", (255, 255, 0)
  ; "black", (0, 0, 0)
  ; "white", (255, 255, 255)
  ; "gray", (128, 128, 128)
  ; "darkgray", (64, 64, 64)
  ; "lightgray", (191, 191, 191)
  ; "brown", (191, 128, 64)
  ; "lime", (191, 255, 0)
  ; "olive", (128, 128, 0)
  ; "orange", (255, 128, 0)
  ; "pink", (255, 191, 191)
  ; "purple", (191, 0, 64)
  ; "teal", (0, 128, 128)
  ; "violet", (128, 0, 128)
  ]
;;

(** [mix p (r1, g1, b1) (r2, g2, b2)] is [p]% of the first and the rest of the
    second, as xcolor's [a!p!b]. *)
let mix
      (p : int)
      ((r1, g1, b1) : int * int * int)
      ((r2, g2, b2) : int * int * int)
  : int * int * int
  =
  let f (a : int) (b : int) : int =
    Stdlib.Float.to_int
      (Stdlib.Float.round
         (((Stdlib.Float.of_int p *. Stdlib.Float.of_int a)
           +. (Stdlib.Float.of_int (100 - p) *. Stdlib.Float.of_int b))
          /. 100.))
  in
  f r1 r2, f g1 g2, f b1 b2
;;

(* See the [.mli]. *)
let colour (c : string) : string =
  let c : string = String.trim c in
  let hex ((r, g, b) : int * int * int) : string =
    Printf.sprintf "#%02x%02x%02x" r g b
  in
  (* [a!p!b!q] is [(a!p!b)!q!white]: each mix is of what came before *)
  let rec go (acc : int * int * int) : string list -> (int * int * int) option
    = function
    | [] -> Some acc
    | p :: rest ->
      (match int_of_string_opt p with
       | Some p when p >= 0 && p <= 100 ->
         (match rest with
          | n :: rest' when Stdlib.Option.is_none (int_of_string_opt n) ->
            (match List.assoc_opt n base_colours with
             | Some rgb -> go (mix p acc rgb) rest'
             | None -> None)
          | _ -> go (mix p acc (255, 255, 255)) rest)
       | _ -> None)
  in
  match String.split_on_char '!' c with
  | first :: rest when not (String.starts_with ~prefix:"#" c) ->
    (match List.assoc_opt first base_colours with
     | None -> c
     | Some rgb -> Stdlib.Option.fold ~none:c ~some:hex (go rgb rest))
  | _ -> c
;;

(* See the [.mli]. *)
let q (s : string) : string =
  let b : Buffer.t = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' | '\t' -> Buffer.add_char b ' '
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b
;;

(* See the [.mli]. *)
let html (s : string) : string =
  let b : Buffer.t = Buffer.create (String.length s + 8) in
  String.iter
    (function
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | '\n' | '\r' | '\t' -> Buffer.add_char b ' '
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b
;;

(** The fonts TeX's [$\tau$] is drawn in: Latin Modern Math is Computer Modern's
    math italic, so the same letter, and the others are the nearest to it, for
    a machine without it (Graphviz tries them in turn, and then any font with
    the letter). *)
let tau_fonts : string = "Latin Modern Math, STIX Two Math, Asana Math"

(** A silent step: TeX's [\boldmath$\tau$], the mathematical bold italic small
    tau (U+1D749, so it needs neither [<B>] nor [<I>]) in {!tau_fonts}. *)
let tau : string = "<FONT FACE=\"" ^ tau_fonts ^ "\">\u{1d749}</FONT>"

(** [label_markup ls] is the labels [ls] as the text of an HTML-like label, one
    to a line, the lines apart by [<BR/>]. A line break inside a label is a
    space. *)
let label_markup (ls : Draw.label list) : string =
  String.concat
    "<BR/>"
    (List.map (function Draw.Silent -> tau | Draw.Label s -> html s) ls)
;;

(** [label_value ls] is the value of the [label] attribute for the labels [ls],
    one to a line. A silent step is a bold italic tau in a math font, which a
    plain string cannot be: so when one is among them the value is an
    HTML-like label, [<...>] ({!label_markup}); otherwise it is a plain quoted
    string. *)
let label_value (ls : Draw.label list) : string =
  let clean (s : string) : string =
    String.map (function '\n' | '\r' | '\t' -> ' ' | c -> c) s
  in
  if List.exists (fun l -> l = Draw.Silent) ls
  then "<" ^ label_markup ls ^ ">"
  else
    q
      (String.concat
         "\n"
         (List.map (function Draw.Silent -> "" | Draw.Label s -> clean s) ls))
;;

(* See the [.mli]. *)
let dot
      ?(labels : Draw.labels = Draw.On_edge)
      ?(direction : Draw_style.direction = Draw_style.Down)
      ?(style : Draw_style.t = Draw_style.empty)
      (d : Draw.t)
  : string
  =
  let rankdir, into, outof =
    match direction with
    | Draw_style.Down -> "TB", "n", "s"
    | Draw_style.Right -> "LR", "w", "e"
  in
  let nodes : Draw.node list =
    List.sort (fun (a : Draw.node) b -> Int.compare a.id b.id) d.nodes
  in
  let arrows : (int * int * Draw.label list) list = Draw.merge d.edges in
  let spans : ((int * int) * int) list = Draw.back_spans d in
  let attrs (l : string list) : string =
    String.concat ", " (List.filter (fun a -> not (String.equal a "")) l)
  in
  let silent (ls : Draw.label list) : bool =
    List.for_all (fun l -> l = Draw.Silent) ls
  in
  (* The colour of an arrow, and its label's: a silent step is grey, and
     nothing else is coloured unless its kind has a colour. *)
  let colour_of (ls : Draw.label list) : string option =
    if silent ls
    then Some "gray50"
    else
      Stdlib.Option.bind (Draw.coloured_kind style ls) (fun k ->
        Stdlib.Option.map colour (Draw_style.kind_colour k style))
  in
  let edge_attrs (ls : Draw.label list) : string list =
    (match colour_of ls with
     | Some c -> [ "color=" ^ q c; "fontcolor=" ^ q c ]
     | None -> [])
    @ if silent ls then [ "style=dashed" ] else []
  in
  let lines : string list ref = ref [] in
  let add (l : string) : unit = lines := l :: !lines in
  add "digraph G {";
  add
    (Printf.sprintf
       "  graph [rankdir=%s, nodesep=0.3, ranksep=0.25, splines=true];"
       rankdir);
  add
    "  node [shape=box, style=\"rounded,filled\", fillcolor=white, \
     fontsize=11, margin=\"0.12,0.06\", height=0, width=0];";
  add "  edge [fontsize=10, penwidth=1.4, arrowsize=0.8];";
  List.iter
    (fun (n : Draw.node) ->
      add
        (Printf.sprintf
           "  s%i [%s];"
           n.id
           (attrs
              [ "label=" ^ q n.text
              ; (if n.initial then "penwidth=2.5" else "")
              ; (if n.terminal then "peripheries=2" else "")
              ])))
    nodes;
  (match List.find_opt (fun (n : Draw.node) -> n.initial) nodes with
   | Some n ->
     add "  start [shape=point, width=0.08, label=\"\"];";
     add (Printf.sprintf "  start -> s%i [arrowsize=0.8];" n.id)
   | None -> ());
  let k : int ref = ref 0 in
  List.iter
    (fun (s, t, ls) ->
      let ea : string list = edge_attrs ls in
      let tail (l : string list) : string =
        String.concat "" (List.map (fun a -> ", " ^ a) l)
      in
      if Int.equal s t || labels = Draw.Beside
      then
        add
          (Printf.sprintf
             "  s%i -> s%i [label=%s%s];"
             s
             t
             (label_value ls)
             (tail ea))
      else (
        incr k;
        let l : int = !k in
        let outline : bool =
          Draw_style.outline style
          && (not (silent ls))
          && Stdlib.Option.is_some (colour_of ls)
        in
        add
          (Printf.sprintf
             "  l%i [%s];"
             l
             (attrs
                ((if outline
                  then
                    [ "shape=box"
                    ; "style=\"rounded,filled\""
                    ; "fillcolor=white"
                    ; "penwidth=0.6"
                    ; "color="
                      ^ q (Stdlib.Option.value (colour_of ls) ~default:"black")
                    ]
                  else
                    [ "shape=box"
                    ; "style=filled"
                    ; "fillcolor=white"
                    ; "penwidth=0"
                    ])
                 @ [ "margin=\"0.05,0.03\""; "label=" ^ label_value ls ]
                 @ (match colour_of ls with
                    | Some c -> [ "fontcolor=" ^ q c ]
                    | None -> [])
                 @ if silent ls then [ "fontsize=14" ] else [])));
        match List.assoc_opt (s, t) spans with
        | Some half ->
          (* laid out target to source, its head at the target *)
          add
            (Printf.sprintf
               "  s%i -> l%i [dir=back, arrowtail=normal, arrowhead=none, \
                minlen=%i, headport=%s%s];"
               t
               l
               half
               into
               (tail ea));
          add
            (Printf.sprintf
               "  l%i -> s%i [arrowhead=none, minlen=%i, tailport=%s%s];"
               l
               s
               half
               outof
               (tail ea))
        | None ->
          add
            (Printf.sprintf
               "  s%i -> l%i [arrowhead=none, weight=8, headport=%s%s];"
               s
               l
               into
               (tail ea));
          add
            (Printf.sprintf
               "  l%i -> s%i [weight=8, tailport=%s%s];"
               l
               t
               outof
               (tail ea))))
    arrows;
  if d.incomplete || List.is_empty nodes
  then
    add
      (Printf.sprintf
         "  label=%s; labelloc=b; fontsize=10;"
         (q
            (if List.is_empty nodes
             then "Empty: no states."
             else "Incomplete: some states or transitions may be missing.")));
  add "}";
  String.concat "\n" (List.rev !lines) ^ "\n"
;;
