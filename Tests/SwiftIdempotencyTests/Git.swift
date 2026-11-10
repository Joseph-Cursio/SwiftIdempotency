import Foundation

/// Asks git whether a recovery pointer really recovers its path.
enum Git {
    /// Can `path` be read at `sha`? Answered by running the command a reader would
    /// run, because the point of a recovery pointer is that it works when pasted.
    static func canRead(_ path: String, citedBy file: String, at sha: String) -> Bool {
        // A citation is written from where it sits, but `git show` wants the path as
        // the repository spells it. Resolve the relative form against the citing
        // document first; fall back to the literal, for a path already written whole.
        let candidates = [
            collapse(file.parentPath.joiningPath(path)),
            collapse(path),
            path,
        ]

        return candidates.contains { candidate in
            run(["show", "\(sha)^:\(candidate)"]) || run(["show", "\(sha):\(candidate)"])
        }
    }

    /// `NSString.standardizingPath` leaves `..` in place for a *relative* path — it
    /// cannot know whether a component is a symlink, so it declines to guess. Here
    /// the components are repository paths, where the textual answer is the right
    /// one, and without collapsing them every pointer is handed to `git show`
    /// unresolved and reads as broken.
    private static func collapse(_ path: String) -> String {
        var stack: [String] = []
        for component in path.split(separator: "/").map(String.init) {
            switch component {
            case ".": continue
            case ".." where !stack.isEmpty && stack.last != "..": stack.removeLast()
            default: stack.append(component)
            }
        }
        return stack.joined(separator: "/")
    }

    private static func run(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = DocCitationTests.repositoryRoot
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
