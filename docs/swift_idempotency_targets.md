# Swift Idempotency Analysis Targets

## 🟢 Vapor ecosystem (richest target set)

### Core framework + infra (great for low-level idempotency patterns)
- vapor → https://github.com/vapor/vapor  
  - Large, production-grade framework with routing, middleware, async handling  
  - Has a **Tests/** directory—ideal for validating your detector  
- postgres-nio → https://github.com/vapor/postgres-nio  
  - Built on SwiftNIO; lots of async state transitions  
  - Good for catching **non-idempotent retries / connection reuse issues**

### ORM + templating + JWT
- Fluent (ORM)
- Leaf (templating)
- jwt-kit (crypto/auth)

👉 These are **excellent** because:
- ORMs often hide **implicit mutations**
- JWT/auth flows expose **idempotency bugs in middleware**

### Real apps / templates
- template-fluent-postgres-leaf  
- awesome-vapor → https://github.com/vapor-community/awesome-vapor  

👉 This list is probably your **best dataset entry point**.

---

## 🟡 Hummingbird ecosystem (cleaner, more minimal)

### Core framework
- hummingbird → https://github.com/hummingbird-project/hummingbird  
  - Built on SwiftNIO, minimal abstractions  
  - Easier to reason about idempotency (less magic)

### Example apps (high signal for analysis)
- hummingbird-examples → https://github.com/hummingbird-project/hummingbird-examples  
  Includes:
  - JWT auth
  - Cognito auth
  - GraphQL server
  - job queues

👉 These are perfect because:
- Small enough to analyze fully
- Still include **real-world patterns (auth, async jobs)**

---

## 🔵 SwiftNIO ecosystem (low-level, high value)

Good targets:
- swift-nio (core repo)
- Vapor’s NIO-based packages (like PostgresNIO above)
- hummingbird-core → https://github.com/hummingbird-project/hummingbird-core  

👉 Look for:
- Channel handlers
- retry logic
- buffering / backpressure

---

## 🟠 Production applications (real side effects) — top priority

Per `CLAUDE.md`'s Lambda "corpus caveat," demo/example corpora
(awslabs Lambda examples, hummingbird-examples, point-free docs)
produce low Run A yields because the handler bodies are deliberately
thin — logging + echo + one SDK read, with little business state to
mutate. For FP-rate evidence, a codebase with real business side
effects (DB writes, third-party API calls, message dispatches) is a
stronger target than more annotations on the demo corpora.

### Candidates

- **`vapor/penny-bot`** → https://github.com/vapor/penny-bot
  - SSWG Discord bot (the actual production one). AWS Lambda +
    SotoDynamoDB + Discord Gateway + GitHub webhooks. Real business
    workload: coin/reward tracking, PR notifications, FAQ/ping
    management, sponsor sync, OAuth callbacks.
  - Shape diversity: 8 discrete Lambda handlers under `Lambdas/`
    (`GHHooks`, `GHOAuth`, `Users`, `Faqs`, `AutoPings`, `AutoFaqs`,
    `Sponsors`, `GitHubAPI`) plus a long-running `Sources/Penny`
    service. Webhook-replayable, OAuth-callback, CRUD, scheduled
    sync all represented.
  - **Directly addresses the Lambda corpus caveat.** Reuses the
    slot-10 response-writer whitelist infrastructure, so the
    framework baseline is warm.

- **`FeatherCMS/feather`** → https://github.com/FeatherCMS/feather
  - Modern Vapor 4 CMS. DB writes + file uploads + admin flows.
  - **Caveat: last push 2023-05-29.** Not archived, but clearly
    unmaintained since Vapor 4 era. Verify Swift version / SPM
    resolves on current toolchain before committing to a round.
  - Worth holding as the "Vapor proper" fill-in (current Vapor
    coverage gap: `todos-fluent` was a toy, `pointfreeco` uses
    custom `HttpPipeline`) — but only if a lively alternative
    doesn't surface first.

---

## 🟣 Point-Free ecosystem (very interesting for semantics)

- swift-composable-architecture (TCA)
- swift-dependencies
- parsing
- snapshot-testing

Why these matter:
- Heavy use of **pure functions vs side effects**
- Clear separation of **effects**
- Good for testing:
  - reducer purity
  - effect re-execution
  - idempotent vs non-idempotent actions

---

## 🧠 Suggested dataset strategy

### Tier 1 (ground truth-ish)
- Point-Free repos (mostly intentional design)
- Small Hummingbird examples

### Tier 2 (real-world complexity)
- Vapor framework + Fluent + jwt-kit
- PostgresNIO

### Tier 3 (messy reality)
- Projects from Awesome Vapor list
- Random GitHub apps using Vapor

---

## ⚠️ Likely idempotency issues you'll find

- Non-idempotent HTTP handlers (POST reused as retry)
- Middleware with hidden mutation
- DB writes without deduplication
- Retry logic in NIO pipelines
- Auth/session side effects
- Task re-execution (async/await boundaries)
