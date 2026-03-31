(lang dune 3.0)
(name opam-ai-disclosure)
(version 0.1.0)
(license ISC)
(authors "Anil Madhavapeddy <anil@recoil.org>")
(maintainers "Anil Madhavapeddy <anil@recoil.org>")
(source (github avsm/ocaml-ai-disclosure))
(generate_opam_files true)

(package
 (name opam-ai-disclosure)
 (synopsis "Query AI content disclosure metadata from OCaml packages")
 (description
  "A library and CLI tool for reading AI content disclosure attributes
   from compiled OCaml artifacts (.cmt/.cmti) and opam package metadata.
   Implements the OCaml AI Content Disclosure specification, aligned with
   the W3C AI Content Disclosure proposal.")
 (depends
  (ocaml (>= 5.0))
  (dune (>= 3.0))
  (cmdliner (>= 1.3.0))
  (opam-state (>= 2.5.0))
  (opam-format (>= 2.5.0))
  (progress (>= 0.4))))
