# hellovapor — Package Integration Trial Retrospective

## Did the scope hold?

Yes. One handler migrated (`createAcronym`), three test suites
added covering distinct API surfaces, one linter parity check
performed. No other controllers touched. No PR filed upstream.

One scope-adjacent find: the linter parity check surfaced a
**SwiftProjectLint-side gap** (`import Fluent` not recognised by
the FluentKit gate) that's orthogonal to the package-trial's
stated question. Recording it on the findings doc rather than
excluding it — it's genuine evidence about adoption ergonomics
that the linter / package composition depends on.

## What would have changed the outcome

- **If Fluent's `Model` protocol inherited `Identifiable`** (it
  reasonably could — `@ID var id: UUID?` is structurally
  sufficient), `IdempotencyKey(fromEntity:)` would be reachable
  without an adapter. That's a Fluent-upstream change, not
  something SwiftIdempotency can fix. But the package can adapt
  to this reality — the `CustomStringConvertible` constraint on
  the Optional ID is purely a SwiftIdempotency design choice.
- **If the linter's FluentKit gate accepted `import Fluent`**, the
  end-to-end story would have been "attribute form works cleanly,
  linter catches the save-without-key, adopter has to only think
  about one layer." Today, adopters either have to switch to the
  non-idiomatic `import FluentKit` (jarring), or the lint rule
  stays silent (bad).
- **If I'd used HelloVapor's existing Acronym migration** (pending
  on PR #1's `.unique(on: "short")` merge) as the idempotency-
  key source, there'd be an actual adopter-side alignment story:
  "the schema's natural key IS the idempotency basis, point the
  macro at it." Didn't go there because PR #1 isn't merged yet;
  would have conflated trial scope with merge status.

## Recommendations for the package API

Prioritized; compounding with the luka-vapor trial.

### Blocker (P0) — README "Using with Fluent ORM" section

Neither documentation section drafted so far (Option C pathology,
inline-closure migration) covers the Fluent-shaped adopter
experience. Fluent is the single most-used persistence library
in the Vapor ecosystem, so "how does SwiftIdempotency compose
with Fluent?" will be the first question most adopters ask. The
answer today is multi-paragraph:

- `Model` isn't `Identifiable` — extend or adapter-wrap.
- `id` is Optional — force-unwrap post-save, use header-sourced
  key pre-save.
- `Model` is a reference type, not `Equatable` — use tuple
  returns in `#assertIdempotent` closures.
- DB writes don't show up in return values — combine with
  explicit row-count asserts.

Drafting this properly is ~40 lines. It's worth blocking
v0.1.0 → SPI on — first impression matters for adopter uptake.

### Significant (P1) — API design for Optional IDs

The `CustomStringConvertible` constraint on `fromEntity:`'s `E.ID`
is the single most fixable friction. Dropping it would make the
constructor reach Fluent Models without any adapter code. The
implementation would need to handle Optional's stringification
("nil" for unwrapped) in a way that tells adopters "this key
isn't usable yet" — maybe a failable initialiser
`init?(fromEntity:)` that returns nil on nil ID.

Alternatively, a new dedicated constructor
`init?(fromFluentModel:)` specific to the Fluent shape. Less
general but more discoverable to the target audience.

Defer until a second Identifiable-but-Optional-ID adopter
confirms the pattern recurs outside Fluent. Could show up in
Core Data adopters, SwiftData adopters — worth checking.

### SwiftProjectLint-side (P1) — FluentKit gate alias

Not a SwiftIdempotency change, but a linter change the package's
story depends on. Extend the gate to accept `import Fluent`. Same
shape as slots 13–18 (data-table addition). Should promote to
**slot 19** in the SwiftProjectLint roadmap.

### Cosmetic (P3) — filename collision note in README

Add a one-line warning to the "Migrating inline-closure handlers"
section: "Watch for filename collisions with existing adopter
sources (e.g. `Migrations/CreateX.swift`); rename your new
handler file to avoid SwiftPM's 'multiple producers' error."

## Cost summary

Actual: ~40 minutes from fork clone to retrospective commit.
Baseline cold build was the biggest time sink (172s + 176s =
~6 minutes of wall-clock waiting). Everything else was
interactive.

Compared to luka-vapor (~45 minutes), the time profile was
similar despite HelloVapor being structurally larger — the
handler body is simpler (3 lines), the tests hit compile errors
immediately that surfaced findings quickly, and Fluent's Vapor
Testing harness (already present in the repo) saved harness-
wiring work.

## Policy notes for the plan

### SwiftProjectLint-side findings are in scope for package trials

The FluentKit-gate gap was surfaced by running the linter on
the migrated source — the same linter parity step the plan
mandates. When that check surfaces a linter gap, it IS a trial
finding. Update the plan's linter-parity section to note that
silent scans are informative, not an implicit "parity
confirmed."

### Compile errors are findings, not blockers

Both compile errors ran into on this trial surfaced real API
gaps (the Identifiable constraint + the CustomStringConvertible
constraint). The adopter-side workaround (`IdentifiableAcronym`
adapter with force-unwrap) is the trial output — not something
to hide. Fold into the plan's "Measurement" section: document
the precise compile errors verbatim.

### Multi-trial findings compose

luka-vapor found Option C pathology on trivial returns.
HelloVapor found the complementary gap on reference-type
returns. Together they define the Option C working set: it's
sharp on struct returns with synthesized Equatable, weak
everywhere else. The combined picture is stronger than either
trial alone — the plan should explicitly say "continue trials
until the working set is characterised," not "continue until
three green runs."

## Data committed

- `docs/hellovapor-package-trial/trial-scope.md`
- `docs/hellovapor-package-trial/trial-findings.md`
- `docs/hellovapor-package-trial/trial-retrospective.md`
- `docs/hellovapor-package-trial/migration.diff`

Fork state (on `Joseph-Cursio/HelloVapor-idempotency-trial`):
- `package-integration-trial` branch at current HEAD. Tests
  green on 5/5 trial tests. Default branch unchanged
  (`trial-hellovapor` from the linter round stays default).
