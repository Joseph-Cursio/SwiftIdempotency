# design-internal — an imported snapshot

These eight documents are **not authored here**. They are copied from
SwiftInferProperties, which keeps a cross-package design record: one doc per
companion package, plus a shared `glossary.md` and `open-threads.md`.

| | |
|---|---|
| **Source** | `SwiftInferProperties/docs/design-internal/` |
| **Imported from** | `dde5397` (2026-08-06) |
| **Imported on** | 2026-08-06 |

## Read-only here

Edit these in SwiftInferProperties and re-import. A change made in this copy is
lost the next time anyone re-imports, and worse, it is invisible to the drift
checking the source repo runs (`make docs-drift`), which compares each doc
against the package it *describes* — not against copies of itself.

That check is the reason these documents are trustworthy, and it is also why
this directory is a liability if anyone treats it as editable. The source repo's
own `swiftprojectlint.md` records what happens when a doc is written against a
checkout nobody verified: it was authored against a local `HEAD` **46 commits
behind origin**, two counts were stale within hours, and the drift check reported
`ok` the whole time because it was comparing against the same stale local state.
A second copy in a second repo is one more place for that to happen.

To refresh:

```sh
cp ~/xcode_projects/SwiftInferProperties/docs/design-internal/*.md \
   ~/xcode_projects/SwiftIdempotency/docs/design-internal/
```

…and update the commit in the table above.

## What each one is

| doc | what it covers |
|---|---|
| `glossary.md` | shared vocabulary across the five packages — including *effect lattice* and `@ClockDeterministic` |
| `open-threads.md` | unresolved questions and defects spanning repo boundaries |
| `swiftidempotency.md` | **this package, described from outside** — see below |
| `swiftprojectlint.md` | the linter: rules, the seed manifest, the entry point of the adoption loop |
| `swifteffectinference.md` | the shared purity/effect oracle both the linter and `swift-infer` consult |
| `swiftinferproperties.md` | the inference engine itself |
| `swiftpropertylaws.md` | the law kit |
| `swift-property-based.md` | the generator/shrinker substrate |

`swiftidempotency.md` is the most useful of the eight to read from here, because
it is this package seen by a consumer rather than by its author. Its **"Idempotent
means three different things across this toolchain"** section is the one to read
first — the value law `f(f(x)) == f(x)`, the reducer-action law, and the effect
law over the world are genuinely distinct, only the first two are checkable in
process, and conflating them is the most expensive mistake available here.

## Known-stale as of import

Every doc carries its own `doc-provenance` marker and a standing warning that
**counts rot while diagnoses do not**. Two claims were overtaken by work landed
the same day as this import, and are called out here so a reader does not act on
them:

- **`swiftidempotency.md`** and the seed-manifest discussion in
  `swiftprojectlint.md` / `swiftinferproperties.md` describe `.pbt/seeds.json` as
  carrying the idempotency *violation* but not the *tier*. That gap is closed:
  SwiftProjectLint#70 emits `effect` (declared tier, resolved tier, provenance,
  depth, reason) on `idempotency` seeds, and SwiftInferProperties#134 consumes it.
- The consumer acts only on `provenance: declared`. `inferred-upward` is withheld
  because SwiftProjectLint supplies its heuristic name inferrer as the anchor
  resolver to `applyBodyInference`, so an upward chain can bottom out on a name
  guess — and the manifest's provenance describes only the final hop. Closing
  *that* needs anchor-purity tracking in SwiftEffectInference's
  `BodyEffectInferrer`, which is the open follow-up.
