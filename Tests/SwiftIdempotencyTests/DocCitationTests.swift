import Foundation
import Testing

/// Every path this repo names in prose resolves — or says how to read it.
///
/// ## Why this exists
///
/// Three separate repairs to cross-repo citations shipped here (#6, #7, #8) before
/// anyone noticed they were being made in a **read-only copy** that the next
/// re-import would discard. The sweep that replaced them (#9) then left residue of
/// its own, because the scanner driving it keyed on a hand-written list of
/// directory names and `fixtures/` was not on it. A citation check that runs once,
/// by hand, finds what the person running it thought to look for.
///
/// The population that motivated this is not prose at all: **six doc comments in
/// shipped `Sources/` and `Tests/`** pointed at round documents pruned months
/// earlier. An adopter reading `@Idempotent`'s documentation was sent to a file
/// that had not existed since `92d1363`.
///
/// ## What counts as resolving
///
/// A citation is fine when it resolves against the repo root, or relative to the
/// document making it, or — for a path led by a sibling checkout's name — inside
/// that sibling. Sibling paths are only *existence*-checked when the sibling is
/// actually checked out beside this repo; their shape is checked always, so a typo
/// in the repo name fails everywhere while a missing checkout fails nowhere.
///
/// ## The exemptions are the design, and each is verified rather than trusted
///
/// A path that no longer exists is not automatically wrong. Records of a moment are
/// full of correct references to things since deleted, and repointing them makes the
/// record wrong. So five exemptions, none of them a bare allowlist:
///
/// 1. **A recovery pointer nearby** — `git show <sha>^:<path>` within
///    ``pointerWindow`` lines, because a doc comment wraps and the pointer for a path
///    named on one line lands on the next. The dead path must be readable at that
///    commit, so a typo cannot hide behind a pointer that merely looks official.
/// 2. **A document-level marker** — `<!-- pruned-docs: <sha> … -->`, for a document
///    like the PRD that cites twenty pruned rounds and would drown in per-line
///    pointers. Verified identically: every dead path in that file must be readable
///    at one of the shas it declares. This is *not* a file-level mute — a path that
///    never existed still fails, because it is recoverable nowhere.
/// 3. **A named repo that is not checked out** — `penny-bot/Lambdas/…`. Naming the
///    repo is what makes the path readable at all; a typo in the name still fails,
///    which is the whole reason the set is written down.
/// 4. **External-package documents** — ``externalPackageDocuments`` and the
///    per-adopter `docs/<adopter>/` write-ups describe someone else's tree.
///    `TUTORIAL.md` names files the reader is being told to create.
/// 5. **History** — ``historyDocuments``, retrospectives that cite what they cited.
///
/// One limit, stated rather than hidden: a recovery pointer for a *sibling's* file
/// names that repo's history, which cannot be read from this checkout. Those are
/// checked for shape only — asserting more would make the suite pass or fail on
/// whether someone happened to clone a neighbour.
///
/// ## The guards are guarded
///
/// Every exemption narrows the population, so every one can hide the thing it was
/// meant to permit. ``prunedMarkersAreStillEarningTheirPlace()`` fails a marker that
/// no longer covers any dead path; ``exemptedDocumentsStillExist()`` fails a listed
/// document that has moved; ``recoveryPointersActuallyRecover()`` runs the command a
/// reader would paste; and ``theScanReachesAPlausiblePopulation()`` asserts the
/// denominator, so a scoping bug cannot make "found nothing wrong" and "looked at
/// nothing" the same green.
///
/// Verified by planting each failure in turn — an unannotated dead path, a pointer
/// naming a commit that never had the file, and a marker covering nothing — and
/// confirming all three are caught.
@Suite("Doc citations — every path this repo names resolves, or says how to read it")
struct DocCitationTests {
    // MARK: - Tests

