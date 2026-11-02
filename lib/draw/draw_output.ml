(* See the [.mli]. *)
type format =
  | Tex
  | Pdf
  | Png

(* See the [.mli]. *)
let format_name : format -> string = function
  | Tex -> "TeX"
  | Pdf -> "PDF"
  | Png -> "PNG"
;;

(* See the [.mli]. *)
let format_of_string (s : string) : format option =
  let lower : string = String.lowercase_ascii s in
  List.find_opt
    (fun f -> String.equal (String.lowercase_ascii (format_name f)) lower)
    [ Tex; Pdf; Png ]
;;

(* See the [.mli]. *)
type problem =
  | Missing_tool of
      { tools : string list
      ; needed_for : string
      }
  | Failed of
      { tool : string
      ; detail : string
      ; log : string option
      }
  | Timed_out of
      { tool : string
      ; seconds : float
      }

(* See the [.mli]. *)
let describe_problem : problem -> string = function
  | Missing_tool { tools; needed_for } ->
    Printf.sprintf
      "%s is needed for %s, and is not on PATH. The files made so far are kept."
      (String.concat " or " tools)
      needed_for
  | Failed { tool; detail; log } ->
    Printf.sprintf
      "%s failed (%s).%s"
      tool
      detail
      (match log with
       | Some l -> Printf.sprintf " Its log is %s." l
       | None -> "")
  | Timed_out { tool; seconds } ->
    Printf.sprintf
      "%s was stopped after %g seconds. Raise the time limit with [MeBi Config \
       Bounds Draw Time <s>], or draw fewer states."
      tool
      seconds
;;

(* See the [.mli]. *)
let valid_name (s : string) : bool =
  let ok_char : char -> bool = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true
    | _ -> false
  in
  String.length s > 0
  && String.length s <= 100
  && String.for_all ok_char s
  && (not (Char.equal s.[0] '-'))
  && not (Char.equal s.[0] '.')
;;

(* See the [.mli]. *)
let name_of_term ~(kind : string) (term : string) : string =
  let b : Buffer.t = Buffer.create 40 in
  let pending : bool ref = ref false in
  String.iter
    (fun c ->
      match Char.lowercase_ascii c with
      | ('a' .. 'z' | '0' .. '9') as c ->
        if !pending && Buffer.length b > 0 then Buffer.add_char b '-';
        pending := false;
        Buffer.add_char b c
      | _ -> pending := true)
    term;
  let slug : string = Buffer.contents b in
  let slug : string =
    if String.length slug > 40 then String.sub slug 0 40 else slug
  in
  (* a cut can leave a trailing hyphen *)
  let slug : string =
    if String.length slug > 0 && Char.equal slug.[String.length slug - 1] '-'
    then String.sub slug 0 (String.length slug - 1)
    else slug
  in
  if String.equal slug "" then kind else kind ^ "-" ^ slug
;;

(* See the [.mli]. *)
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
type status =
  | Exited of int
  | Killed
  | Unrunnable of string

