# Round 7 Trial Scope

## Research question

Do the four mechanisms shipped in the `SwiftIdempotency` macros package integrate end-to-end with the `SwiftProjectLint` static analyzer on a realistic codebase? Four sub-questions:

1. **Attribute-form annotations.** Do `@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)` parse cleanly and feed the linter pipeline equivalently to doc-comment annotations?
2. **`IdempotencyKey` compile-time enforcement.** Does the strong type reject `UUID()` construction at the type system level, making the existing `missingIdempotencyKey` rule a fallback for untyped paths?
3. **`@Idempotent` peer-macro test generation.** Does the auto-generated `@Test func testIdempotencyOf<Name>()` peer compile and run on a zero-argument function in a realistic test target?
4. **`#assertIdempotent { body }` expression macro.** Does the freestanding macro produce working runtime assertions in `@Test`-decorated methods?

## Pinned artefacts

| Role | Repo / branch | SHA / tag | Local path |
|---|---|---|---|
| Linter baseline | `Joseph-Cursio/SwiftProjectLint` @ `main` | `58d302d` + uncommitted post-R7 fixes | `/Users/joecursio/xcode_projects/SwiftProjectLint` |
| Macros package | `Joseph-Cursio/SwiftIdempotency` @ `main` | `b78a176` + uncommitted post-R7 fixes | `/Users/joecursio/xcode_projects/SwiftIdempotencyPackage` |
| Validation sample | `SwiftIdempotencyPhase7Sample` (local-only, not pushed) | — | `/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample` |

The sample consumes the macros package via a local-path `Package.swift` dependency. This is a trial-time shortcut; real adopters would use the github URL dependency.

## Scope commitment

- **Purpose-built sample** rather than modifying pointfreeco or swift-aws-lambda-runtime's Package.swift. Cleaner than invasive dependency changes on a real target; matches the "validation against our own mechanism" framing rather than "re-measurement on a real corpus."
- **Both repos may accept edits during the trial** — this is validation of mechanisms in development, not frozen artefacts. Any breaking discovery produces a fix and a finding; the fix ships alongside the findings rather than on a follow-up branch.
- **Findings capture the deltas.** Every time the trial produced a compile error or unexpected behaviour, the finding is recorded with the root cause and the resolution (or documented limitation if unresolved).
- **Throwaway sample directory.** `SwiftIdempotencyPhase7Sample/` is local-only; never pushed anywhere.

## Sample structure

```
SwiftIdempotencyPhase7Sample/
├── Package.swift                   — SwiftPM manifest, local-path dep on macros package
├── Sources/SampleWebhookApp/
│   └── WebhookHandler.swift        — production-shape webhook handler with annotations
└── Tests/SampleWebhookAppTests/
    └── SampleIntegrationTests.swift — end-to-end integration tests
```

**Production code in `WebhookHandler.swift`:**
- `WebhookEvent`, `Gift` domain models (both `Identifiable`)
- `sendGiftEmail(for:idempotencyKey:)` — `@ExternallyIdempotent(by: "idempotencyKey")`, takes `IdempotencyKey`
- `handlePaymentIntent(event:gift:)` — `/// @lint.context replayable`, calls `sendGiftEmail` with `IdempotencyKey(fromEntity: gift)`
- `generateOneTimeToken()` — `@NonIdempotent` marker
- `logHandlerInvocation()` — `@Observational` marker

**Tests in `SampleIntegrationTests.swift`:**
- IdempotencyKey construction from `Identifiable` entities and audited strings
- Codable round-trip verification
- `#assertIdempotent` usage on pure computations
- Webhook flow end-to-end (handle → send-with-key)
- Compile-error documentation test (describes what's rejected at the type level)

## Acceptance summary

- Sample builds clean with both packages as dependencies.
- Sample's test suite passes (integration tests green).
- SwiftProjectLint scanning the sample produces **0 diagnostics** — the replayable → externally-idempotent call graph is a legal lattice row; attribute-form annotations feed the rule engine correctly.
- Every compile error or runtime error discovered during the trial is recorded in `trial-findings.md` as a Swift-macro-ecosystem finding with the resolution or documented limitation.

## Explicit non-scope

- **A new measurement against pointfreeco / swift-aws-lambda-runtime.** Round 7 is about the macros package + linter integration, not re-measuring the idempotency rules on real corpora (R1-R6 already did that).
- **Publishing the sample as an example directory in the macros package.** Keeping it as a local-only scaffold avoids conflating "trial artefact" with "user-facing sample" — the README's inline examples serve the latter purpose.
- **Modifying the proposal's Phase 5 scope claims.** The proposal doc reflects what shipped; the findings update it if round 7 surfaces a mechanism-level claim that needs revision.
