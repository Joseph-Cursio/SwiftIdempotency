# Slot 21 + 22 Post-Ship Verification on Uitsmijter

## Summary

**Both slots verified on real adopter code.** Before/after scan on the
Uitsmijter trial fork with annotations added to two functions
confirms the predicted diagnostic delta matches the slot definitions
exactly.

## Method

1. Annotated two functions in the Uitsmijter trial fork:
   - `Sources/Uitsmijter-AuthServer/routes.swift` — added
     `/// @lint.context replayable` to `routes(_ app:) throws`
     (contains 12 `app.register(collection:)` call sites).
   - `Sources/Uitsmijter-AuthServer/JWT/KeyStorage+RedisImpl.swift`
     — added `/// @lint.context strict_replayable` to
     `generateNewActiveKey()` (contains a `Task.sleep(nanoseconds:)`
     call in a retry-backoff loop at line 323, plus ~17 other
     unclassified calls that will also fire under strict mode).
2. Ran `swift run CLI /tmp/Uitsmijter-trial --categories idempotency
   --threshold info` against two SwiftProjectLint tips:
   - **Pre-ship baseline:** slot-20 tip `69979a4` (before PRs
     #27/#28 landed).
   - **Post-ship:** slot-22 tip `a1024ac` (after both merges).
3. Compared diagnostic counts and identified slot-specific deltas.

The annotation tier choice is intentional:

- `replayable` on `routes(_ app:)` — `register` is in
  `nonIdempotentNames`, so under `replayable` the inferrer fires
  `[Non-Idempotent In Retry Context]` on every call site. Slot 21
  silences these by making the `(app, register) → Vapor` pair
  resolve as idempotent before the bare-name check.
- `strict_replayable` on `generateNewActiveKey()` — `sleep` is
  *not* in any lexicon at slot 20, so it classifies as `nil`
  (unclassified); under `replayable` that passes silently, so no
  delta is observable. Under `strict_replayable` an unclassified
  callee fires `[Unannotated In Strict Replayable Context]`. Slot
  22 makes `Task.sleep` resolve as idempotent, silencing that
  fire.

## Results

### Slot 21 — `(app, register) → Vapor` whitelist

| File | Pre-ship fires | Post-ship fires | Delta |
|---|---|---|---|
| `routes.swift:28` — `app.register(collection: HealthController())` | 1 | 0 | silenced |
| `routes.swift:29` — `app.register(collection: VersionsController())` | 1 | 0 | silenced |
| `routes.swift:30` — `app.register(collection: MetricsController())` | 1 | 0 | silenced |
| `routes.swift:33` — `app.register(collection: LoginController())` | 1 | 0 | silenced |
| `routes.swift:34` — `app.register(collection: LogoutController())` | 1 | 0 | silenced |
| `routes.swift:37` — `app.register(collection: InterceptorController())` | 1 | 0 | silenced |
| `routes.swift:40` — `app.register(collection: WellKnownController())` | 1 | 0 | silenced |
| `routes.swift:41` — `app.register(collection: AuthorizeController())` | 1 | 0 | silenced |
| `routes.swift:42` — `app.register(collection: TokenController())` | 1 | 0 | silenced |
| `routes.swift:43` — `app.register(collection: RevokeController())` | 1 | 0 | silenced |
| `routes.swift:46` — `app.register(collection: DeviceController())` | 1 | 0 | silenced |
| `routes.swift:47` — `app.register(collection: ActivateController())` | 1 | 0 | silenced |

**12 `register` fires at slot-20 tip → 0 at slot-22 tip. ✅**

(Correction to the earlier trial-findings doc: 12 call sites, not 10.
The initial `app.register(collection:)` count missed `DeviceController`
and `ActivateController` — the RFC 8628 Device Authorization Grant
controllers registered at lines 46-47.)

`routes.swift` is completely silent under replayable post-ship.

### Slot 22 — `(Task, sleep) → SwiftConcurrency` whitelist

`KeyStorage+RedisImpl.swift:323` is the `Task.sleep(nanoseconds:)`
call site inside the 5-attempt backoff loop of `generateNewActiveKey()`.

| Pre-ship fires at :323 | Post-ship fires at :323 | Delta |
|---|---|---|
| `sleep` (unclassified) | silenced | slot 22 ✅ |
| `UInt64(attempt * 500_000_000)` (unclassified) | still fires | slot 22 doesn't cover stdlib initializer calls (expected) |

**`sleep` fires 1 → 0. ✅**

The `UInt64(...)` initializer call at the same line continues to
fire under `strict_replayable` — it's unclassified at both tips.
Slot 22's scope was intentionally narrow (`Task.sleep` specifically);
a general "stdlib numeric initializers are idempotent" whitelist
would be a separate future slice if evidence accumulates.

### Total issue count delta

- Pre-ship: 31 issues (12 `register` + 1 `sleep` + 18 other
  unclassified-in-strict-replayable from the backoff loop and
  surrounding Redis ops).
- Post-ship: 18 issues (0 `register` + 0 `sleep` + 18 other
  unchanged).
- **Delta: −13 diagnostics silenced = 12 slot 21 + 1 slot 22.**

Exactly matches the predicted silencing per slot.

## Trial fork state

- `Joseph-Cursio/Uitsmijter-idempotency-trial@32b2da4` on
  `package-integration-trial` — carries both the Option B probe
  (ship from 2026-04-24 earlier in this session) and the post-ship
  verification annotations. Both commits preserved for reproducibility.

## Raw scan outputs preserved

- `scan-slot-20-tip.txt` — full diagnostics at SwiftProjectLint
  `69979a4` with Uitsmijter annotated.
- `scan-slot-22-tip.txt` — full diagnostics at SwiftProjectLint
  `a1024ac` with same annotations.

## What this closes

The unchecked box from both PR descriptions — *"Post-merge: re-run
adopter road-tests on [adopter] annotated branches to confirm the
fires silence as predicted"* — is closed. The predicted silencing
held end-to-end on real adopter code, not just unit-test fixtures.

## Methodological lesson

The sweep methodology note from `trial-adopter-lint-sweep-2026-04-24.md`
can be extended: **bare-scan + grep surfaces candidate promotions;
annotation + two-run scan verifies the promotion's effect**. Neither
step requires full road-test ceremony (3-6 handler annotations,
transcript capture, replayable + strict_replayable passes). A
single annotated function per slice is sufficient evidence when the
slot is receiver-method-shape-narrow.

Sweep: ~30 min. Verification: ~30 min. Both together close a slice
end-to-end without the ~3-hour road-test cost when the slice is
mechanically well-defined.
