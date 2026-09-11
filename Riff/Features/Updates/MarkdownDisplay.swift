import Foundation

// MarkdownUI displays raw HTML blocks as text. Hide HTML comments for reading,
// while keeping comment syntax visible inside Markdown code examples.
enum MarkdownDisplay {
    static func hidingComments(in source: String) -> String {
        var result: [String] = []
        var comment = false
        var inlineTicks = 0
        var fence: (character: Character, count: Int)?
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            let indentation = line.count - trimmed.count
            if let current = fence {
                result.append(line)
                let count = trimmed.prefix(while: { $0 == current.character }).count
                if indentation <= 3 && count >= current.count && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                continue
            }
            if !comment && inlineTicks == 0 {
                if indentation >= 4 || line.hasPrefix("\t") { result.append(line); continue }
                if let first = trimmed.first, first == "`" || first == "~" {
                    let count = trimmed.prefix(while: { $0 == first }).count
                    if count >= 3 { fence = (first, count); result.append(line); continue }
                }
            }
            var visible = ""
            var cursor = line.startIndex
            while cursor < line.endIndex {
                if comment {
                    if let end = line.range(of: "-->", range: cursor..<line.endIndex) { comment = false; cursor = end.upperBound }
                    else { cursor = line.endIndex }
                } else if line[cursor] == "\\" && inlineTicks == 0 {
                    visible.append(line[cursor]); cursor = line.index(after: cursor)
                    if cursor < line.endIndex { visible.append(line[cursor]); cursor = line.index(after: cursor) }
                } else if line[cursor] == "`" {
                    let run = line[cursor...].prefix(while: { $0 == "`" })
                    if inlineTicks == 0 { inlineTicks = run.count }
                    else if inlineTicks == run.count { inlineTicks = 0 }
                    visible += run; cursor = line.index(cursor, offsetBy: run.count)
                } else if inlineTicks == 0 && line[cursor...].hasPrefix("<!--") {
                    comment = true; cursor = line.index(cursor, offsetBy: 4)
                } else {
                    visible.append(line[cursor]); cursor = line.index(after: cursor)
                }
            }
            result.append(visible)
        }
        return result.joined(separator: "\n")
    }
}
