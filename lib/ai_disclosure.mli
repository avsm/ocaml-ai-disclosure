[@@@ai_disclosure "ai-assisted"]
[@@@ai_model "claude-opus-4-6"]
[@@@ai_provider "Anthropic"]

(** AI content disclosure types and extraction from compiled OCaml
    artifacts (.cmt/.cmti). *)

(** {1 Disclosure levels} *)

type level = [
  | `None
  | `Ai_assisted
  | `Ai_generated
  | `Autonomous
  | `Unknown
]

val level_of_string : string -> level
val string_of_level : level -> string
val pp_level : Format.formatter -> level -> unit

(** {1 Provenance metadata} *)

type provenance = {
  model : string option;
  provider : string option;
}

val empty_provenance : provenance
val pp_provenance : Format.formatter -> provenance -> unit

(** {1 Disclosure records}

    The types form a hierarchy:

    - {!type-disclosure}: a single level + provenance pair (the atom).
    - {!unit_disclosure}: disclosure for one compilation unit
      (.cmt or .cmti), including per-item overrides.
    - {!module_disclosure}: a named module with separate impl/intf
      disclosures.
    - {!package_disclosure}: a named package with a default disclosure
      and per-module details. *)

(** A level/provenance pair.  The shared building block for all
    disclosure records. *)
type disclosure = {
  level : level;
  provenance : provenance;
}

val unknown : disclosure

(** A named item (value, type, module binding) with its own
    disclosure, overriding the enclosing module default. *)
type item = {
  name : string;
  disclosure : disclosure;
}

(** Disclosure extracted from a single compilation unit. *)
type unit_disclosure = {
  disclosure : disclosure;
  items : item list;
}

val empty_unit : unit_disclosure

(** Disclosure for a module, with separate implementation and
    interface.  [intf] has level [`Unknown] when no interface
    disclosure exists. *)
type module_disclosure = {
  mod_name : string;
  impl : unit_disclosure;
  intf : unit_disclosure;
}

(** Disclosure for an opam package. *)
type package_disclosure = {
  pkg_name : string;
  pkg_version : string;
  disclosure : disclosure;
  modules : module_disclosure list;
}

(** {1 Pretty-printers} *)

val pp_item : Format.formatter -> item -> unit
val pp_module : Format.formatter -> module_disclosure -> unit
val pp_package : Format.formatter -> package_disclosure -> unit
val pp_package_json : Format.formatter -> package_disclosure -> unit

(** {1 Extraction from compiled artifacts} *)

(** [parse_cmt_file path] extracts disclosure from a .cmt or .cmti
    file.  Returns [None] if the file cannot be read. *)
val parse_cmt_file : string -> unit_disclosure option

(** {1 Directory scanning} *)

(** [scan_dir dir default_level] recursively scans [dir] for .cmt and
    .cmti files, extracting disclosure metadata from each module found.
    [default_level] is inherited by modules that do not declare their
    own level. *)
val scan_dir : string -> level -> module_disclosure list
