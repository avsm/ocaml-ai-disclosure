# AI Content Disclosure for OCaml (Proposal)

The OCaml ecosystem increasingly contains code produced with varying degrees of
AI involvement, ranging light AI-assisted editing ('copilots') to fully
autonomous generation.  There is currently no accepted mechanism for OCaml
authors to disclose AI involvement at any granularity within their packages.

This document proposes a voluntary disclosure scheme spanning three levels of
the OCaml ecosystem:

1. dune `(package)` stanza / opam fields: package-level default disclosure
2. OCaml source: per-module and per-value disclosure via attributes

The vocabulary and semantics are aligned with (and derived from) the
[W3C AI Content Disclosure](https://github.com/w3c-cg/ai-content-disclosure/)
proposal for HTML. We have also consulted the
[IETF AI-Disclosure header](https://www.ietf.org/archive/id/draft-abaris-aicdh-00.html)
draft.

These are intended to be voluntary disclosures in order to:

- expose AI usage to package managers so they can consider them while version solving
- guide limited human code review time towards appropriate areas of a codebase
- identify potential legal issues arising from the use of AI generated code
- assess quality control as models evolve over time to generate improved code
- guide policy decisions about the use of certain models or providers
- focus CI and fuzz testing infrastructure efforts towards uncertain code areas

## Disclosure Values

The W3C AI Content Disclosure proposal and the IETF AI-Disclosure HTTP
header draft define the same four semantic levels with different token
names.  The W3C tokens are used in HTML attributes whereas the IETF tokens
appear in HTTP headers.  This specification adopts the W3C tokens
because they are written directly in source code where readability
matters.

| Value | Meaning | W3C HTML | IETF HTTP |
|-------|---------|----------|-----------|
| `none` | No AI involvement; a human-only assertion | `none` | `none` |
| `ai-assisted` | Human-authored, AI edited or refined | `ai-assisted` | `ai-modified` |
| `ai-generated` | AI-generated with human prompting and/or review | `ai-generated` | `ai-originated` |
| `autonomous` | AI-generated without human oversight | `autonomous` | `machine-generated` |

The absence of any disclosure annotation means "unknown", not "none".
`none` represents an affirmative assertion that no AI was used.

Authors should declare the dominant disclosure level at each layer and
override at finer granularity where individual components differ.
Tooling can infer heterogeneity by comparing child annotations against
their parent; an explicit "mixed" value is not needed.

## opam packages

An opam package declares a disclosure level for that package using the
`x-ai-disclosure` extension field.  Optional companion fields carry
provenance metadata.

```
opam-version: "2.0"
name: "foo"
version: "1.0.0"
x-ai-disclosure: "ai-assisted"
x-ai-model: "claude-opus-4-6"
x-ai-provider: "Anthropic"
```

When sub-libraries or modules carry varying levels, the package should declare
the dominant level as a best-judgement default.  Finer-grained annotations
below will override where individual components differ.

These fields are currently invisible to the opam solver and client; they are
consumed by the `opam-ai-disclosure` plugin and downstream tooling. However, if
adopted (i.e. remove the `x-`) then a future version of the opam language may
use these during solves.

## dune package stanza

The `(package)` stanza in `dune-project` is the natural place to declare
disclosure at the package level within the build system.  We propose the
following fields:

```lisp
(lang dune 3.2x)

(package
 (name foo)
 (ai_disclosure
  (level ai-assisted)
  (model "claude-opus-4-6")
  (provider "Anthropic")))
```

When dune generates the `.opam` file, the `(ai_disclosure)` stanza
would be emitted as the corresponding `x-ai-disclosure`, `x-ai-model`,
and `x-ai-provider` extension fields.

**Status: not yet implemented.**  These fields are proposed for a future
version of the dune language.  Until then, authors should place the
`x-ai-*` fields in a `<package>.opam.template` file.  Dune merges the
template contents into the generated `.opam` file, so the extension
fields survive `dune build @install` and opam file regeneration.  For
example:

```
# foo.opam.template
x-ai-disclosure: "ai-assisted"
x-ai-model: "claude-opus-4-6"
x-ai-provider: "Anthropic"
```

The `opam-ai-disclosure` tool reads the resulting `.opam` fields
regardless of how they were produced.

## OCaml Module and Value

OCaml's attribute mechanism provides element-level granularity without
requiring any ppx rewriter.  The attributes are purely informational and
are preserved in `.cmt` and `.cmti` files for post-compilation analysis.

### Module-level disclosure

A floating attribute applies to the entire compilation unit:

```ocaml
[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-4-6"]
[@@@ai_provider "Anthropic"]
```

### Item-level disclosure

A declaration attribute applies to a single value, type, module
definition, or other structure item:

```ocaml
let merge_sort xs =
  (* hand-written implementation *)
  ...
[@@ai_disclosure "none"]

let pretty_print fmt v =
  (* generated by LLM from description *)
  ...
[@@ai_disclosure "ai-generated"]
```

It is unlikely that "none" will be heavily used, and the "ai-generated"
ones will be placed directly an LLM agent. Nonetheless, both are available
for direct use (e.g. an IDE might place these as well).

### Interface files

Disclosure in `.mli` files is independent of `.ml` files.  The interface
describes AI involvement in the API design; the implementation describes
AI involvement in the code.  They may differ: a human-designed API may
have an AI-generated implementation, or vice versa.

```ocaml
(* parser.mli *)
[@@@ai_disclosure "none"]  (* API designed by hand *)

(* parser.ml *)
[@@@ai_disclosure "ai-assisted"]  (* implementation used AI assistance *)
```

## Inheritance

Disclosure follows a nearest-ancestor model, consistent with the W3C
HTML proposal:

```
dune (package) / opam x-field
  \-- module floating attribute (overrides package)
        \-- item attribute (overrides module)
```

At each level:an explicit annotation overrides the inherited value, absence
means "inherit from parent", and at the root level absence means "unknown."
Tooling infers heterogeneity when child annotations differ from
their parent.  Authors need not declare this explicitly.

## Attribute Reference

### Disclosure level

| Attribute | Scope | Example |
|-----------|-------|---------|
| `(ai_disclosure ...)` | dune `(package)` stanza | `(ai_disclosure (level ai-generated))` |
| `x-ai-disclosure` | opam field | `x-ai-disclosure: "ai-generated"` |
| `[@@@ai_disclosure "..."]` | OCaml module | `[@@@ai_disclosure "none"]` |
| `[@@ai_disclosure "..."]` | OCaml item | `[@@ai_disclosure "ai-generated"]` |

### Provenance metadata (optional)

| Attribute | Purpose | Example value |
|-----------|---------|---------------|
| `ai_model` | Model identifier(s) | `"claude-opus-4-6"` |
| `ai_provider` | Provider name(s) | `"Anthropic"` |

The `ai_model` value should be the API model identifier (e.g.
`claude-opus-4-6`, `gpt-4o`, `gemini-2.5-pro`), not a marketing name.
This is the string a caller would pass to the provider's API to
reproduce the output, and is unambiguous across versions.

These attributes may be repeated to record multiple models that contributed to
a module.  Each repeated attribute adds to the list rather than replacing the
previous value:

```ocaml
[@@@ai_model "claude-opus-4-6"]
[@@@ai_model "gpt-4o"]
[@@@ai_provider "Anthropic"]
[@@@ai_provider "OpenAI"]
```

This supports workflows where different models are used for different
aspects of a module (e.g. one for code, another for tests), or where
multiple contributors use different models.

(TODO avsm: should we have an optional comment field where the use of the model
can be recorded? e.g. 'testing' or 'translation from Rust')

These use the same naming at each layer, adapted to the layer's syntax:
dune uses `(model ...)` inside the `(ai_disclosure)` stanza, opam uses
`x-ai-model`, and OCaml uses `[@@@ai_model "..."]`.

## Intended Workflow

The disclosure lifecycle has two phases: automated annotation during code
generation, followed by human review that adjusts or removes annotations.

### Phase 1: AI agent annotates

When an AI coding agent (e.g. Claude Code) generates or modifies OCaml
code, it should automatically insert `ai_disclosure` attributes at the
appropriate granularity.  A module entirely produced by the agent receives
a module-level `[@@@ai_disclosure "ai-generated"]`; individual functions
added to an otherwise human-written file receive item-level
`[@@ai_disclosure "ai-generated"]` annotations.  The agent should also
set `x-ai-disclosure` in the `.opam` file if the package-level default
has changed.

This phase is mechanical and should require no human effort.  The
annotations serve as a conservative starting point: every AI-touched
artifact is marked.

### Phase 2: Human reviewer adjusts

During code review, the human reviewer reads the AI-generated code and
exercises editorial judgement.  After reviewing and potentially modifying
a function or module, the reviewer may:

- Downgrade the disclosure from `ai-generated` to `ai-assisted` if
  they have substantially rewritten the code while retaining the AI's
  structural contribution.
- Remove the disclosure entirely (or replace it with `none`) if
  they judge that they have sufficiently understood, verified, and taken
  ownership of the code such that they consider it their own work.
- Leave it unchanged if the code is used as-is or with only minor
  corrections.

The key principle is that disclosure reflects the *current state of
authorship*.  A human who has thoroughly reviewed, understood, and taken
responsibility for a piece of code may reasonably assert `none`.  The
annotations exist to direct review attention, not to permanently brand code.

This two-phase workflow ensures that:
1. AI output is conservatively marked at the point of generation.
2. Human review effort is directed towards marked code.
3. Once a human has reviewed and taken ownership, the markers reflect
   that new reality.
4. The remaining markers in a codebase represent code that has not yet
   received sufficient human review.

## Tooling

### opam-ai-disclosure

The `opam-ai-disclosure` binary queries disclosure metadata from installed opam
packages and local build directories.  It reads the `x-ai-disclosure` fields
from `.opam` files and `ai_disclosure` attributes from `.cmt`/`.cmti` files
produced by the compiler.

```
opam-ai-disclosure show <package> [--json]
```

This displays the disclosure tree for a single installed package including its
package-level disclosure, and per-module disclosures extracted from
`.cmt`/`.cmti` files in the package's lib directory.

```
opam-ai-disclosure lint [<package>]
```

This lint disclosure consistency across all installed packages (or a single
package if named), and prints a summary of disclosure levels across the
switch.  The consistency checks are if a:

- package declares `none` (positive human-only assertion)
  but one of its modules carries a different disclosure level involving AI.
- package declares a specific level and one or more modules override it with a
  different level.  This is not an error (overrides are expected), but is
  reported for visibility. [TODO avsm: just remove this?]

```
opam-ai-disclosure scan [<dir>] [--json]
```

Scan a local directory for `.cmt`/`.cmti` files and extract disclosure
attributes.  Useful for inspecting a `_build` tree during development.

### Claude Code skill

The `ocaml-dev:ai-disclosure` skill for
[Claude Code](https://claude.ai/code) automates the annotation phase
of the workflow.  It inserts `ai_disclosure`, `ai_model`, and
`ai_provider` attributes into generated OCaml code and maintains
`<package>.opam.template` files.  Install it from the
[ocaml-claude-marketplace](https://github.com/avsm/ocaml-claude-marketplace).

### Future integration

`odoc` documentation generators may render disclosure metadata alongside module
documentation.  `merlin` and `ocaml-lsp` language servers may surface
disclosure attributes in hover information.

## FAQ

## What is the regulatory context here?

[EU AI Act Article 50(2)](https://eur-lex.europa.eu/eli/reg/2024/1689/oj)
(effective August 2026) requires providers of AI systems generating
synthetic "audio, image, video or text content" to mark outputs in a
machine-readable format.  Source code is not explicitly mentioned, and
the deployer-side obligations in Article 50(4) are limited to text
published to inform the public on matters of public interest, which
would not ordinarily include code in a repository.

Nevertheless, the provider obligation uses "text content" without
qualification, and the Draft Code of Practice interprets this broadly
to cover all AI-generated outputs regardless of audience or purpose.
Whether AI-generated source code falls within scope is an open
interpretive question that has not been addressed in existing legal
commentary to my knowledge.

This specification does not depend on any particular regulatory
outcome.  It is a voluntary, forward-looking mechanism that enables
the OCaml ecosystem to adopt machine-readable AI provenance now,
independently of whether disclosure becomes a legal requirement for
code within the EU or other zones.


### Why is absent "unknown" and not "none"?

The absence of an annotation means the disclosure status has not been
determined, not that no AI was used. This avoids placing a burden on authors
who do not use AI tools as they are not required to assert anything.  A
processor that encounters unannotated code should treat it as having no
information, not as a positive claim of human authorship.  However, tools may
choose to do mass annotations based on priors; for example all code originating
before 2022 might be automatically stamped as `none`.

The `none` value exists for authors who wish to positively assert that
a package or module was written without AI involvement.

### Why not use git blame?

`git blame` tracks who committed each line, not whether AI was
involved in producing it.

- A human may commit AI-generated code or an AI agent may commit
  but the code may have been human-reviewed and substantially rewritten
  before the commit.
- Rebases, squash merges, and history rewrites destroy blame
  attribution, whereas attributes in the source survive these operations.

This specification records the *current state* as declared by the author and is
not a historical audit trail. Environments that require full traceability may
use both mechanisms with a VCS for audit and attributes for declaration.

### Can a human claim AI-generated code as their own?

After reviewing, understanding, and potentially rewriting AI-generated code, a
human may downgrade the disclosure to `ai-assisted` or remove it entirely.
This proposal does not take a position on the legality of such an operation;
only that once a human has taken responsibility for the code, the markers can
reflect that.  See [Intended Workflow](#intended-workflow) for the two-phase
lifecycle.

### Does this take a position on whether AI code is good or bad?

No. The goal is a transparent and machine-readable signal so that consumers of
the code (whether humans, license checkers, package managers, or CI systems)
can apply their own policies.  Some may want to prioritise review of
AI-generated modules where others may want to filter by provider or model
version.

### Can this help with licensing policy?

Disclosure metadata can support organisational policies about which
models or providers are acceptable.  For example, a project could
lint for code generated by models whose training data or licensing
terms are incompatible with the project's licence.  The specification
does not define such policies, but provides the metadata they would
operate on.

## Contacts

This draft was authored by Anil Madhavapeddy <avsm2@cam.ac.uk>, with
significant contributions and discussions with Michael W. Dales, Patrick
Ferris, Mark T. Elvers, Jon Ludlam and Sadiq Jaffer.

This proposal text is licensed as CC-BY and any code as ISC.

## References

1. [W3C AI Content Disclosure Community Group](https://www.w3.org/community/ai-content-disclosure/)
2. [IETF draft-abaris-aicdh-00](https://www.ietf.org/archive/id/draft-abaris-aicdh-00.html)
3. [EU AI Act, Article 50](https://eur-lex.europa.eu/eli/reg/2024/1689/oj)
