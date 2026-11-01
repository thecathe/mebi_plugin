(** The kinds of message the plugin can emit. Contains no reference to the Rocq
    API — see {!Logger.set_sink} for how messages reach Rocq's [Feedback]. *)

module Kind : sig
  (** [Debug] .. [Error] mirror Rocq's [Feedback.level]; [Trace], [Result]
      and [Show] are the plugin's own. *)
  type t =
    | Debug
    | Info
    | Notice
    | Warning
    | Error
    | Trace
    | Result
    | Show

  (** Every kind. *)
  val all : t list

  (** [to_string k] is [k]'s constructor name ([Debug] is ["Debug"]).
      Raises nothing. *)
  val to_string : t -> string

  (** [of_string s] is the kind named [s] ({!to_string}), or [None]. Raises
      nothing. *)
  val of_string : string -> t option

  (** [default k] is whether [k] is emitted when nothing has configured it:
      all but [Debug], [Trace] and [Result]. Raises nothing. *)
  val default : t -> bool
end

(** One message, kept in parts rather than pre-composed, so a sink that can lay
    text out properly (Rocq's [Pp]) still has the pieces to do so. *)
type message =
  { kind : Kind.t
  ; fn : string (** [__FUNCTION__] of the emitting site, or [""]. *)
  ; prefix : string option
    (** Printed just before [body], separator included (as ["p: "]). *)
  ; body : string
  }

(** Fitting a message to a width ([MeBi Config Output Wrap]).

    The work of deciding what may be re-flowed and filling it to a width is
    here, as plain strings, so that it is testable without Rocq;
    {!Mebi_plugin.Rocq_output} turns the result into [Pp]. *)
module Wrap : sig
  (** A named width the user can set ([MeBi Config Output Width Wide n]):
      shorthands for [Width n]. *)
  type preset =
    | Wide
    | Slim

  (** How messages are wrapped.
      - [Off]: not at all, as a single block (the default).
      - [Flow]: as paragraphs of [Pp] boxes with break points, so whatever
        shows the message picks the width. Rocq's own printing width applies
        where it renders to text (78, or [Set Printing Width]); a client
        that renders the boxes itself can follow its viewport.
      - [Width n]: filled to [n] columns here, so it holds in every client.
      - [Preset p]: [Width] of what [p] is set to now. *)
  type mode =
    | Off
    | Flow
    | Width of int
    | Preset of preset

  (** [mode], with a preset replaced by its width. *)
  type resolved =
    | No_wrap
    | Flowing
    | Hard of int

  (** The narrowest width accepted: 20. Narrower leaves no room for a word
      beside a hanging indent. *)
  val min_width : int

  (** What {!preset_width} is until set: 120 for [Wide], 60 for [Slim]. *)
  val default_width : preset -> int

  (** [valid n] is whether [n] is at least {!min_width}. Raises nothing. *)
  val valid : int -> bool

  (** [mode ()] is the mode now in force: [Off] until set. Raises nothing. *)
  val mode : unit -> mode

  (** [set_mode m] makes [m] the mode.

      @raise Invalid_argument if [m] is [Width n] with [n] not {!valid}. *)
  val set_mode : mode -> unit

  (** [preset_width p] is what [p] is set to now. Raises nothing. *)
  val preset_width : preset -> int

  (** [set_preset_width p n] makes [p] stand for [n] columns, and leaves the
      mode as it is.

      @raise Invalid_argument if [n] is not {!valid}. *)
  val set_preset_width : preset -> int -> unit

  (** [reset ()] makes the mode [Off] and both presets their defaults. Raises
      nothing. *)
  val reset : unit -> unit

  (** [resolved ()] is {!mode} with the preset looked up. Raises nothing. *)
  val resolved : unit -> resolved

  (** One line of a message, as far as wrapping is concerned. *)
  type line =
    | Verbatim of string
    (** kept exactly: a blank line, a row of aligned columns (a run of two
        or more spaces, or a tab, after the indent), or a line of JSON
        (starting with a brace, a square bracket or a double quote) *)
    | Para of
        { indent : int
        ; words : string list
        } (** prose: free to break between words *)

  (** [layout ~header body] is the lines of a message: [body]'s, each
      classified, with trailing blank lines dropped and [header] (the
      function and prefix, which may be [""]) before them. A body of a single
      paragraph is joined to the header on one line; otherwise the header
      is a line of its own. Raises nothing. *)
  val layout : header:string -> string -> line list

  (** [text_width s] is the number of characters in [s], counting a UTF-8
      sequence as one (not the bytes, nor the display width of wide
      glyphs). Raises nothing. *)
  val text_width : string -> int

  (** [fill ~width lines] is [lines] as lines of text at most [width]
      characters long, as far as possible: a paragraph is filled greedily,
      its continuation lines indented 2 further than its first (at most half
      the width); a word longer than the room, and a {!Verbatim} line, go
      over rather than be cut. Raises nothing. *)
  val fill : width:int -> line list -> string list
end
