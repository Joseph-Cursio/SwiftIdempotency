import Foundation

/// Finding citations in the tree, resolving them, and reading their recovery annotations.
extension DocCitationTests {
    // MARK: - Scanning

    static func scan() throws -> [Citation] {
        var found: [Citation] = []
        for file in try scannedFiles() {
            let text = try String(contentsOf: URL(fileURLWithPath: absolute(file)), encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            let markerShas = prunedMarkerShas(in: text)

            for (offset, line) in lines.enumerated() {
                for path in paths(in: line, isMarkdown: file.hasSuffix(".md")) {
                    if resolves(path, citedBy: file) {
                        found.append(
                            Citation(
                                path: path, file: file, line: offset + 1,
                                exemption: nil, resolved: true, recoveryShas: []
                            )
                        )
                        continue
                    }

                    let nearby = pointerShas(around: offset, in: lines)
                    let exemption: Exemption?
                    let shas: [String]

                    if !nearby.isEmpty {
                        (exemption, shas) = (.recoveryPointer, nearby)
                    } else if !markerShas.isEmpty {
                        (exemption, shas) = (.prunedMarker, markerShas)
                    } else if isSiblingRooted(path) {
                        (exemption, shas) = (.siblingNotCheckedOut, [])
                    } else if isExternalPackageDocument(file) {
                        (exemption, shas) = (.externalPackage, [])
                    } else if historyDocuments.contains(file) {
                        (exemption, shas) = (.history, [])
                    } else {
                        (exemption, shas) = (nil, [])
                    }

                    found.append(
                        Citation(
                            path: path, file: file, line: offset + 1,
                            exemption: exemption, resolved: false, recoveryShas: shas
                        )
                    )
                }
            }
        }
        return found
    }

    /// Backticked paths, plus markdown link targets. A citation must contain a `/`:
    /// a bare `Effect.swift` names a *file* in running prose, not a location, and
    /// checking it for existence asks a question the author did not ask.
    static func paths(in line: String, isMarkdown: Bool) -> [String] {
        var results: [String] = []

        for match in line.ranges(between: "`") {
            let candidate = String(line[match])
            if isPathLike(candidate) { results.append(candidate) }
        }

        if isMarkdown {
            for target in line.markdownLinkTargets() where isPathLike(target) {
                results.append(target)
            }
        }

        return results
    }

    static func isPathLike(_ candidate: String) -> Bool {
        guard candidate.contains("/") else { return false }
        // A recovery pointer *contains* a dead path by construction. Reading it as a
        // citation would fail every annotation written to satisfy this check.
        guard !candidate.contains("git show"), !candidate.contains(":") else { return false }
        // Elisions (`Sources/…/Internal/x.swift`) and globs name a set, not a file.
        guard !candidate.contains("…"), !candidate.contains("*"),
              !candidate.contains("<"), !candidate.contains("{")
        else { return false }
        guard !candidate.hasPrefix("http://"), !candidate.hasPrefix("https://") else { return false }
        // Dotfile *directories* (`.swiftinfer/index.json`) are artefacts a tool writes
        // at runtime, described here rather than committed. `./` and `../` are real.
        if candidate.hasPrefix("."), !candidate.hasPrefix("./"), !candidate.hasPrefix("../") {
            return false
        }
        let stripped = candidate.split(separator: "#").first.map(String.init) ?? candidate
        return citationExtensions.contains { stripped.hasSuffix(".\($0)") }
    }

    // MARK: - Resolution

    static func resolves(_ path: String, citedBy file: String) -> Bool {
        var bare = path.split(separator: "#").first.map(String.init) ?? path
        if bare.hasPrefix(ownRepository + "/") {
            bare = String(bare.dropFirst(ownRepository.count + 1))
        }
        if FileManager.default.fileExists(atPath: absolute(bare)) { return true }

        let joined = file.parentPath.joiningPath(bare)
        if FileManager.default.fileExists(atPath: absolute(joined)) {
            return true
        }

        guard let head = bare.split(separator: "/").first.map(String.init),
              siblingRepositories.contains(head)
        else { return false }

        let sibling = repositoryRoot.deletingLastPathComponent().path.joiningPath(bare)
        return FileManager.default.fileExists(atPath: sibling)
    }

    static func isSiblingRooted(_ path: String) -> Bool {
        guard let head = path.split(separator: "/").first.map(String.init) else { return false }
        return siblingRepositories.contains(head)
    }

    static func isExternalPackageDocument(_ file: String) -> Bool {
        if externalPackageDocuments.contains(file) { return true }
        let parts = file.split(separator: "/").map(String.init)
        guard parts.count > 2, parts[0] == "docs" else { return false }
        return !sharedDocsDirectories.contains(parts[1])
    }

    // MARK: - Recovery annotations

    /// `git show <sha>^:` / `<sha>~2:` / `<sha>:` — the shas offered as a way to read
    /// a path that is gone. A doc comment wraps, so the window looks either side.
    static func pointerShas(around index: Int, in lines: [String]) -> [String] {
        let lower = max(0, index - pointerWindow)
        let upper = min(lines.count - 1, index + pointerWindow)
        guard lower <= upper else { return [] }
        return lines[lower...upper].flatMap { $0.gitShowShas() }
    }

    static func prunedMarkerShas(in text: String) -> [String] {
        guard let range = text.range(of: "<!-- pruned-docs:"),
              let end = text.range(of: "-->", range: range.upperBound..<text.endIndex)
        else { return [] }
        return text[range.upperBound..<end.lowerBound]
            .split { $0 == " " || $0 == "\n" }
            .map(String.init)
            .filter { $0.count >= 7 && $0.allSatisfy(\.isHexDigit) }
    }

    static func filesDeclaringPrunedMarker() throws -> [String] {
        try scannedFiles().filter { file in
            guard let text = try? String(
                contentsOf: URL(fileURLWithPath: absolute(file)), encoding: .utf8
            ) else { return false }
            return !prunedMarkerShas(in: text).isEmpty
        }
    }
}
