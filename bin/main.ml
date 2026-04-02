[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-4-6"]
[@@@ai_provider "Anthropic"]

open Cmdliner
open Ai_disclosure

let string_of_opam_value (v : OpamParserTypes.FullPos.value) =
  match v.pelem with
  | OpamParserTypes.FullPos.String s -> Some s
  | _ -> None

let read_opam_disclosure (opam : OpamFile.OPAM.t) : disclosure =
  let exts = OpamFile.OPAM.extensions opam in
  let ext key =
    Option.bind (OpamStd.String.Map.find_opt key exts) string_of_opam_value
  in
  let to_list = Option.fold ~none:[] ~some:(fun s -> [s]) in
  { level =
      Option.fold ~none:`Unknown ~some:level_of_string (ext "x-ai-disclosure");
    provenance =
      { models = to_list (ext "x-ai-model");
        providers = to_list (ext "x-ai-provider") } }

let with_switch_state f =
  OpamSystem.init ();
  let root = OpamStateConfig.opamroot () in
  ignore (OpamStateConfig.load_defaults ~lock_kind:`Lock_none root);
  OpamCoreConfig.init ();
  OpamFormatConfig.init ();
  OpamStateConfig.init ();
  OpamGlobalState.with_ `Lock_none @@ fun gt ->
  OpamSwitchState.with_ `Lock_none gt @@ fun st ->
  f st

let first_existing_dir dirs =
  List.find_opt (fun d -> Sys.file_exists d && Sys.is_directory d) dirs

let read_opam_file_disclosure path : disclosure =
  try
    let opam = OpamFile.OPAM.read (OpamFile.make (OpamFilename.of_string path)) in
    read_opam_disclosure opam
  with _ -> unknown

let find_project_disclosure dir =
  let abs = if Filename.is_relative dir then
    Filename.concat (Sys.getcwd ()) dir else dir in
  let rec find d =
    let entries = try Sys.readdir d with Sys_error _ -> [||] in
    let opam_file = Array.to_seq entries
      |> Seq.find (fun e -> Filename.check_suffix e ".opam") in
    match opam_file with
    | Some f -> Some (read_opam_file_disclosure (Filename.concat d f))
    | None ->
      let parent = Filename.dirname d in
      if parent = d then None else find parent
  in
  find abs

let get_package_disclosure st pkg =
  let disclosure = read_opam_disclosure (OpamSwitchState.opam st pkg) in
  let pkg_name = OpamPackage.Name.to_string (OpamPackage.name pkg) in
  let source_dir =
    OpamFilename.Dir.to_string (OpamSwitchState.source_dir st pkg) in
  let switch_dir =
    OpamFilename.Dir.to_string
      (OpamPath.Switch.root st.switch_global.root st.switch) in
  let lib_dir = Filename.concat (Filename.concat switch_dir "lib") pkg_name in
  let modules = match first_existing_dir [lib_dir; source_dir] with
    | Some dir -> scan_dir dir disclosure.level
    | None -> []
  in
  { pkg_name;
    pkg_version = OpamPackage.Version.to_string (OpamPackage.version pkg);
    disclosure; modules }

let resolve_packages st = function
  | Some name ->
    let n = OpamPackage.Name.of_string name in
    if not (OpamSwitchState.is_name_installed st n) then begin
      Format.eprintf "Error: package %s is not installed@." name;
      exit 1
    end;
    [OpamSwitchState.find_installed_package_by_name st n]
  | None ->
    OpamPackage.Set.elements st.installed

let all_levels = [`None; `Ai_assisted; `Ai_generated; `Autonomous; `Unknown]

let show_cmd =
  let doc = "Show AI disclosure for a package" in
  let info = Cmd.info "show" ~doc in
  let pkg_arg =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"PACKAGE"
           ~doc:"Package name to query")
  in
  let json_flag = Arg.(value & flag & info ["json"] ~doc:"Output as JSON") in
  let run pkg json =
    with_switch_state @@ fun st ->
    let d = get_package_disclosure st
      (List.hd (resolve_packages st (Some pkg))) in
    if json then pp_package_json Format.std_formatter d
    else pp_package Format.std_formatter d
  in
  Cmd.v info Term.(const run $ pkg_arg $ json_flag)

let lint_cmd =
  let doc = "Lint and summarise AI disclosure across installed packages" in
  let info = Cmd.info "lint" ~doc in
  let pkg_arg =
    Arg.(value & pos 0 (some string) None & info [] ~docv:"PACKAGE"
           ~doc:"Package to lint (default: all installed)")
  in
  let run pkg =
    with_switch_state @@ fun st ->
    let pkg_list = resolve_packages st pkg in
    let total = List.length pkg_list in
    let errors = ref 0 in
    let counts = Hashtbl.create 7 in
    List.iter (fun l -> Hashtbl.replace counts l 0) all_levels;
    let progress_part = Progress.Line.(list [
      spinner ();
      const " linting ";
      count_to total;
      const " ";
      bar ~style:`UTF8 ~width:(`Fixed 30) total;
      const " ";
      elapsed ();
    ]) in
    let name_part = Progress.Line.(rpad 30 string) in
    let line = Progress.Line.(pair ~sep:(const " ") progress_part name_part) in
    Progress.with_reporter line (fun report ->
      List.iter (fun p ->
        let pkg_name_s = OpamPackage.to_string p in
        report (0, pkg_name_s);
        let d = get_package_disclosure st p in
        let pkg_level = d.disclosure.level in
        Hashtbl.replace counts pkg_level
          (1 + try Hashtbl.find counts pkg_level with Not_found -> 0);
        if pkg_level = `None then
          List.iter (fun m ->
            let ml = m.impl.disclosure.level in
            if ml <> `None && ml <> `Unknown then begin
              Format.eprintf
                "warning: %s declares 'none' but module %s declares '%s'@."
                d.pkg_name m.mod_name (string_of_level ml);
              incr errors
            end
          ) d.modules;
        if pkg_level <> `Unknown then begin
          let n_overrides = List.length (List.filter (fun m ->
            let ml = m.impl.disclosure.level in
            ml <> `Unknown && ml <> pkg_level
          ) d.modules) in
          if n_overrides > 0 then
            Format.eprintf
              "info: %s declares '%s'; %d module(s) override with \
               different levels@."
              d.pkg_name (string_of_level pkg_level) n_overrides
        end;
        report (1, pkg_name_s)
      ) pkg_list);
    let declared =
      total - (try Hashtbl.find counts `Unknown with Not_found -> 0) in
    Format.printf "@.Checked %d package(s), %d with disclosure:@.@."
      total declared;
    List.iter (fun level ->
      let n = try Hashtbl.find counts level with Not_found -> 0 in
      if n > 0 then
        Format.printf "  %-15s %d@." (string_of_level level) n
    ) all_levels;
    Format.printf "@.";
    if !errors = 0 then
      Format.printf "No consistency issues found.@."
    else
      Format.printf "%d consistency issue(s) found.@." !errors
  in
  Cmd.v info Term.(const run $ pkg_arg)

let scan_cmd =
  let doc = "Scan a local directory for AI disclosure attributes in .cmt/.cmti files" in
  let info = Cmd.info "scan" ~doc in
  let dir_arg =
    Arg.(value & pos 0 string "." & info [] ~docv:"DIR"
           ~doc:"Directory to scan (default: current directory)")
  in
  let json_flag = Arg.(value & flag & info ["json"] ~doc:"Output as JSON") in
  let run dir json =
    let pkg_disclosure =
      Option.value ~default:unknown (find_project_disclosure dir) in
    let modules = scan_dir dir pkg_disclosure.level in
    let d =
      { pkg_name = Filename.basename
          (if dir = "." then Sys.getcwd () else dir);
        pkg_version = "dev";
        disclosure = pkg_disclosure;
        modules }
    in
    if json then pp_package_json Format.std_formatter d
    else pp_package Format.std_formatter d
  in
  Cmd.v info Term.(const run $ dir_arg $ json_flag)

let () =
  let doc = "Query AI content disclosure metadata from OCaml packages" in
  let info = Cmd.info "opam-ai-disclosure" ~version:"0.1.0" ~doc in
  Cmd.group info [show_cmd; lint_cmd; scan_cmd] |> Cmd.eval |> exit
