import Testing
@testable import AudienceCore

struct RichTextTests {
    @Test func markdownBecomesTheWebsiteHTML() {
        #expect(RichText.html(fromMarkdown: "Dans *Le Médecin malgré lui*, qui est **Sganarelle** ?")
                == "Dans <em>Le Médecin malgré lui</em>, qui est <strong>Sganarelle</strong> ?")
        #expect(RichText.html(fromMarkdown: "_italique_ et __gras__ et <u>souligné</u>")
                == "<em>italique</em> et <strong>gras</strong> et <u>souligné</u>")
        #expect(RichText.html(fromMarkdown: "Classe :\n- Molière\n- Racine\n\nPuis justifie.")
                == "<p>Classe :</p><ul><li>Molière</li><li>Racine</li></ul><p>Puis justifie.</p>")
    }
    @Test func plainStatementsKeepTheirFormerForm() {
        // Same output as the former htmlEscaped, so unformatted statements are not rewritten.
        #expect(RichText.html(fromMarkdown: "l'origine & 3 < 5\nsuite") == "l'origine &amp; 3 &lt; 5<br>suite")
        #expect(RichText.html(fromMarkdown: "Quelle est ") == "Quelle est ")
    }
    @Test func asterisksAndUnderscoresThatAreNotEmphasisStayText() {
        for text in ["Calcule 2*3*4.", "2 * 3 * 4", "nom_de_variable", "Le chat ______ la souris.", "Un seul * ici", "x_1 + x_2", "\\*pas en italique\\*"] {
            #expect(!RichText.html(fromMarkdown: text).contains("<em>"), "\(text)")
            #expect(!RichText.html(fromMarkdown: text).contains("<strong>"), "\(text)")
        }
        #expect(RichText.html(fromMarkdown: "\\*pas en italique\\*") == "*pas en italique*")
    }
    @Test func websiteHTMLIsEditedAsMarkdown() {
        #expect(RichText.markdown(fromHTML: "Dans <em>Le Médecin malgré lui</em>, Martine traite Sganarelle de « sac à vin ».")
                == "Dans *Le Médecin malgré lui*, Martine traite Sganarelle de « sac à vin ».")
        #expect(RichText.markdown(fromHTML: "<p><strong>Vrai </strong>ou faux ?</p>") == "**Vrai** ou faux ?")
        #expect(RichText.markdown(fromHTML: "<p>Classe :</p><ul><li>Molière</li><li>Racine</li></ul>") == "Classe :\n\n- Molière\n- Racine")
        // Nested escapes of old saves are repaired.
        #expect(RichText.markdown(fromHTML: "Dans l&amp;#39;extrait de *Cendrillon*") == "Dans l'extrait de *Cendrillon*")
    }
    @Test func markdownStoredByImportsIsSentAsHTML() {
        #expect(RichText.normalized("Quelle est la quête de la Belle dans *La Belle et la Bête* ?")
                == "Quelle est la quête de la Belle dans <em>La Belle et la Bête</em> ?")
        // Statements without Markdown are sent exactly as before.
        let html = "<p>Dans <em>Le Médecin malgré lui</em>, qui parle ?</p>"
        #expect(RichText.normalized(html) == html)
        #expect(RichText.normalized("Calcule 2*3*4.") == "Calcule 2*3*4.")
    }
    @Test func runsCarryTheFormattingForDisplay() {
        #expect(RichText.runs("Dans l&amp;#39;extrait de *Cendrillon*, qui aide ?") == [
            .init("Dans l'extrait de "), .init("Cendrillon", italic: true), .init(", qui aide ?")
        ])
        #expect(RichText.runs("<p>Classe :</p><ul><li><strong>Molière</strong></li><li>Racine</li></ul>") == [
            .init("Classe :\n\n• "), .init("Molière", bold: true), .init("\n• Racine")
        ])
        #expect(RichText.runs("<p>Un</p><p>Deux<br>trois</p>") == [.init("Un\n\nDeux\ntrois")])
        #expect(RichText.plainText("Le mot vient du latin *mirabilia*.") == "Le mot vient du latin mirabilia.")
        #expect(RichText.runs("").isEmpty)
    }
    @Test func editingRoundTripKeepsTheStatement() {
        for markdown in ["Dans *Le Médecin malgré lui*, qui est **Sganarelle** ?", "Classe :\n\n- Molière\n- Racine",
                         "Ligne un\nLigne deux", "<u>Souligné</u> puis texte"] {
            #expect(RichText.markdown(fromHTML: RichText.html(fromMarkdown: markdown)) == markdown)
        }
    }
    @Test func answersShowInlineEmphasisOnly() {
        #expect(RichText.answerRuns("Tu t&#39;ennuies. (*s&#39;ennuyer*)") == [
            .init("Tu t'ennuies. ("), .init("s'ennuyer", italic: true), .init(")")
        ])
        #expect(RichText.answerPlainText("Je paie. (*payer*)") == "Je paie. (payer)")
        #expect(RichText.answerIsFormatted("**Oui**") && !RichText.answerIsFormatted("2*3*4"))
        #expect(RichText.answerRuns("- 3") == [.init("- 3")])
        #expect(RichText.answerRuns("a &lt; b &amp; c") == [.init("a < b & c")])
    }
}
