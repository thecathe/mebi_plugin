(** The kinds of message the plugin can emit, and nothing else.

    This module deliberately contains no reference to the Rocq API. Routing a
    message to Rocq's [Feedback] is the job of a {i sink} installed at plugin
    load (see [Logger.set_sink] and [Mebi_plugin.Rocq_output]); when no sink is
    installed, [Logger] prints to [stdout]. That is what lets [lib/utils],
    [lib/terms] and [lib/model] build and be tested as plain OCaml libraries. *)

module Kind = struct
  (** [Debug] .. [Error] mirror Rocq's [Feedback.level]; [Trace], [Result] and
      [Show] are extensions of this plugin. The distinction only matters to a
      sink, so unlike previous versions this type is not split into
      [level]/[special]. *)
  type t =
    | Debug
    | Info
    | Notice
    | Warning
    | Error
    | Trace
    | Result
    | Show

  (* See the [.mli] for these. *)
  let all : t list =
    [ Debug; Info; Notice; Warning; Error; Trace; Result; Show ]
  ;;

  let to_string : t -> string = function
    | Debug -> "Debug"
    | Info -> "Info"
    | Notice -> "Notice"
    | Warning -> "Warning"
    | Error -> "Error"
    | Trace -> "Trace"
    | Result -> "Result"
    | Show -> "Show"
  ;;

  let of_string : string -> t option = function
    | "Debug" -> Some Debug
    | "Info" -> Some Info
    | "Notice" -> Some Notice
    | "Warning" -> Some Warning
    | "Error" -> Some Error
    | "Trace" -> Some Trace
    | "Result" -> Some Result
    | "Show" -> Some Show
    | _ -> None
  ;;

  (* See the [.mli]. Matches the previous [Output.default_level_fun] /
     [default_special_fun] defaults. *)
  let default : t -> bool = function
    | Debug -> false
    | Trace -> false
    | Result -> false
    | Info | Notice | Warning | Error | Show -> true
  ;;
end

