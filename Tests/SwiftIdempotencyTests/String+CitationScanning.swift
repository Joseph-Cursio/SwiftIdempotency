/// Line-scanning and path helpers for ``DocCitationTests``.
extension String {
    /// The path without its last component, or `""` for a bare file name.
    var parentPath: String {
        guard let slash = lastIndex(of: "/") else { return "" }
        return String(self[..<slash])
    }

    /// `component` appended to this path with one `/`, or `component` alone when
    /// this path is empty.
    func joiningPath(_ component: String) -> String {
        if isEmpty { return component }
        return hasSuffix("/") ? self + component : self + "/" + component
    }

    /// Ranges of text between paired occurrences of `delimiter`.
    func ranges(between delimiter: Character) -> [Range<String.Index>] {
        var results: [Range<String.Index>] = []
        var opening: String.Index?
        for index in indices where self[index] == delimiter {
            if let start = opening {
                results.append(self.index(after: start)..<index)
                opening = nil
            } else {
                opening = index
            }
        }
        return results
    }

    /// Targets of `[text](target)`, ignoring any `#fragment`.
    func markdownLinkTargets() -> [String] {
        var results: [String] = []
        var search = startIndex
        while let open = range(of: "](", range: search..<endIndex) {
            guard let close = range(of: ")", range: open.upperBound..<endIndex) else { break }
            let target = String(self[open.upperBound..<close.lowerBound])
            if !target.contains(" ") { results.append(target) }
            search = close.upperBound
        }
        return results
    }

    /// Shas named in a `git show <sha>^:path` pointer on this line.
    func gitShowShas() -> [String] {
        var results: [String] = []
        var search = startIndex
        while let marker = range(of: "git show ", range: search..<endIndex) {
            let remainder = self[marker.upperBound...]
            let sha = remainder.prefix(while: \.isHexDigit)
            if sha.count >= 7 { results.append(String(sha)) }
            search = marker.upperBound
        }
        return results
    }
}
