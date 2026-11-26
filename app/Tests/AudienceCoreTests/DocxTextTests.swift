import Testing
import Foundation
@testable import AudienceCore

struct DocxTextTests {
    private let namespace = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""

    /// A .docx made with the system `zip`, like Word's own ZIP container.
    private func docx(body: String, extra: [String: Data] = [:]) throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docx-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("word/media"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("<?xml version=\"1.0\"?><w:document \(namespace)><w:body>\(body)</w:body></w:document>".utf8)
            .write(to: dir.appendingPathComponent("word/document.xml"))
        for (name, data) in extra { try data.write(to: dir.appendingPathComponent(name)) }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "-r", "-9", "out.docx", "word"]
        try zip.run(); zip.waitUntilExit()
        return try Data(contentsOf: dir.appendingPathComponent("out.docx"))
    }

    @Test func paragraphsKeepTheirTextAndOrder() throws {
        let data = try docx(body: """
            <w:p><w:r><w:t>Le passé simple</w:t></w:r></w:p>
            <w:p><w:r><w:t xml:space="preserve">Il </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>chanta</w:t></w:r><w:r><w:t>.</w:t></w:r></w:p>
            """)
        #expect(try DocxText.extract(from: data) == "Le passé simple\nIl chanta.")
    }

    @Test func headingsListsTabsAndBreaksAreKept() throws {
        let data = try docx(body: """
            <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Conjugaison</w:t></w:r></w:p>
            <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>chanter</w:t></w:r></w:p>
            <w:p><w:pPr><w:pStyle w:val="Titre1"/></w:pPr><w:r><w:t>Titre</w:t></w:r></w:p>
            <w:p><w:r><w:t>a</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>b</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>c</w:t></w:r></w:p>
            """)
        #expect(try DocxText.extract(from: data) == "## Conjugaison\n- chanter\n# Titre\na\tb\nc")
    }

    @Test func tablesBecomePipeSeparatedRows() throws {
        let cell = { (text: String) in "<w:tc><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc>" }
        let data = try docx(body: """
            <w:p><w:r><w:t>Avant</w:t></w:r></w:p>
            <w:tbl><w:tr>\(cell("Je"))\(cell("chantai"))</w:tr><w:tr>\(cell("Tu"))\(cell("chantas"))</w:tr></w:tbl>
            <w:p><w:r><w:t>Après</w:t></w:r></w:p>
            """)
        #expect(try DocxText.extract(from: data) == "Avant\nJe | chantai\nTu | chantas\nAprès")
    }

    @Test func deletedTextFieldsAndPicturesAreLeftOut() throws {
        let data = try docx(body: """
            <w:p><w:r><w:t>Gardé</w:t></w:r><w:del><w:r><w:delText>supprimé</w:delText></w:r></w:del>
            <w:r><w:instrText> PAGE </w:instrText></w:r></w:p>
            """, extra: ["word/media/photo.png": Data(repeating: 7, count: 4_000)])
        #expect(try DocxText.extract(from: data) == "Gardé")
    }

    @Test func blankParagraphsCollapseAndTheTextIsTrimmed() throws {
        let blank = "<w:p/>"
        let data = try docx(body: "\(blank)\(blank)<w:p><w:r><w:t>Un</w:t></w:r></w:p>\(blank)\(blank)\(blank)\(blank)<w:p><w:r><w:t>Deux</w:t></w:r></w:p>\(blank)")
        #expect(try DocxText.extract(from: data) == "Un\n\nDeux")
    }

    @Test func otherFilesAreRefusedWithAClearMessage() throws {
        #expect(throws: AudienceError.self) { try DocxText.extract(from: Data("pas un zip".utf8)) }
        // A valid ZIP without word/document.xml, such as a questionnaire archive.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docx-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("# Titre".utf8).write(to: dir.appendingPathComponent("a.md"))
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "x.zip", "a.md"]
        try zip.run(); zip.waitUntilExit()
        let archive = try Data(contentsOf: dir.appendingPathComponent("x.zip"))
        #expect(throws: AudienceError.self) { try DocxText.extract(from: archive) }
    }

    @Test func readsADocumentWrittenByARealWordProcessor() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docx-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("""
            <html><head><meta charset="utf-8"></head><body><h1>Le passé simple</h1><p>Intro avec du <b>gras</b> et des accents : é à ç.</p>
            <ul><li>chanter</li><li>finir</li></ul>
            <table><tr><td>Je</td><td>chantai</td></tr><tr><td>Tu</td><td>chantas</td></tr></table></body></html>
            """.utf8).write(to: dir.appendingPathComponent("cours.html"))
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        convert.currentDirectoryURL = dir
        convert.arguments = ["-convert", "docx", "cours.html"]
        try convert.run(); convert.waitUntilExit()
        let text = try DocxText.extract(from: Data(contentsOf: dir.appendingPathComponent("cours.docx")))
        // textutil writes the table cells as plain paragraphs; real tables are covered by the hand-made file above.
        let order = ["Le passé simple", "Intro avec du gras et des accents : é à ç.", "chanter", "finir", "Je", "chantai", "Tu", "chantas"]
        var position = text.startIndex
        for fragment in order {
            let found = try #require(text.range(of: fragment, range: position..<text.endIndex), "\(fragment) dans :\n\(text)")
            position = found.upperBound
        }
    }
}
