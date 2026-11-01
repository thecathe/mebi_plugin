(** A desktop notification when a long-running MeBi command ends: opt-in, off
    by default, and optional in every other respect.

    Nothing here is needed for MeBi to work. The notification is sent by
    running [notify-send] (the [libnotify] package) if it is on [PATH]; where
    it is not, or there is no notification server to receive it, the command
    still finishes as it would have, with one warning per session. No program
    is run while the setting is off.

    This library has no Rocq dependency ([Wrapper.Command.run] and
    [Proof_solver.guard], in [src/], are where the plugin hands it a command),
    so it is exercised by [test/tests.exe]. It does not depend on [lib/draw]. *)

(** {2 Settings}

    [MeBi Config Notify ...]. *)

(** [set_after secs] turns notifications on for any command that takes [secs]
    seconds or longer (negative is read as 0, which announces every command),
    and says so. Warns at once if [notify-send] is not on [PATH], since none
    will be sent. Raises nothing. *)
val set_after : int -> unit

(** [set_off ()] turns notifications off, and says so. Raises nothing. *)
val set_off : unit -> unit

(** [reset ()] is the default: off. Silent, as the other [Reset]s are. Raises
    nothing. *)
val reset : unit -> unit

(** [threshold ()] is the number of seconds a command must take to be
    announced, [None] while notifications are off. Raises nothing. *)
val threshold : unit -> int option

(** [test ()] sends a notification now, whatever the setting, and says whether
    it went: the way to find out before a demonstration that the tool and the
    notification server are there. Raises nothing. *)
val test : unit -> unit

(** {2 Announcing a command} *)

(** [timed ~command f] is [f ()]. If notifications are on and [f] took at least
    the threshold, it then sends one saying so, whether [f] returned or raised
    (an exception is re-raised unchanged, with its backtrace). [command] names
    the command in the message ([Run Bisim]).

    Only the outermost call counts: a command run from inside another (a
    [Sim Begin] checks bisimilarity with the same code [Run Bisim] runs) is
    part of it and does not announce itself. Nothing it does can fail the
    command: a notification that cannot be sent is a warning, once.

    @raise e whatever [f] raises (propagated). *)
val timed : command:string -> (unit -> 'a) -> 'a

(** [show_elapsed secs] is a duration for a message: [45s], [3m 07s],
    [1h 02m] (whole seconds, rounded down). Raises nothing. *)
val show_elapsed : float -> string
