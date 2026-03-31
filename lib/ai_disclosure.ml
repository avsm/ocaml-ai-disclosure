[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-4-6"]
[@@@ai_provider "Anthropic"]

type level = [
  | `None
  | `Ai_assisted
  | `Ai_generated
  | `Autonomous
  | `Unknown
]

type provenance = {
  model : string option;
  provider : string option;
}

let empty_provenance = { model = None; provider = None }

type disclosure = {
  level : level;
  provenance : provenance;
}

let unknown = { level = `Unknown; provenance = empty_provenance }

type item = {
  name : string;
  disclosure : disclosure;
}

type unit_disclosure = {
  disclosure : disclosure;
  items : item list;
}

let empty_unit = { disclosure = unknown; items = [] }

type module_disclosure = {
  mod_name : string;
  impl : unit_disclosure;
  intf : unit_disclosure;
}

type package_disclosure = {
  pkg_name : string;
  pkg_version : string;
  disclosure : disclosure;
  modules : module_disclosure list;
}

let level_of_string = function
  | "none" -> `None
  | "ai-assisted" -> `Ai_assisted
  | "ai-generated" -> `Ai_generated
  | "autonomous" -> `Autonomous
  | _ -> `Unknown

let string_of_level = function
  | `None -> "none"
  | `Ai_assisted -> "ai-assisted"
  | `Ai_generated -> "ai-generated"
  | `Autonomous -> "autonomous"
  | `Unknown -> "unknown"

let pp_level ppf l = Format.pp_print_string ppf (string_of_level l)

let pp_provenance ppf prov =
  let parts = List.filter_map Fun.id [
    Option.map (fun m -> "model=" ^ m) prov.model;
    Option.map (fun p -> "provider=" ^ p) prov.provider;
  ] in
  if parts <> [] then
    Format.fprintf ppf " (%s)" (String.concat ", " parts)

let pp_disclosure ppf d =
  Format.fprintf ppf "%a%a" pp_level d.level pp_provenance d.provenance

let intf_differs m =
  m.intf.disclosure.level <> `Unknown &&
  m.intf.disclosure <> m.impl.disclosure

let pp_item ppf i =
  Format.fprintf ppf "%s: %a" i.name pp_disclosure i.disclosure

let pp_module ppf m =
  if intf_differs m then begin
    Format.fprintf ppf "@[<v 0>%s (impl): %a" m.mod_name
      pp_disclosure m.impl.disclosure;
    Format.fprintf ppf "@,%s (intf): %a" m.mod_name
      pp_disclosure m.intf.disclosure
  end else
    Format.fprintf ppf "@[<v 0>%s: %a" m.mod_name
      pp_disclosure m.impl.disclosure;
  List.iter (fun i -> Format.fprintf ppf "@,  %a" pp_item i)
    (m.impl.items @ m.intf.items);
  Format.fprintf ppf "@]"

let pp_package ppf d =
  Format.fprintf ppf "@[<v 0>%s %s: %a" d.pkg_name d.pkg_version
    pp_disclosure d.disclosure;
  List.iter (fun m -> Format.fprintf ppf "@,  %a" pp_module m) d.modules;
  Format.fprintf ppf "@]@."

let pp_json_opt ppf key = function
  | None -> ()
  | Some v -> Format.fprintf ppf ",@,\"%s\": \"%s\"" key v

let pp_disclosure_json ppf prefix d =
  Format.fprintf ppf ",@,\"%sdisclosure\": \"%s\"" prefix (string_of_level d.level);
  pp_json_opt ppf (prefix ^ "model") d.provenance.model;
  pp_json_opt ppf (prefix ^ "provider") d.provenance.provider

let pp_package_json ppf d =
  Format.fprintf ppf "@[<v 2>{@,";
  Format.fprintf ppf "\"package\": \"%s\",@," d.pkg_name;
  Format.fprintf ppf "\"version\": \"%s\"" d.pkg_version;
  pp_disclosure_json ppf "" d.disclosure;
  if d.modules <> [] then begin
    Format.fprintf ppf ",@,\"modules\": [@[<v 2>";
    List.iteri (fun i m ->
      if i > 0 then Format.fprintf ppf ",";
      Format.fprintf ppf "@,@[<v 2>{";
      Format.fprintf ppf "@,\"name\": \"%s\"" m.mod_name;
      pp_disclosure_json ppf "" m.impl.disclosure;
      if intf_differs m then
        pp_disclosure_json ppf "intf_" m.intf.disclosure;
      let items = m.impl.items @ m.intf.items in
      if items <> [] then begin
        Format.fprintf ppf ",@,\"items\": [@[<v 2>";
        List.iteri (fun j it ->
          if j > 0 then Format.fprintf ppf ",";
          Format.fprintf ppf "@,{\"name\": \"%s\", \"disclosure\": \"%s\"}"
            it.name (string_of_level it.disclosure.level)
        ) items;
        Format.fprintf ppf "@]@,]"
      end;
      Format.fprintf ppf "@]@,}"
    ) d.modules;
    Format.fprintf ppf "@]@,]"
  end;
  Format.fprintf ppf "@]@,}@."

(* Attribute extraction from .cmt/.cmti *)

let string_of_payload : Parsetree.payload -> string option = function
  | PStr [{pstr_desc = Pstr_eval ({pexp_desc =
      Pexp_constant {pconst_desc = Pconst_string (s, _, _); _}; _}, _); _}] ->
    Some s
  | _ -> None

let ai_attr_field (attr : Parsetree.attribute) =
  let name = attr.attr_name.txt in
  if String.starts_with ~prefix:"ai_" name then
    Some (String.sub name 3 (String.length name - 3),
          string_of_payload attr.attr_payload)
  else
    None

let update_disclosure d field value =
  match field, value with
  | "disclosure", Some s -> { d with level = level_of_string s }
  | "model", Some s ->
    { d with provenance = { d.provenance with model = Some s } }
  | "provider", Some s ->
    { d with provenance = { d.provenance with provider = Some s } }
  | _ -> d

let update_unit (u : unit_disclosure) field value : unit_disclosure =
  { u with disclosure = update_disclosure u.disclosure field value }

let add_item (u : unit_disclosure) name attrs : unit_disclosure =
  let d =
    List.fold_left (fun d attr ->
      match ai_attr_field attr with
      | Some (field, value) -> update_disclosure d field value
      | None -> d
    ) unknown attrs
  in
  if d.level = `Unknown then u
  else { u with items = u.items @ [{ name; disclosure = d }] }

let ident_name_opt = function Some id -> Ident.name id | None -> "_"

let extract_floating u (attr : Parsetree.attribute) =
  match ai_attr_field attr with
  | Some (field, value) -> update_unit u field value
  | None -> u

let extract_from_structure (str : Typedtree.structure) =
  List.fold_left (fun u (item : Typedtree.structure_item) ->
    match item.str_desc with
    | Tstr_attribute attr -> extract_floating u attr
    | Tstr_value (_, bindings) ->
      List.fold_left (fun u (vb : Typedtree.value_binding) ->
        let name = match vb.vb_pat.pat_desc with
          | Tpat_var (id, _, _) -> Ident.name id
          | _ -> "<pattern>"
        in
        add_item u name vb.vb_attributes
      ) u bindings
    | Tstr_module mb ->
      add_item u (ident_name_opt mb.mb_id) mb.mb_attributes
    | Tstr_type (_, decls) ->
      List.fold_left (fun u (td : Typedtree.type_declaration) ->
        add_item u (Ident.name td.typ_id) td.typ_attributes
      ) u decls
    | _ -> u
  ) empty_unit str.str_items

let extract_from_signature (sig_ : Typedtree.signature) =
  List.fold_left (fun u (item : Typedtree.signature_item) ->
    match item.sig_desc with
    | Tsig_attribute attr -> extract_floating u attr
    | Tsig_value vd ->
      add_item u (Ident.name vd.val_id) vd.val_attributes
    | Tsig_type (_, decls) ->
      List.fold_left (fun u (td : Typedtree.type_declaration) ->
        add_item u (Ident.name td.typ_id) td.typ_attributes
      ) u decls
    | Tsig_module md ->
      add_item u (ident_name_opt md.md_id) md.md_attributes
    | _ -> u
  ) empty_unit sig_.sig_items

let parse_cmt_file path =
  try
    let cmt = Cmt_format.read_cmt path in
    match cmt.cmt_annots with
    | Implementation str -> Some (extract_from_structure str)
    | Interface sig_ -> Some (extract_from_signature sig_)
    | _ -> None
  with _ -> None

(* Directory scanning *)

let module_name_of_path path =
  Filename.basename path |> Filename.chop_extension |> String.capitalize_ascii

let rec collect_cmt_files acc dir =
  let entries = ref [] in
  (try
    let dh = Unix.opendir dir in
    Fun.protect ~finally:(fun () -> Unix.closedir dh) @@ fun () ->
    try while true do
      let entry = Unix.readdir dh in
      if entry <> "." && entry <> ".." then
        entries := entry :: !entries
    done with End_of_file -> ()
  with Unix.Unix_error _ -> ());
  List.fold_left (fun acc entry ->
    let path = Filename.concat dir entry in
    match (try Some (Unix.stat path) with Unix.Unix_error _ -> None) with
    | Some st when st.Unix.st_kind = Unix.S_DIR ->
      collect_cmt_files acc path
    | Some _ when Filename.check_suffix entry ".cmt"
               || Filename.check_suffix entry ".cmti" ->
      path :: acc
    | _ -> acc
  ) acc !entries

let parse_or_empty path =
  Option.value ~default:empty_unit (parse_cmt_file path)

let scan_dir dir default_level =
  let by_module = Hashtbl.create 64 in
  List.iter (fun path ->
    let mod_name = module_name_of_path path in
    let impl, intf =
      Option.value ~default:(None, None) (Hashtbl.find_opt by_module mod_name)
    in
    Hashtbl.replace by_module mod_name
      (match Filename.extension path with
       | ".cmt"  -> (Some path, intf)
       | ".cmti" -> (impl, Some path)
       | _ -> (impl, intf))
  ) (collect_cmt_files [] dir);
  Hashtbl.fold (fun mod_name (impl_path, intf_path) acc ->
    let impl = Option.fold ~none:empty_unit ~some:parse_or_empty impl_path in
    let intf = Option.fold ~none:empty_unit ~some:parse_or_empty intf_path in
    let impl =
      if impl.disclosure.level <> `Unknown then impl
      else { impl with disclosure =
        { impl.disclosure with level = default_level } }
    in
    if impl.disclosure.level = `Unknown
       && intf.disclosure.level = `Unknown
       && impl.items = [] && intf.items = []
    then acc
    else { mod_name; impl; intf } :: acc
  ) by_module []
  |> List.sort (fun a b -> String.compare a.mod_name b.mod_name)