(** One message, kept in parts rather than pre-composed into a string, so that
    a sink able to lay text out properly (Rocq's [Pp]) still can. *)
type message =
  { kind : Kind.t
  ; fn : string (** [__FUNCTION__] of the emitting site, or [""]. *)
  ; prefix : string option
    (** Printed just before [body], separator included (as ["p: "]). *)
  ; body : string
  }

module Wrap = struct
  type preset =
    | Wide
    | Slim

  type mode =
    | Off
    | Flow
    | Width of int
    | Preset of preset

  type resolved =
    | No_wrap
    | Flowing
    | Hard of int

  (* See the [.mli] for everything in this module. *)
  let min_width : int = 20
  let default_width : preset -> int = function Wide -> 120 | Slim -> 60
  let valid (n : int) : bool = n >= min_width

  (** [check n] is [()] if [n] is {!valid}. Raises [Invalid_argument]
      otherwise. *)
  let check (n : int) : unit =
    if Bool.not (valid n)
    then
      invalid_arg
        (Printf.sprintf
           "Output.Wrap: a width is at least %i columns, not %i"
           min_width
           n)
  ;;

  let the_mode : mode ref = ref Off
  let the_wide : int ref = ref (default_width Wide)
  let the_slim : int ref = ref (default_width Slim)
  let mode () : mode = !the_mode

  let set_mode (m : mode) : unit =
    (match m with Width n -> check n | Off | Flow | Preset _ -> ());
    the_mode := m
  ;;

  let preset_width : preset -> int = function
    | Wide -> !the_wide
    | Slim -> !the_slim
  ;;

  let set_preset_width (p : preset) (n : int) : unit =
    check n;
    match p with Wide -> the_wide := n | Slim -> the_slim := n
  ;;

  let reset () : unit =
    the_mode := Off;
    the_wide := default_width Wide;
    the_slim := default_width Slim
  ;;

  let resolved () : resolved =
    match !the_mode with
    | Off -> No_wrap
    | Flow -> Flowing
    | Width n -> Hard n
    | Preset p -> Hard (preset_width p)
  ;;

  type line =
    | Verbatim of string
    | Para of
        { indent : int
        ; words : string list
        }

  (* A UTF-8 continuation byte is [10xxxxxx]; every other byte starts a
     character. *)
  let text_width (s : string) : int =
    String.fold_left
      (fun n c -> if Char.code c land 0xC0 = 0x80 then n else n + 1)
      0
      s
  ;;

  (** [leading_spaces s] is the number of spaces [s] starts with. Raises
      nothing. *)
  let leading_spaces (s : string) : int =
    let n : int = String.length s in
    let rec go (i : int) : int =
      if i < n && s.[i] = ' ' then go (i + 1) else i
    in
    go 0
  ;;

  (** [has_columns s] is whether [s] has a run of two spaces or a tab in it:
      the mark of aligned columns, which re-flowing would ruin. Raises
      nothing. *)
  let has_columns (s : string) : bool =
    let n : int = String.length s in
    let rec go (i : int) : bool =
      i < n
      && (s.[i] = '\t'
          || (s.[i] = ' ' && i + 1 < n && s.[i + 1] = ' ')
          || go (i + 1))
    in
    go 0
  ;;

  (** [is_rule s] is whether [s] is only dashes, equals signs, underscores,
      asterisks and spaces: a divider, which re-flowing would only break.
      Raises nothing. *)
  let is_rule (s : string) : bool =
    String.for_all
      (fun c -> c = '-' || c = '=' || c = '_' || c = '*' || c = ' ')
      s
  ;;

  (** [rstrip s] is [s] without trailing spaces, tabs and carriage returns.
      Raises nothing. *)
  let rstrip (s : string) : string =
    let rec go (i : int) : int =
      if i > 0 && (s.[i - 1] = ' ' || s.[i - 1] = '\t' || s.[i - 1] = '\r')
      then go (i - 1)
      else i
    in
    String.sub s 0 (go (String.length s))
  ;;

  (** [classify l] is the line [l] (no newline in it), as {!line}. Raises
      nothing. *)
  let classify (l : string) : line =
    let l : string = rstrip l in
    let indent : int = leading_spaces l in
    if indent >= String.length l
    then Verbatim ""
    else (
      let rest : string = String.sub l indent (String.length l - indent) in
      match rest.[0] with
      | '{' | '}' | '[' | ']' | '"' -> Verbatim l
      | _ when is_rule rest -> Verbatim l
      | _ when has_columns rest -> Verbatim l
      | _ ->
        Para
          { indent
          ; words =
              List.filter (fun w -> w <> "") (String.split_on_char ' ' rest)
          })
  ;;

  (** [drop_trailing_blanks ls] is [ls] without the blank lines at its end.
      Raises nothing. *)
  let drop_trailing_blanks (ls : line list) : line list =
    let rec go : line list -> line list = function
      | Verbatim "" :: tl -> go tl
      | ls -> ls
    in
    List.rev (go (List.rev ls))
  ;;

  let layout ~(header : string) (body : string) : line list =
    let lines : line list =
      String.split_on_char '\n' body
      |> List.map classify
      |> drop_trailing_blanks
    in
    match classify header, lines with
    | Verbatim "", ls -> ls
    | Para h, [ Para { indent = 0; words } ] ->
      [ Para { indent = 0; words = h.words @ words } ]
    | h, ls -> h :: ls
  ;;

  (** [fill_words ~width ~indent words] is the paragraph [words], the first
      line indented [indent] and the rest 2 further (at most half of
      [width]), as lines at most [width] characters long, except where a word
      is longer. Raises nothing. *)
  let fill_words ~(width : int) ~(indent : int) (words : string list)
    : string list
    =
    let hang : string = String.make (min (indent + 2) (width / 2)) ' ' in
    let rec go (cur : string) (acc : string list) : string list -> string list
      = function
      | [] -> List.rev (cur :: acc)
      | w :: tl ->
        if text_width cur + 1 + text_width w <= width
        then go (cur ^ " " ^ w) acc tl
        else go (hang ^ w) (cur :: acc) tl
    in
    match words with
    | [] -> [ "" ]
    | w :: tl -> go (String.make indent ' ' ^ w) [] tl
  ;;

  let fill ~(width : int) (lines : line list) : string list =
    List.concat_map
      (function
        | Verbatim s -> [ s ]
        | Para { indent; words } -> fill_words ~width ~indent words)
      lines
  ;;
end
