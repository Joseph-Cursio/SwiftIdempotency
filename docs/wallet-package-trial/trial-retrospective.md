# Wallet — trial retrospective

## Did the scope hold?

Yes. Source modifications stayed within the committed envelope
(six doc-comment annotations on the Passes-side handlers + one
README banner). No logic edits, no migration changes. Audit cap
held: Run A audited per-line (5 ≤ 30), Run B decomposed by
cluster (44 > 30, follows the cap rule). SQL ground-truth pass
ran as committed.

Trial fork is `Joseph-Cursio/wallet-idempotency-trial`, default
branch `trial-wallet`, hardened (issues/wiki/projects disabled,
non-contribution banner prepended).

## Pre-committed questions

### 1. Cross-function guard recognition

**Answer: no.** The linter fires on `createRegistration` (Run A
diagnostics 1, 3) and on `newDevice.create` (diagnostic 2)
because body-level inference reads each call site in isolation
and does not propagate the protective effect of the upstream
`if r != nil { return .ok }` guard back across the function
boundary. Sequential retry of `registerPass` is safe in practice
— the line-46 device lookup or the line-67 registration lookup
short-circuits the second invocation — but the linter cannot see
this without flow-sensitive cross-function analysis.

This is named adoption gap
**`cross-function-dedup-guard-not-propagated`** in the findings
doc. Whether to slice it depends on residual rate across rounds
— the Wallet round alone produced 3 of 5 Run A diagnostics from
this single shape, which is meaningful.

### 2. Real-bug discovery on personalize

**Answer: yes, and the unique constraint makes it worse, not
safer.** `personalizedPass` calls `personalization.create(on:
req.db)` at line 218 with no upstream read-guard. The
`PersonalizationInfo` migration declares
`.unique(on: passID)` — under road_test_plan's standard heuristic
("`.unique(on:)` flips create-on-retry to defensible"), this
would normally be defensible. **It is not.** The handler does not
catch Fluent's unique-violation error, so a sequential retry
returns a 500 instead of the 200 Apple's spec mandates. The
constraint converts a duplicate-row outcome into an HTTP failure,
which loops Apple's retry rather than satisfying it.

This is the round's single confirmed real-bug catch and the
strongest evidence to date that `@lint.context replayable` finds
genuine adopter bugs in spec-mandated retry contexts. It also
**refines the Fluent-adopter SQL heuristic**: `.unique(on:)` is
defensible *only when* the handler either (a) reads first and
returns the existing row's projection, or (b) catches the
violation and returns the spec-required success status. Neither
holds here.

The road_test_plan §"For Fluent adopters specifically" section
is correct in spirit but its blanket "flip to defensible" rule
needs a footnote covering this case. Folding back as a policy
note (below).

### 3. Observational classification

**Answer: yes.** `logMessage` is silent in Run A as predicted —
`req.logger.notice` is correctly classified as observational by
the linter's framework whitelist. Run B fires the
`Unannotated In Strict Replayable Context` diagnostic on
`req.content.decode` (line 182) but not on the `logger.notice`
call itself, which confirms the whitelist is working at strict
tier as well.

### 4. Multi-target Sources/

**Answer: single-root scan covers it.** A `swift run CLI
/path/to/wallet --categories idempotency` invocation walks
`Sources/VaporWallet/`, `Sources/VaporWalletPasses/`, and
`Sources/VaporWalletOrders/` from one entry point because they
share one `Package.swift`. The road_test_plan §"Multi-package
corpora" warning applies only when sub-packages have their own
nested `Package.swift` (vapor, hummingbird-examples,
swift-aws-lambda-runtime); Wallet does not have that shape
despite presenting three modules.

This was a free question — the scope doc could have answered it
by reading `Package.swift` first and noting the single-package
structure.

## Counterfactuals

- **If the scope had also annotated the Orders side**, Run A
  would have produced ~4 additional diagnostics (Orders has no
  personalize endpoint and no real-bug candidate). Yield would
  drop further: 1/10 = 0.10 instead of 1/6 = 0.17. Annotating
  Orders would have *halved* the round's yield without surfacing
  any new shape. Skipping it was correct.
- **If `personalizedPass` had been Apple-side observed first**,
  the bug would still be invisible to the user — sequential
  retries return 500 to Apple's servers, not to the developer.
  The linter caught a shape that production logs alone wouldn't
  cleanly attribute.
- **If the `PersonalizationInfo` migration had no unique
  constraint**, the bug would be different (silent duplicate
  rows, both with the same `pass_id`, leading to nondeterministic
  read behavior on subsequent fetches) but still caught by the
  same `create`-without-guard heuristic. The rule fires on the
  shape, not on the constraint — the SQL pass refines verdict,
  not detection.

## Cost summary

- Estimated: ~1 round of effort (6 handler annotations + 2 scans
  + audit + 4 docs).
- Actual: roughly tracking estimate. SQL ground-truth pass added
  ~10 minutes for three migration reads via `gh api`; previous
  rounds used local clone of `fluent-wallet` which would have
  been slightly faster. Three migration files vs the round's
  alternative of cloning the upstream — `gh api` was the right
  tradeoff.
- One minor friction: the Edit tool requires the file to be Read
  at the same absolute path; recon read was at
  `/tmp/.../wallet/...` but annotations targeted
  `/tmp/.../wallet-fork/...`. Six edits failed before re-Reading.
  Cost ~2 minutes; not worth folding into the template (it's a
  tool-mechanics quirk, not a road-test concept).

## Policy notes

**Refinement to road_test_plan §"For Fluent adopters
specifically".** The current blanket rule says
`.unique(on: <natural-key>)` flips create-on-retry to defensible.
Wallet shows this is too coarse: a unique constraint *without* an
error-catching handler converts duplicate-insert into a 500,
which is an Apple-spec violation in retry contexts. The refined
rule:

> `.unique(on:)` flips a `create` diagnostic to defensible when
> *either* (a) the handler reads the natural key first and
> returns success on a hit, *or* (b) the handler catches the
> Fluent unique-violation error and returns the framework's
> success status. If neither holds, the diagnostic is a real
> catch — the constraint turns duplicate-row into a 500, which
> is worse for a spec-mandated retry context than a silent
> duplicate.

Suggest folding into road_test_plan as a short note; the existing
heuristic remains correct for the common Fluent CRUD case
(`myfavquotes-api`, etc.) where read-first-then-create is
idiomatic.

## Data committed

Under `docs/wallet-package-trial/`:

- `trial-scope.md` — research question, pinned SHAs, annotation
  plan, scope commitment, pre-committed questions.
- `trial-findings.md` — Run A per-diagnostic table with SQL
  ground-truth pass, Run B carried + cluster decomposition,
  yield, comparison to predicted outcome.
- `trial-retrospective.md` — this document.
- `trial-transcripts/replayable.txt` — Run A raw output, 21 lines.
- `trial-transcripts/strict-replayable.txt` — Run B raw output,
  99 lines.

Trial fork: `Joseph-Cursio/wallet-idempotency-trial`,
SHA `b875f47`, branch `trial-wallet` (default).
