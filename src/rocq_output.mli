(** Routes plugin output through Rocq.

    [lib/utils], [lib/terms] and [lib/model] link no Rocq runtime and emit
    through {!Logger}, which prints to [stdout] by default. This module installs
    the Rocq half: a sink rendering messages with [Pp] onto [Feedback], and the
    source-location provider used to name dump files.

    {!install} runs on module initialisation, so nothing normally needs to call
    it; [g_mebi.mlg] calls it explicitly to make the dependency visible. *)

(** [sink m] prints the message [m] through Rocq's [Feedback], at the level
    of its kind ([Trace] as debug, [Result] as info, [Show] as notice,
    [Error] as debug: it does not raise). Raises nothing. *)
val sink : Logger.sink

(** [loc_provider ()] names where the command now running is, to name dump
    files by: ["line N | file"] for a command read from a file, else (a
    command typed or sent from an editor, which has no file or reliable line)
    the logical path of the document, such as [MEBI.Examples.CoffeeMachine]
    (just the file's base name if no loadpath entry maps it; [Top] in
    [rocq repl]). Raises nothing. *)
val loc_provider : unit -> string

(** [render_text s] is the text [s] as a [Pp.t], laid out as the wrapping mode
    says ([MeBi Config Output Wrap]): [Pp.str s] itself when it is [Off]; else
    paragraphs as boxes ([Flow]) or filled to a width. For text that does not
    go through {!Logger}: [MeBi Help], [MeBi Message], [Debug] and [Divider],
    and the errors the plugin raises. Raises nothing. *)
val render_text : string -> Pp.t

(** [origin_location ()] says where the command now running is, for the
    [origin:] header of a printed result and the ["location"] of a JSON one:
    ["file, line N"] for a command read from a file; for one from an editor
    (which has no file), ["Logical.path, line N"] with the {i true} line, counted
    from the exact character offset vsrocq gives (its [line_nb] is not
    reliable) in the document's saved file, found through the load path; or
    ["Logical.path (line unknown)"] when that file is missing or no longer
    matches (an unsaved edit). In [rocq repl] (path [Top], no file) it is
    ["line N"]. Raises nothing. *)
val origin_location : unit -> string

(** [install ()] makes {!Logger} print through {!sink} and name dumps with
    {!loc_provider}. Raises nothing. *)
val install : unit -> unit
