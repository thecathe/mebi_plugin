(** A soft cap on the plugin's memory ([MeBi Config Bounds Memory]).

    The plugin's memory-heavy loops (extraction, saturation, the up-front
    game walks and estimates, the proof solver's steps) call {!check} once
    per unit of work. With a limit set, {!check} reads the process's memory
    at most every {!interval} seconds and raises {!Exceeded} once it is over
    the limit, so the command fails with a message instead of the process
    being killed. On by default ({!default}). Unset, and with no command
    tracked ({!start_tracking}), {!check} reads two references and does nothing
    else.

    The cap is soft: memory is read between units of work, so one unit can
    overshoot it, and [Qed] (Rocq's kernel) is never checked. It is a
    mitigation, not a replacement for an OS-level cap. Contains no reference
    to the Rocq API. *)

(** [Exceeded { phase; used; limit }]: the process used [used] bytes,
    over [limit], when [phase] checked. *)
exception
  Exceeded of
    { phase : string
    ; used : int
    ; limit : int
    }

(** The default limit in bytes, and how it was computed: 75% of the
    machine's RAM ([MemTotal] in [/proc/meminfo]), or 90% of the
    process's cgroup memory cap ([memory.max], as [systemd-run -p MemoryMax=...] sets) if that is smaller. An explicit cap is chosen for
    this one process, so it keeps less headroom than RAM, which is shared.
    [None] where neither can be read (not Linux). Computed once, at load. *)
val default : (int * string) option

(** The limit in bytes, or [None] for no limit. Starts at {!default}. *)
val limit : int option ref

(** [set_limit x] sets {!limit} to [x], and makes the next {!check} read
    memory whatever the time since the last read. Raises nothing. *)
val set_limit : int option -> unit

(** [reset ()] restores {!default}, as {!set_limit}. Raises nothing. *)
val reset : unit -> unit

(** [describe ()] is {!limit} in MB, saying so if it is the default, or
    ["none"]. Raises nothing. *)
val describe : unit -> string

(** [over_bound bytes] is a sentence saying that [bytes] is over {!limit},
    for an error or notice estimating that much memory; [None] if it is
    not, or no limit is set. Raises nothing. *)
val over_bound : int -> string option

(** The least time in seconds between two reads of memory by {!check}. *)
val interval : float

(** [used ()] is the process's memory in bytes: its resident set and swap
    ([VmRSS] and [VmSwap] in [/proc/self/status]) on Linux, otherwise the
    size of the OCaml major heap. [None] if neither can be read. Raises
    nothing. *)
val used : unit -> int option

(** [check phase] checks {!used} against {!limit}, if one is set and
    either {!interval} has passed since the last read or that read was
    over the limit. Over it, it compacts the heap (once after each raise)
    and reads again before raising.

    @raise Exceeded if memory is over the limit (raised here). *)
val check : string -> unit

(** [message phase used limit] is the message for {!Exceeded}, with a
    hint for [phase]. Raises nothing. *)
val message : string -> int -> int -> string

(** {2 What one command used}

    [MeBi Config Notify] reports the memory a long command reached against the
    bound. It is the highest value {!check} read while the command ran, so it
    sees what the bound sees: the plugin's own loops, every {!interval}
    seconds, and not Rocq's kernel in [Qed]. The kernel's own peak counter
    ([VmHWM]) is not used: resetting it per command also erases the peak the
    operating system reports when the process exits (measured 2026-11-02: a
    process that peaked at 420MB exited reporting 12MB), which would corrupt
    the memory figures of [bench/]. *)

(** What a tracked command used. All of memory is the process's, not the
    command's: the bytes in use when it began are what earlier commands left
    (OCaml keeps memory it has freed), so [peak - start] is how far the process
    grew, a lower bound on what the command needed. *)
type report =
  { start : int (** bytes in use when tracking began *)
  ; peak : int
    (** the most {!check} read since, and at the end; at least [start] *)
  ; limit : int option (** the bound in bytes, [None] if there was none *)
  ; stopped_in : string option
    (** [Some phase] if {!Exceeded} was raised during [phase] while tracking *)
  }

(** [start_tracking ()] starts recording the memory read by {!check}, which
    then reads even with no limit set. Not nestable: the caller keeps count.
    Raises nothing. *)
val start_tracking : unit -> unit

(** [stop_tracking ()] stops recording and reports. It reads memory once more,
    so a command that ended between two checks is not under-counted. [None] if
    memory cannot be read (see {!used}). Raises nothing. *)
val stop_tracking : unit -> report option
