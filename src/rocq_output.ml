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

(* See the [.mli]. *)
let install () : unit =
  Logger.set_sink sink;
  Utils.FileWriter.set_loc_provider loc_provider
;;

(* Installed on module initialisation, i.e. when Rocq loads the plugin via
   `Declare ML Module`. Nothing else needs to call `install`. *)
let () = install ()
