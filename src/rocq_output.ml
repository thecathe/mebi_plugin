(** Routes plugin output through Rocq.

    [lib/utils], [lib/terms] and [lib/model] are plain OCaml and link no Rocq
    runtime; they emit through [Logger], which by default prints to [stdout].
    This module is the Rocq half: it installs a sink that renders messages with
    [Pp] and hands them to [Feedback], plus a provider for the source location
    used to name dump files. Both are installed by [install ()], called once
    when the plugin loads.

    This is the layer the old [Output.Mode.Rocq] / [Output.Mode.OCaml] functor
    pair was expressing. The difference is that the choice is now made once at
    load time instead of being a functor parameter on every module in [lib/]. *)

(** Renders [__FUNCTION__], the optional prefix and the body into one [Pp.t],
    preserving the box structure the previous [Output.Mode.Rocq] used: the
    whole message is one string, so nothing in it can wrap. This is [Wrap Off].
*)
let render_block ({ fn; prefix; body; _ } : Output.message) : Pp.t =
  let open Pp in
  let a : Pp.t =
    (match fn with "" -> mt () | z -> str z ++ str ": ") |> v 0
  in
  let b : Pp.t =
    Option.cata (fun (p : string) -> str p) (mt ()) prefix |> v 0
  in
  let c : Pp.t = str body |> v 0 in
  seq [ v 0 (seq [ a; b ]); ws 0; c ] |> hv 0
;;

(** [header m] is [__FUNCTION__] and the prefix of [m], as the text that
    stands before its body. Raises nothing. *)
let header ({ fn; prefix; _ } : Output.message) : string =
  (match fn with "" -> "" | z -> z ^ ": ")
  ^ match prefix with None -> "" | Some p -> p
;;

(** [render_flow lines] is [lines] with a [Pp] box round each paragraph and a
    break point between its words, so that whatever prints the message picks
    where they fall: Rocq at its printing width, or a client that lays the
    boxes out itself. Each line is its own line; a {!Output.Wrap.Verbatim} one
    is one string. This is [Wrap Flow]. Raises nothing. *)
let render_flow (lines : Output.Wrap.line list) : Pp.t =
  let open Pp in
  let line : Output.Wrap.line -> Pp.t = function
    | Verbatim s -> str s
    | Para { indent; words } ->
      seq
        [ str (String.make indent ' '); hov 2 (prlist_with_sep spc str words) ]
  in
  v 0 (prlist_with_sep cut line lines)
;;

(** [render_hard width lines] is [lines] filled to [width] columns here
    ({!Output.Wrap.fill}), one string a line, so that it holds in a client
    that does not lay out boxes. This is [Wrap Width], [Wide] and [Slim].
    Raises nothing. *)
let render_hard (width : int) (lines : Output.Wrap.line list) : Pp.t =
  let open Pp in
  v 0 (prlist_with_sep cut str (Output.Wrap.fill ~width lines))
;;

(** [render_text s] is the text [s] as a [Pp.t], laid out as
    {!Output.Wrap.resolved} says: [Pp.str s] itself under [Wrap Off], else
    paragraphs of boxes or filled lines (as {!render}, with no header). For
    the plugin's text that does not go through {!Logger}: [MeBi Help],
    [MeBi Message] and the errors it raises. Raises nothing. *)
let render_text (s : string) : Pp.t =
  match Output.Wrap.resolved () with
  | No_wrap -> Pp.str s
  | Flowing -> render_flow (Output.Wrap.layout ~header:"" s)
  | Hard width -> render_hard width (Output.Wrap.layout ~header:"" s)
;;

(** Renders [m] as {!Output.Wrap.resolved} says: as one block, as boxes, or
    filled to a width. Raises nothing. *)
let render (m : Output.message) : Pp.t =
  match Output.Wrap.resolved () with
  | No_wrap -> render_block m
  | Flowing -> render_flow (Output.Wrap.layout ~header:(header m) m.body)
  | Hard width ->
    render_hard width (Output.Wrap.layout ~header:(header m) m.body)
;;

(* See the [.mli]. [Trace], [Result] and [Show] have no [Feedback] level
   of their own, so they map onto debug, info and notice. *)
let sink : Logger.sink =
  fun (m : Output.message) ->
  let doc : Pp.t = render m in
  match m.kind with
  | Debug | Trace -> Feedback.msg_debug doc
  | Info | Result -> Feedback.msg_info doc
  | Notice | Show -> Feedback.msg_notice doc
  | Warning -> Feedback.msg_warning ~quickfix:[] doc
  (* NOTE: as before, Error is reported via msg_debug rather than raising. *)
  | Error -> Feedback.msg_debug doc
;;

(* See the [.mli]. A command read from a file is named by its line and file.
   One read from the toplevel input has no file: that is every command under
   vsrocq, which parses with no location, and under [rocq repl]. Its [line_nb]
   cannot be trusted either (under vsrocq it was 2 to 3 lines short in a
   probe), so it is named by the logical path of the document being checked:
   under vsrocq that is the file's, as the loadpath maps it (its base
   name if nothing does), and [Top] under [rocq repl]. *)
