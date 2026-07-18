# Mutation / regression corpus (private)

A hand-authored mutant corpus for **sharpening the kit itself** — the kit dogfooding
on itself, the discipline of Chapter 30 §30.4.4 made standing. Mutants live in
SwiftIdempotency's own source and are killed by its own tests, including the
**negative-control** `withKnownIssue` tests (`nonIdempotentFails`,
`nonEffectIdempotentFails`) whose entire job is to prove the detector isn't blind.
Not a scored benchmark — no frozen answer key.

Each mutant is a reversible patch (`patches/<id>.patch`). The runner applies one,
builds, runs its named killer test via `swift test --filter`, checks the outcome,
and reverts. SwiftPM targets test methods precisely, so a kill is attributed by
construction.

## Run

```sh
mutants/run-mutants.sh                       # all mutants
mutants/run-mutants.sh assert-property-runs-once
```

Requires a clean working tree.

## The corpus (`manifest.json`)

| id | shape | expected | killer |
|---|---|---|---|
| `assert-property-runs-once` | retry-value | killed | `nonIdempotentFails` |
| `effects-property-skips-retry` | retry-effect | killed | `nonEffectIdempotentFails` |
| `idempotencykey-derivation` | key-derivation | killed | `fromIdentifiableEntity_uuidID_producesStableRawValue` |

The first two attack the "run it twice" core of the property assertions — the exact
mechanism that makes them able to detect non-idempotence at all. If either mutant
survived, the assertion would pass on genuinely non-idempotent code (the detector
gone blind), which is precisely what the negative-control tests exist to forbid.
The third makes `IdempotencyKey` derive from the entity rather than its stable `id`.

## Adding a mutant

1. Make the buggy edit; 2. `git diff -- <file> > mutants/patches/<id>.patch`;
3. `git checkout -- <file>`; 4. add an entry to `manifest.json` (`test`, `shape`,
`expected`). Keep mutants realistic and diverse across shapes.