(* See the [.mli]. [sh] only changes directory and runs [argv] in place of
   itself, so the process waited on is the program, and killing it kills
   the program. OCaml's [Unix] has no spawn with a working directory, and
   changing the session's own would change it for Rocq. *)
let run ~(timeout : float) ~(dir : string) (argv : string list) : status =
  let devnull : Unix.file_descr = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
  Fun.protect
    ~finally:(fun () -> Unix.close devnull)
    (fun () ->
      let args : string array =
        Array.of_list ("sh" :: "-c" :: "cd \"$0\" && exec \"$@\"" :: dir :: argv)
      in
      match Unix.create_process "sh" args devnull devnull devnull with
      | exception Unix.Unix_error (e, _, _) -> Unrunnable (Unix.error_message e)
      | pid ->
        let deadline : float = Unix.gettimeofday () +. timeout in
        let rec wait () : status =
          match Unix.waitpid [ Unix.WNOHANG ] pid with
          | exception Unix.Unix_error (e, _, _) ->
            Unrunnable (Unix.error_message e)
          | 0, _ ->
            if Unix.gettimeofday () >= deadline
            then (
              (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
              (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ());
              Killed)
            else (
              Unix.sleepf 0.02;
              wait ())
          | _, Unix.WEXITED n -> Exited n
          | _, (Unix.WSIGNALED _ | Unix.WSTOPPED _) -> Exited (-1)
        in
        wait ())
;;

(* See the [.mli]. [Utils.FileWriter.create_parent_dir] makes the directory
   that will hold a file, so it is given one in [dir]. *)
let write
      ?(labels : Draw.labels option)
      ?(direction : Draw_style.direction option)
      ~(dir : string)
      ~(name : string)
      ~(style : Draw_style.t)
      (d : Draw.t)
  : string list
  =
  Utils.FileWriter.create_parent_dir (Filename.concat dir name);
  let files : (string * string) list =
    [ name ^ ".tikz", Draw.picture ?labels ~style d
    ; name ^ ".style.tikz", Draw_style.tikzset ?direction style
    ; name ^ ".tex", Draw.wrapper ~name
    ]
  in
  List.map
    (fun (file, text) ->
      let path : string = Filename.concat dir file in
      Out_channel.with_open_text path (fun oc -> output_string oc text);
      path)
    files
;;

(** [first_error log] is the first line of the TeX log [log] that starts an
    error (with [!]). [None] if the log cannot be read or has none. Raises
    nothing. *)
let first_error (log : string) : string option =
  match In_channel.with_open_text log In_channel.input_all with
  | exception Sys_error _ -> None
  | text ->
    String.split_on_char '\n' text
    |> List.find_opt (fun l -> String.length l > 0 && Char.equal l.[0] '!')
    |> Stdlib.Option.map String.trim
;;

(** [remove path] removes [path] if it is there. *)
let remove (path : string) : unit = try Sys.remove path with Sys_error _ -> ()

(** [exit_problem tool status ~log] is why [tool], which ended as [status],
    did not do its job, or [None] if it did. *)
let exit_problem
      ~(tool : string)
      ~(timeout : float)
      ~(log : string option)
      (st : status)
  : problem option
  =
  match st with
  | Exited 0 -> None
  | Exited n ->
    let detail : string =
      match Stdlib.Option.bind log first_error with
      | Some e -> e
      | None -> Printf.sprintf "exit code %i" n
    in
    Some (Failed { tool; detail; log })
  | Killed -> Some (Timed_out { tool; seconds = timeout })
  | Unrunnable e -> Some (Failed { tool; detail = e; log = None })
;;

(** [make_pdf ~timeout ~dir ~name] compiles [name].tex, and is the PDF's path
    or why there is none. The TeX log is kept only if it failed. *)
let make_pdf ~(timeout : float) ~(dir : string) ~(name : string)
  : (string, problem) result
  =
  match find_exe "lualatex" with
  | None ->
    Error (Missing_tool { tools = [ "lualatex" ]; needed_for = "a PDF" })
  | Some lualatex ->
    let path (ext : string) : string = Filename.concat dir (name ^ ext) in
    let st : status =
      run
        ~timeout
        ~dir
        [ lualatex
        ; "-interaction=nonstopmode"
        ; "-halt-on-error"
        ; "-no-shell-escape"
        ; name ^ ".tex"
        ]
    in
    (match
       exit_problem ~tool:"lualatex" ~timeout ~log:(Some (path ".log")) st
     with
     | Some p -> Error p
     | None ->
       remove (path ".aux");
       remove (path ".log");
       Ok (path ".pdf"))
;;

(** [make_png ~timeout ~dir ~name] rasterises [name].pdf, and is the PNG's
    path or why there is none. *)
let make_png ~(timeout : float) ~(dir : string) ~(name : string)
  : (string, problem) result
  =
  let png : string = Filename.concat dir (name ^ ".png") in
  let attempt (tool : string) (argv : string list) : (string, problem) result =
    match exit_problem ~tool ~timeout ~log:None (run ~timeout ~dir argv) with
    | None -> Ok png
    | Some p -> Error p
  in
  match find_exe "pdftocairo", find_exe "gs" with
  | Some p, _ ->
    attempt
      "pdftocairo"
      [ p; "-png"; "-singlefile"; "-r"; "200"; name ^ ".pdf"; name ]
  | None, Some g ->
    attempt
      "gs"
      [ g
      ; "-q"
      ; "-dNOPAUSE"
      ; "-dBATCH"
      ; "-sDEVICE=png16m"
      ; "-r200"
      ; "-dTextAlphaBits=4"
      ; "-dGraphicsAlphaBits=4"
      ; "-sOutputFile=" ^ name ^ ".png"
      ; name ^ ".pdf"
      ]
  | None, None ->
    Error
      (Missing_tool { tools = [ "pdftocairo"; "gs" ]; needed_for = "a PNG" })
;;

(* See the [.mli]. *)
let render
      ~(format : format)
      ~(timeout : float)
      ~(dir : string)
      ~(name : string)
  : string list * problem list
  =
  match format with
  | Tex -> [], []
  | Pdf | Png ->
    (match make_pdf ~timeout ~dir ~name with
     | Error p -> [], [ p ]
     | Ok pdf ->
       (match format with
        | Png ->
          (match make_png ~timeout ~dir ~name with
           | Ok png -> [ pdf; png ], []
           | Error p -> [ pdf ], [ p ])
        | Tex | Pdf -> [ pdf ], []))
;;