let loc_provider () : string =
  match Loc.get_current_command_loc () with
  | Some { line_nb; fname = InFile { file; _ } } ->
    String.map (fun x -> if Char.equal '/' x then ' ' else x) file
    |> Printf.sprintf "line %i | %s" line_nb
  | Some { fname = ToplevelInput; _ } ->
    Names.DirPath.to_string (Lib.library_dp ())
  | None -> "Unknown Location"
;;

(** [ids dp] are the components of [dp], outermost first. Raises nothing. *)
let ids (dp : Names.DirPath.t) : string list =
  List.rev_map Names.Id.to_string (Names.DirPath.repr dp)
;;

(** [strip_prefix prefix l] is [l] without [prefix], if [l] starts with it.
    Raises nothing. *)
let rec strip_prefix (prefix : string list) (l : string list)
  : string list option
  =
  match prefix, l with
  | [], rest -> Some rest
  | p :: ps, x :: xs when String.equal p x -> strip_prefix ps xs
  | _ -> None
;;

(** [candidate_files dp] are the paths a document named [dp] may be saved at:
    for each load path binding whose logical path starts [dp], its physical
    path followed by the rest of [dp] with [.v] on the end, and then the
    document's base name in the working directory (a file no binding maps is
    named by its base name alone). Raises nothing. *)
let candidate_files (dp : Names.DirPath.t) : string list =
  let d : string list = ids dp in
  let mapped : string list =
    List.filter_map
      (fun (lp : Loadpath.t) ->
        match strip_prefix (ids (Loadpath.logical lp)) d with
        | Some (_ :: _ as rest) ->
          Some
            (List.fold_left Filename.concat (Loadpath.physical lp) rest ^ ".v")
        | _ -> None)
      (Loadpath.get_load_paths ())
  in
  mapped @ match List.rev d with base :: _ -> [ base ^ ".v" ] | [] -> []
;;

(** The saved files read so far, by path, with the modification time and size
    they had, so that a file is read again only once it changes. *)
let the_files : (string, (float * int) * string) Hashtbl.t = Hashtbl.create 4

(** [read_saved path] is the text of the regular file [path], or [None] if it
    cannot be read. Raises nothing. *)
let read_saved (path : string) : string option =
  match Unix.stat path with
  | exception Unix.Unix_error _ -> None
  | { st_kind = S_REG; st_mtime; st_size; _ } ->
    (match Hashtbl.find_opt the_files path with
     | Some (stamp, text) when stamp = (st_mtime, st_size) -> Some text
     | _ ->
       (match
          Stdlib.In_channel.with_open_bin path Stdlib.In_channel.input_all
        with
        | exception Sys_error _ -> None
        | text ->
          Hashtbl.replace the_files path ((st_mtime, st_size), text);
          Some text))
  | _ -> None
;;

(** [document_line ~bp ~ep] is the true line of the command at the byte
    offsets [bp] to [ep] of the document being checked, counted in its saved
    file ({!candidate_files}), if that file is there and has a command (the
    text [MeBi]) at that place. Under vsrocq the offsets are exact while
    [Loc.line_nb] is not (it was 54 lines short on one example, 3 on
    another), but vsrocq checks the editor's buffer, which may differ from the
    saved file: an unsaved edit above the command moves it, and the check fails
    rather than name a wrong line. Raises nothing. *)
let document_line ~(bp : int) ~(ep : int) : int option =
  let rec first : string list -> int option = function
    | [] -> None
    | path :: rest ->
      (match read_saved path with
       | Some text
         when 0 <= bp
              && bp <= ep
              && ep <= String.length text
              && Utils.contains ~sub:"MeBi" (String.sub text bp (ep - bp)) ->
         Utils.line_of_offset text bp
       | _ -> first rest)
  in
  first (candidate_files (Lib.library_dp ()))
;;

(* See the [.mli]. *)
let origin_location () : string =
  match Loc.get_current_command_loc () with
  | Some { fname = InFile { file; _ }; line_nb; _ } ->
    Printf.sprintf "%s, line %i" file line_nb
  | Some { fname = ToplevelInput; line_nb; bp; ep; _ } ->
    let name : string = Names.DirPath.to_string (Lib.library_dp ()) in
    (match document_line ~bp ~ep with
     | Some n -> Printf.sprintf "%s, line %i" name n
     | None when String.equal name "Top" ->
       (* [rocq repl]: no document, and its [line_nb] is right *)
       Printf.sprintf "line %i" line_nb
     | None -> Printf.sprintf "%s (line unknown)" name)
  | None -> "unknown location"
;;

(* See the [.mli]. *)
let install () : unit =
  Logger.set_sink sink;
  Utils.FileWriter.set_loc_provider loc_provider
;;

(* Installed on module initialisation, i.e. when Rocq loads the plugin via
   `Declare ML Module`. Nothing else needs to call `install`. *)
let () = install ()
