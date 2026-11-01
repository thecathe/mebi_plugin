(* See the [.mli]. *)

(* The program that shows a notification. It talks to whichever notification
   server the desktop session runs, over D-Bus; MeBi does not. *)
let program : string = "notify-send"

(* Seconds [program] is given before it is killed: it only hands the message
   to the server, so this is long past what it needs. *)
let timeout : float = 5.

(* Seconds a command must take to be announced; [None] while off. *)
let the_threshold : int option ref = ref None

(* How many [timed] calls are open. A command run from inside another is part
   of it, and only the outermost announces. *)
let depth : int ref = ref 0

(* Whether the warning that nothing could be sent has been given since the
   setting was last changed. Without it a missing [program] would warn after
   every command. *)
let warned : bool ref = ref false

(* See the [.mli]. *)
let threshold () : int option = !the_threshold

(* [find_exe cmd] is the first executable [cmd] on [PATH]. As
   [Draw_output.find_exe], repeated here rather than shared so that this
   library does not depend on the drawing one. *)
let find_exe (cmd : string) : string option =
  let dirs : string list =
    match Sys.getenv_opt "PATH" with
    | Some p -> String.split_on_char ':' p
    | None -> []
  in
  List.find_map
    (fun (d : string) ->
      let path : string = Filename.concat (if d = "" then "." else d) cmd in
      match Unix.access path [ Unix.X_OK ] with
      | () when not (Sys.is_directory path) -> Some path
      | () -> None
      | exception Unix.Unix_error _ -> None)
    dirs
;;

(* See the [.mli]. *)
let show_elapsed (secs : float) : string =
  let s : int = int_of_float (Float.max 0. secs) in
  if s < 60
  then Printf.sprintf "%is" s
  else if s < 3600
  then Printf.sprintf "%im %02is" (s / 60) (s mod 60)
  else Printf.sprintf "%ih %02im" (s / 3600) (s mod 3600 / 60)
;;

(* [send ~title ~body] is [Ok ()] once [program] has been run and exited 0, or
   [Error why]. No shell is involved, so the text cannot be read as anything but
   text. Its output goes nowhere; the reason a send failed is its exit status,
   not what it printed. Raises nothing. *)
let send ~(title : string) ~(body : string) : (unit, string) result =
  match find_exe program with
  | None -> Error (program ^ " is not on PATH")
  | Some exe ->
    (try
       let devnull : Unix.file_descr =
         Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0
       in
       Fun.protect
         ~finally:(fun () -> Unix.close devnull)
         (fun () ->
           let argv : string array =
             [| exe; "--app-name=MeBi"; "--"; title; body |]
           in
           let pid : int =
             Unix.create_process exe argv devnull devnull devnull
           in
           let deadline : float = Unix.gettimeofday () +. timeout in
           let rec wait () : (unit, string) result =
             match Unix.waitpid [ Unix.WNOHANG ] pid with
             | 0, _ ->
               if Unix.gettimeofday () >= deadline
               then (
                 (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
                 (try ignore (Unix.waitpid [] pid) with
                  | Unix.Unix_error _ -> ());
                 Error (program ^ " did not finish in time"))
               else (
                 Unix.sleepf 0.02;
                 wait ())
             | _, Unix.WEXITED 0 -> Ok ()
             | _, Unix.WEXITED n ->
               Error (Printf.sprintf "%s exited with status %i" program n)
             | _, (Unix.WSIGNALED _ | Unix.WSTOPPED _) ->
               Error (program ^ " was stopped by a signal")
           in
           wait ())
     with
     | Unix.Unix_error (e, _, _) -> Error (Unix.error_message e))
;;

(* What to do about the tool not being usable: a one-line note of what is
   wrong and how to stop being told. *)
let advice : string =
  "install notify-send (the libnotify package) and have a notification server \
   running, or turn this off with [MeBi Config Notify Off]"
;;

(* [announce ~command ~elapsed ~ok] sends the notification for a command that
   has ended, and warns, once, if it cannot. Raises nothing. *)
let announce ~(command : string) ~(elapsed : float) ~(ok : bool) : unit =
  let body : string =
    Printf.sprintf
      "%s %s after %s"
      command
      (if ok then "finished" else "ended with an error")
      (show_elapsed elapsed)
  in
  match send ~title:"MeBi" ~body with
  | Ok () -> ()
  | Error why ->
    if Bool.not !warned
    then (
      warned := true;
      Logger.warning
        (Printf.sprintf
           "(MeBi Notify: no notification was sent: %s. To get one, %s.)"
           why
           advice))
;;

(* See the [.mli]. *)
let timed ~(command : string) (f : unit -> 'a) : 'a =
  match !the_threshold with
  | None -> f ()
  | Some _ when !depth > 0 -> f ()
  | Some secs ->
    let started : float = Unix.gettimeofday () in
    incr depth;
    let finish (ok : bool) : unit =
      decr depth;
      let elapsed : float = Unix.gettimeofday () -. started in
      if elapsed >= float_of_int secs
      then (try announce ~command ~elapsed ~ok with _ -> ())
    in
    (match f () with
     | v ->
       finish true;
       v
     | exception e ->
       let bt : Printexc.raw_backtrace = Printexc.get_raw_backtrace () in
       finish false;
       Printexc.raise_with_backtrace e bt)
;;

(* See the [.mli]. *)
let set_after (secs : int) : unit =
  let secs : int = Int.max 0 secs in
  the_threshold := Some secs;
  warned := false;
  Logger.show
    (Printf.sprintf
       "(MeBi Config: Set Notify After to: %i seconds. A command that takes \
        that long ends with a desktop notification.)"
       secs);
  match find_exe program with
  | Some _ -> ()
  | None ->
    (* Said now, so a command that ends later does not say it again. *)
    warned := true;
    Logger.warning
      (Printf.sprintf
         "(MeBi Notify: %s is not on PATH, so none will be sent. To get one, \
          %s.)"
         program
         advice)
;;

(* See the [.mli]. *)
let set_off () : unit =
  the_threshold := None;
  warned := false;
  Logger.show "(MeBi Config: Set Notify to: Off.)"
;;

(* See the [.mli]. *)
let reset () : unit =
  the_threshold := None;
  warned := false
;;

(* See the [.mli]. *)
let test () : unit =
  match send ~title:"MeBi" ~body:"This is a test notification." with
  | Ok () -> Logger.show "(MeBi Notify: a test notification was sent.)"
  | Error why ->
    Logger.warning
      (Printf.sprintf
         "(MeBi Notify: the test notification was not sent: %s. To get one, \
          %s.)"
         why
         advice)
;;
