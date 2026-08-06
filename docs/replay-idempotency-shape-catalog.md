# The Replay-Idempotency Shape Catalog

*Recognising the handler shapes that are safe to run twice — and the property each one admits.*

## Why this page exists

The property-discovery toolchain (SwiftProjectLint → swift-infer → SwiftPropertyLaws)
was built to surface *value-shaped* properties: round-trips, monoids, commutativity,
and **value idempotence** — `f(f(x)) == f(x)` for a pure function. swift-infer's
`IdempotenceTemplate` covers exactly that case, and its reducer sibling
(`IdempotenceInteractionTemplate`) covers the double-apply-a-reducer-action case by
matching a curated verb list (`refresh` / `reset` / `clear` / …). That template's own
caveat draws the boundary: *"detection is purely name-based — reducer-body purity for
this action is not yet inspected."*

**Replay-idempotency is a different animal.** SwiftIdempotency's subject is the
side-effecting handler — a webhook dispatch, an order insert, an album download — that
is safe to run twice not because it returns the same value but because its *observable
effects* happen once. The signal that makes such a handler idempotent lives in the
**body and signature** (a dedup gate, a stable-key parameter, an `@ExternallyIdempotent`
claim), which is precisely what neither existing discovery template inspects. So there
is a real discovery hole exactly where this package lives: the toolchain *enforces*
replay-idempotency claims (SwiftEffectInference parses the annotation grammar; the
linter's Idempotency Violation rule polices it) but has no way to *propose* the shape
where no one has claimed it yet.

This catalog closes the human-facing half of that hole. It is the Section 2.4.2 move —
*state the reference definition, then let a machine try to break it* — applied to
replay-idempotency. Replay handlers are **not** the shapeless bugs that technique was
invented for: they have a very legible structure, and once you can name the four shapes
below, you can recognise them in your own code and write the property by hand today,
with no new tooling. The catalog is also the design source for a future
`ReplayIdempotenceTemplate` in swift-infer (see *For tool authors* at the end).

Every shape below is drawn from a working fixture in [`examples/`](../examples). The
fixtures are the ground truth; this page is the map.

---

## How to read a shape

Each entry states five things, because those are exactly what you need to turn a hunch
into a runnable property:

| Field | What it tells you |
|---|---|
| **Signal** | the structural tell in the code that says "this is a replay-idempotency candidate" |
| **What makes it safe** | the mechanism (the gate, the key) that *earns* the idempotence — remove it and the property fails |
| **The property** | the refutable law, stated as effects, not return values |
| **How to write it** | the SwiftIdempotency assertion that encodes the property |
| **The twin that breaks it** | the plausible-but-wrong implementation the property must *reject* (this is what makes the law refutable rather than vacuous) |

A note on the last row, because it is the load-bearing one. A property is only worth
proposing if some type-correct, plausible implementation is *rejected* by it. `f(x) == f(x)`
admits every implementation and catches nothing. Each shape below names a concrete twin —
usually "the same handler with the gate deleted" — that the property disproves. That twin
is why the shape is on this catalog and not in a list of comforting tautologies.

---

## Shape 1 — Key-from-entity builder

**The purest shape: a handler whose only idempotency work is deriving a stable key from a
stable identity.** No gate, no storage — the guarantee is bought at construction time by
carrying `IdempotencyKey` in the type signature so a caller *cannot* smuggle a
per-invocation value in.

Fixture: [`StripeWebhookHandler`](../examples/webhook-handler-sample/Sources/WebhookHandlerSample/StripeWebhookHandler.swift)

```swift
public static func makeChargeRequest(for event: PaymentIntent) -> ChargeRequest {
    ChargeRequest(
        amountMinorUnits: event.amountMinorUnits,
        currency: event.currency,
        idempotencyKey: IdempotencyKey(fromEntity: event)   // ← the signal
    )
}
```

- **Signal.** A value is built with `IdempotencyKey(fromEntity:)` (or a labelled
  `IdempotencyKey` initialiser) from a parameter that is `Identifiable` with a
  *stable* id — one the upstream system redelivers verbatim on retry (a Stripe event id,
  not a fresh `UUID()`).
- **What makes it safe.** The key is a pure function of the entity's stable id, and the
  downstream type demands an `IdempotencyKey` rather than a `String`, so the stability is
  enforced at the call site.
- **The property.** For a fixed entity, the built request is identical across invocations:
  `makeChargeRequest(for: e) == makeChargeRequest(for: e)`, and its key equals
  `IdempotencyKey(fromEntity: e)`.
- **How to write it.** This shape is pure and `Equatable`, so a plain
  `#assertIdempotent { handler.makeChargeRequest(for: event) }` at the call site is
  enough — no recorder needed.
- **The twin that breaks it.** Derive the key from `UUID()` or `Date()` instead of the
  entity id. Every call now yields a different key; the equality property fails, and the
  linter's `missingIdempotencyKey` rule flags it independently.

> This is the boundary case where replay-idempotency collapses back into *value*
> idempotence — which is why it is the one shape swift-infer's existing `IdempotenceTemplate`
> could already almost reach. The three shapes below are the ones it cannot.

---

## Shape 2 — Dedup-gate handler

**The canonical effectful shape, and the one with the buggy twin shipped alongside it.**
An early-return gate checks whether this key has already been handled; if so, the handler
short-circuits before doing any work.

Fixture: [`OrderCreatedHandler`](../examples/option-b-sample/Sources/OptionBSample/OrderCreatedHandler.swift)

```swift
public func handle(_ order: Order) async throws -> Bool {
    if await dedup.hasHandled(orderID: order.id) {   // ← the gate
        return false
    }
    try await repo.insert(order)                     // ← the effect
    await dedup.markHandled(orderID: order.id)
    return true
}
```

- **Signal.** An `async throws` handler whose first statement is a dedup check
  (`hasHandled` / `exists` / `contains`) keyed on a stable id, with an early return, and a
  persistence/network effect *after* the gate.
- **What makes it safe.** The gate — and nothing else. The effect runs at most once per
  key because the second invocation takes the early return.
- **The property.** Under a fixed key, the observable effects after two invocations equal
  the effects after one: *effects are idempotent*, even though the two *return values*
  differ (`true` then `false`).
- **How to write it.** This is the motivating case for the Option B surface, because the
  return type (`Bool`) makes a return-equality check *silent* on the bug — both calls to
  a broken handler return `true`. You must observe effects:

  ```swift
  try await assertIdempotentEffects(recorders: [repo]) {
      _ = try await handler.handle(order)
  }
  ```

- **The twin that breaks it.**
  [`BuggyOrderHandler`](../examples/option-b-sample/Sources/OptionBSample/OrderCreatedHandler.swift#L43)
  ships in the same file: identical signature, gate deleted, so every invocation writes.
  `assertIdempotentEffects` catches it (two inserts, effect count 2);
  `#assertIdempotent` does **not** (both calls return `true`). That divergence is the
  whole reason Option B exists, and it is the sharpest lesson in the catalog: *when the
  return type is trivial, the property must be stated over effects or it cannot fail.*

---

## Shape 3 — Fetch-existing-or-insert

**The database-backed cousin of the dedup gate.** Instead of a separate dedup store, the
handler queries for an existing row under the key and returns it if present, inserting only
on a miss. Common wherever a `@Model` / ORM row *is* the dedup record.

Fixture: [`OfflineManager.download`](../examples/swiftdata-sample/Sources/SwiftDataSample/OfflineManager.swift#L52)

```swift
@ExternallyIdempotent(by: "idempotencyKey")          // ← the claim
public static func download(
    album: Album,
    idempotencyKey: IdempotencyKey,                  // ← the key parameter
    in container: ModelContainer
) throws -> OfflineAlbum {
    // …
    if let existing = try context.fetch(descriptor).first {
        return existing                              // ← the gate
    }
    let offline = OfflineAlbum(id: album.id, /* … */)
    context.insert(offline)
    try context.save()
    return offline
}
```

- **Signal.** A handler carrying `@ExternallyIdempotent(by: "someParam")` (or a
  fetch-then-conditionally-insert body) with an `IdempotencyKey` parameter, returning a
  persisted row.
- **What makes it safe.** The fetch-first branch: a second call under the same key finds
  the row the first call wrote and returns it unchanged.
- **The property, two ways.** Both are worth stating because they catch different breaks:
  - *Identity:* two calls under the same key return the same row —
    `first.persistentModelID == second.persistentModelID`.
  - *Count:* the row count under the key stays at 1 after two invocations. This one
    survives even when the return type is a non-`Equatable` reference, which the identity
    form cannot compare directly.
- **How to write it.** The row-count invariant is the robust form when the return is a
  non-`Equatable` `@Model` — assert `fetchCount == 1` after a double invocation (see
  [`DownloadHandlerTests`](../examples/swiftdata-sample/Tests/SwiftDataSampleTests/DownloadHandlerTests.swift)).
  For `#assertIdempotent`, wrap the result's value fields in an `Equatable` struct (the
  hellovapor-documented workaround for non-`Equatable` `@Model` returns).
- **The twin that breaks it.** Drop the fetch branch and insert unconditionally: the row
  count goes to 2 and the identity form returns two different rows. Note the fixture also
  has `@Attribute(.unique)` on the id as defence-in-depth — real, but *not* the gate; the
  property is about the handler's logic, not the schema constraint that happens to backstop
  it.

---

## Shape 4 — Route-effect-through-key

**The most general effectful shape: the idempotency key is threaded into a downstream side
effect, and the handler is idempotent *relative to that key* whether or not it owns any
storage of its own.** The effect is abstracted behind a boundary (a recorder closure, a
client protocol) so tests can observe it.

Fixture: [`AcronymService`](../examples/fluent-sample/Sources/FluentSample/AcronymService.swift#L47)

```swift
@ExternallyIdempotent(by: "idempotencyKey")
public static func notifyCache(
    acronym: Acronym,
    idempotencyKey: IdempotencyKey,
    recorder: (IdempotencyKey, String) -> Void       // ← the observable effect boundary
) {
    recorder(idempotencyKey, acronym.short)
}
```

- **Signal.** `@ExternallyIdempotent(by: "someKey")` on a handler whose side effect is
  delivered through an injected boundary, with the key derived from a persisted entity's
  primary key (here via `IdempotencyKey(fromFluentModel:)`, which uses Fluent's
  `requireID()` for the pre-save failure case).
- **What makes it safe.** The downstream system is assumed to deduplicate on the key
  (Redis SETNX, a DynamoDB conditional put, a `UNIQUE` constraint). The handler's job is
  only to *route a stable key* — its correctness reduces to "the key is stable," which is
  Shape 1 wearing a side effect.
- **The property.** For a fixed key, the effect delivered to the boundary is identical
  across invocations: same key, same payload, every time.
- **How to write it.** Inject a recording boundary and assert the recorded effects match
  across a double invocation — `assertIdempotentEffects(recorders:)` with the recorder
  conforming to `IdempotentEffectRecorder`.
- **The twin that breaks it.** Derive the key inside the handler from something
  per-invocation (a fresh `UUID()`, `Date()`), or read a mutable field that the first call
  changed. The routed effect now differs between calls and the property fails.

---

## The taxonomy at a glance

| Shape | Structural signal | What earns idempotence | Property is stated over | Return-equality enough? |
|---|---|---|---|---|
| **1 · Key-from-entity** | `IdempotencyKey(fromEntity:)` from a stable id | pure key derivation | the built value | ✅ (it's pure) |
| **2 · Dedup gate** | `hasHandled` early return, then effect | the gate | **effects** | ❌ (trivial return hides the bug) |
| **3 · Fetch-or-insert** | `@ExternallyIdempotent`, fetch-then-insert | the fetch-first branch | row identity **or** row count | ⚠️ (only via `Equatable`-struct wrap) |
| **4 · Route-through-key** | `@ExternallyIdempotent`, effect via boundary | key stability + downstream dedup | recorded effects | ❌ |

Three of the four shapes (2, 3, 4) demand you state the property over **effects**, not
return values — which is exactly the capability the value-shaped discovery templates lack,
and exactly why this catalog is a prerequisite for teaching a machine to propose these.

---

## The boundary: where these shapes stop

A property needs a reference definition it can be false against. These four shapes supply
one — a stable key, a gate, a fetch-first branch — and where none is present, replay-safety
has no algebraic handle and the tools should fall silent rather than manufacture a law.
Two honest non-cases:

- **A handler that is idempotent by luck of ordering** (e.g. writes that happen to be
  overwritten by a later unconditional write) has no gate to point at. There is nothing
  structural to recognise, so nothing to propose.
- **A pure computation dressed as a handler** (Shape 1's degenerate form —
  `OrderTotaliser`, `PricingCalculator` in the fixtures) is *value* idempotence, already
  covered by swift-infer's `IdempotenceTemplate`. It belongs in the value-property
  catalogue, not here. Listing it here would be double-counting.

---

## For tool authors — this page as a discovery spec

This catalog is also the design source for a `ReplayIdempotenceTemplate` in swift-infer.
The four *Signal* rows are the match rules; the four *Property* rows are what `discover`
would propose; the four *twin* rows are the acceptance/rejection set. A template built from
this page is better-founded than the existing name-based reducer template, because for an
effectful handler you *can* inspect the body for the gate — you are not stuck at
name-matching.

**One hard rule, and it is the same rule Appendix C spends pages on.** The fixtures in
[`examples/`](../examples) were written by this package's author. They are legitimate as
(a) the human-facing catalogue above and (b) a development / regression set — the same
standing as the [`mutants/`](../mutants) corpus. They are **not** legitimate as *evidence*
that discovery works: tuning a template against them and then reporting "it finds them" is
the *grade-your-own-homework* trap, and the frozen-answer-key discipline forbids it. The
evidence that replay-idempotency discovery works must come from an external oracle — point
the template at `MacCloud_server`, whose retry-safety bugs were real and unplanted, or at a
public library's fix commit. That is the same rule that licensed the swift-collections
`symmetricDifference` fix.

---

*Fixtures referenced: [`webhook-handler-sample`](../examples/webhook-handler-sample),
[`option-b-sample`](../examples/option-b-sample),
[`swiftdata-sample`](../examples/swiftdata-sample),
[`fluent-sample`](../examples/fluent-sample). Value-idempotence fixtures
([`assert-idempotent-sample`](../examples/assert-idempotent-sample),
[`idempotency-tests-sample`](../examples/idempotency-tests-sample)) are catalogued as
Shape 1's degenerate form and belong to the value-property surface.*
