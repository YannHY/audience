import Foundation

/// Plain text of a Word document (.docx), so a lesson can be given to an assistant as it was written.
/// Headings become "#" lines, list items "- " lines, table rows " | "-separated lines. Pictures, headers,
/// footnotes and tracked deletions are left out. Nothing is evaluated: macros and links are never followed.
public enum DocxText {
    public static func extract(from data: Data) throws -> String {
        let unreadable = AudienceError.message("Ce fichier n’est pas un document Word (.docx) lisible.")
        let entries: [(name: String, data: Data)]
        do { entries = try ZipReader.entries(data) { $0 == "word/document.xml" } } catch { throw unreadable }
        guard let xml = entries.first?.data else { throw unreadable }
        let parser = XMLParser(data: xml)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        let reader = Reader()
        parser.delegate = reader
        guard parser.parse() else { throw AudienceError.message("Le contenu du document Word est illisible.") }
        return reader.text
    }

    private final class Reader: NSObject, XMLParserDelegate {
        private var lines: [String] = []
        private var cells: [[String]] = []   // paragraphs of each open table cell
        private var rows: [[String]] = []    // cells of each open table row
        private var paragraph = ""
        private var prefix = ""
        private var inText = false
        private var inParagraphProperties = false

        var text: String {
            lines.joined(separator: "\n")
                .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// A finished line goes to the open table cell, or to the document.
        private func emit(_ line: String) {
            if cells.isEmpty { lines.append(line) } else { cells[cells.count - 1].append(line) }
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            guard namespaceURI?.contains("wordprocessingml") == true else { return }
            switch name {
            case "p": paragraph = ""; prefix = ""
            case "pPr": inParagraphProperties = true
            case "numPr" where inParagraphProperties: prefix = "- "
            case "pStyle" where inParagraphProperties:
                if let style = attributes["w:val"] ?? attributes["val"],
                   let level = style.range(of: #"^(?:Heading|Titre)\s*([1-6])"#, options: [.regularExpression, .caseInsensitive])
                    .flatMap({ Int(style[$0].filter(\.isNumber)) }) {
                    prefix = String(repeating: "#", count: level) + " "
                }
            case "t": inText = true
            case "tab": paragraph += "\t"
            case "br", "cr": paragraph += "\n"
            case "noBreakHyphen": paragraph += "-"
            case "tr": rows.append([])
            case "tc": cells.append([])
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { paragraph += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard namespaceURI?.contains("wordprocessingml") == true else { return }
            switch name {
            case "t": inText = false
            case "pPr": inParagraphProperties = false
            case "p":
                let body = paragraph.trimmingCharacters(in: .whitespaces)
                emit(body.isEmpty ? "" : prefix + body)
                paragraph = ""; prefix = ""
            case "tc":
                let content = (cells.popLast() ?? []).filter { !$0.isEmpty }.joined(separator: " ")
                if !rows.isEmpty { rows[rows.count - 1].append(content) }
            case "tr":
                let row = (rows.popLast() ?? []).joined(separator: " | ")
                if !row.trimmingCharacters(in: CharacterSet(charactersIn: " |")).isEmpty { emit(row) }
            default: break
            }
        }
    }
}