    @Test("no citation names a path that does not exist")
    func citationsResolve() throws {
        let unresolved = try Self.scan().filter(\.isProblem)

        #expect(
            unresolved.isEmpty,
            """
            These citations name a path that does not resolve. Either fix the path, or \
            — if it was deliberately pruned — pair it with a recovery pointer on the same \
            line or within \(Self.pointerWindow), e.g. "(pruned in `abc1234`; recover with \
            git show <sha>^:<the path>)". A document citing many pruned paths can \
            declare them once with a `pruned-docs` marker instead. If it lives in \
            a sibling checkout, write the repo into the path: SwiftProjectLint + the path:
            \(Self.render(unresolved))
            """
        )
    }

    /// A marker that covers nothing protects nothing, while reading in the diff as a
    /// deliberate decision. The same argument the pruning commits themselves make.
    @Test("every `pruned-docs` marker still covers a dead path")
    func prunedMarkersAreStillEarningTheirPlace() throws {
        let citations = try Self.scan()
        let earning = Set(
            citations.filter { $0.exemption == .prunedMarker }.map(\.file)
        )

        let idle = try Self.filesDeclaringPrunedMarker().filter { !earning.contains($0) }

        #expect(
            idle.isEmpty,
            """
            These files declare `<!-- pruned-docs: … -->` but no longer cite any pruned \
            path — the citations were fixed and the marker outlived them. Drop it; it \
            silences nothing today and will silence the next real break:
            \(idle.sorted().joined(separator: "\n"))
            """
        )
    }

    /// The expensive failure is a pointer that looks official and resolves to nothing.
    /// Every sha named as a recovery route is executed against the path it claims.
    @Test("every recovery pointer names a commit the path can actually be read at")
    func recoveryPointersActuallyRecover() throws {
        // A pointer for a sibling's file names that repo's history, which cannot be
        // read from this checkout and should not be asserted on — it would pass or
        // fail on whether someone happened to clone a neighbour. Shape only, there.
        let claimed = try Self.scan().filter {
            ($0.exemption == .recoveryPointer || $0.exemption == .prunedMarker)
                && !Self.isSiblingRooted($0.path)
        }

        #expect(!claimed.isEmpty, "no recovery-exempt citations found — check the scanner")

        let broken = claimed.filter { citation in
            !citation.recoveryShas.contains {
                Git.canRead(citation.path, citedBy: citation.file, at: $0)
            }
        }

        #expect(
            broken.isEmpty,
            """
            These citations are exempted by a recovery pointer or a `pruned-docs` marker, \
            but the path cannot be read at any commit they name. The exemption is \
            therefore describing a file that was never there:
            \(Self.render(broken))
            """
        )
    }

    /// An exemption naming a file that has moved exempts nothing, while reading in
    /// the diff as a decision someone made on purpose.
    @Test("every exempted document still exists")
    func exemptedDocumentsStillExist() throws {
        let missing = (Self.externalPackageDocuments.union(Self.historyDocuments))
            .filter { !FileManager.default.fileExists(atPath: Self.absolute($0)) }

        #expect(
            missing.isEmpty,
            """
            These are exempted from citation checking but are not in the tree. Drop the \
            entry — it protects nothing and hides the next file that moves into its place:
            \(missing.sorted().joined(separator: "\n"))
            """
        )
    }

    /// Every exemption above narrows what is looked at. This asserts what remains.
    @Test("the scan reaches a plausible population")
    func theScanReachesAPlausiblePopulation() throws {
        let citations = try Self.scan()
        let files = Set(citations.map(\.file))

        // Floors are a smoke alarm for a scoping bug, not a metric to maintain. Measured
        // at 421 citations across 109 files on 2026-08-12, and set at roughly half that
        // — low enough that ordinary pruning never trips it, high enough that a walk
        // which silently stops descending does. If a real consolidation drops below,
        // lower them *after* confirming every root below is still reached.
        #expect(citations.count >= 200, "only \(citations.count) citations found")
        #expect(files.count >= 50, "only \(files.count) files contributed a citation")

        for root in ["docs/design-internal/", "docs/ideas/", "Sources/", "Tests/"] {
            #expect(
                files.contains { $0.hasPrefix(root) },
                "\(root) contributed no citations at all — check the walk"
            )
        }
    }

    // MARK: - What a citation is

    enum Exemption: Equatable {
        case recoveryPointer
        case prunedMarker
        case externalPackage
        case history
        case siblingNotCheckedOut
    }

    struct Citation {
        let path: String
        let file: String
        let line: Int
        /// Nil when the path resolves; otherwise why it is allowed not to.
        let exemption: Exemption?
        let resolved: Bool
        /// Commits this citation claims the path can be recovered at.
        let recoveryShas: [String]

        var isProblem: Bool { !resolved && exemption == nil }
    }

    // MARK: - Configuration

    /// How far from a citation a recovery pointer may sit and still cover it.
    /// Doc comments wrap, so a pointer for a path named on one line routinely lands
    /// on the next. Wide enough for a wrapped sentence, narrow enough that a pointer
    /// cannot reach across a paragraph to launder an unrelated path.
    static let pointerWindow = 5

    /// Sibling checkouts this repo's docs are allowed to name. A path led by one of
    /// these is well-formed wherever it is read; whether it *resolves* is only asked
    /// when that sibling is checked out beside this repo.
    static let siblingRepositories: Set<String> = [
        // The toolchain, checked out beside this repo.
        "SwiftInferProperties", "SwiftProjectLint", "SwiftEffectInference",
        "SwiftPropertyLaws", "swift-property-based",
        // Adopters named by trial write-ups and triage notes. Not checked out here
        // and not expected to be — naming the repo is what makes the path readable
        // at all, and a typo in the name still fails, which is the point.
        "vapor", "penny-bot", "pointfreeco", "swift-aws-lambda-runtime",
    ]

    /// This repo, named explicitly. `docs/design-internal/` is written in a sibling
    /// and copied here, so it spells out every repo including ours; the prefix is a
    /// path that resolves, not a foreign one.
    static let ownRepository = "swiftIdempotency"

    /// `docs/` children that are shared or meta rather than per-adopter. Everything
    /// else under `docs/` is a trial write-up, and a trial write-up naming a bare
    /// `Sources/…` means *the adopter's*, in a checkout this repo does not have.
    static let sharedDocsDirectories: Set<String> = [
        "design-internal", "ideas", "release-notes", "property-based",
    ]

    /// Documents that describe a package **other than this one**, so a bare
    /// `Sources/…` in them is a path in the reader's tree rather than ours.
    /// `TUTORIAL.md` walks the reader through building `PaymentTutorial` from
    /// scratch; the files it names are ones the reader is being told to create.
    /// Guarded by ``externalPackageDocumentsStillExist()`` — an entry naming a file
    /// that has moved exempts nothing while reading as a deliberate decision.
    static let externalPackageDocuments: Set<String> = ["TUTORIAL.md"]

    /// A record of a moment is allowed to cite what existed at that moment, and
    /// repointing it would make the record wrong. Same argument the pruning commits
    /// make about their own contents. Guarded the same way.
    static let historyDocuments: Set<String> = [
        "docs/retrospective-2026-04-24.md",
        "docs/retrospective-2026-05-04.md",
        "docs/retrospective-2026-05-05.md",
    ]

    static let citationExtensions = ["swift", "md", "json", "yml", "yaml", "toml"]

    // MARK: - The tree

    static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftIdempotencyTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }()

    static func absolute(_ path: String) -> String {
        repositoryRoot.path.joiningPath(path)
    }

    /// Markdown and Swift under the repo, minus build products. `examples/` holds
    /// real sample packages *and* their `.build` output; the latter is ~1,450
    /// markdown files of vendored dependency documentation, which would swamp the
    /// population floor above and make it meaningless.
    static func scannedFiles() throws -> [String] {
        var results: [String] = []
        let skipped = [".build", ".git", ".swiftpm", "node_modules"]
        let enumerator = FileManager.default.enumerator(
            at: repositoryRoot, includingPropertiesForKeys: nil
        )
        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent
            if skipped.contains(name) {
                enumerator?.skipDescendants()
                continue
            }
            guard ["md", "swift"].contains(url.pathExtension) else { continue }
            results.append(
                url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
            )
        }
        return results.sorted()
    }

    static func render(_ citations: [Citation]) -> String {
        citations
            .sorted { ($0.file, $0.line) < ($1.file, $1.line) }
            .map { "  \($0.file):\($0.line) — \($0.path)" }
            .joined(separator: "\n")
    }
}
