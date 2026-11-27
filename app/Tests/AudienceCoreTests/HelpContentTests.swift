import Foundation
import Testing
@testable import AudienceCore

struct HelpContentTests {
    @Test(arguments: [HelpPlatform.mac, .iPad])
    func everyTopicIsComplete(platform: HelpPlatform) {
        let topics = HelpContent.topics(for: platform)
        #expect(topics.count >= 10)
        #expect(Set(topics.map(\.id)).count == topics.count)
        for topic in topics {
            #expect(!topic.title.isEmpty && !topic.symbol.isEmpty && !topic.blocks.isEmpty, "\(topic.id)")
        }
    }

    /// Each platform names its own gestures: the Mac has menus and shortcuts, the iPad has touch gestures.
    @Test func textFollowsThePlatform() {
        let mac = HelpContent.topics(for: .mac).map(\.searchableText).joined()
        let iPad = HelpContent.topics(for: .iPad).map(\.searchableText).joined()
        #expect(mac.contains("⌥⌘P") && !iPad.contains("⌥⌘P"))
        #expect(iPad.contains("Tirez la liste") && !mac.contains("Tirez la liste"))
        #expect(mac.contains("1. Service") && iPad.contains("1. Service"))
        #expect(HelpContent.topics(for: .mac).map(\.id) == HelpContent.topics(for: .iPad).map(\.id))
    }

    /// The example the help lets people copy is what they paste into the import window.
    @Test func offeredExampleImports() throws {
        for platform in [HelpPlatform.mac, .iPad] {
            let examples = HelpContent.topics(for: platform).flatMap(\.blocks).compactMap { block -> String? in
                if case .example(_, let code) = block { code } else { nil }
            }
            #expect(examples.count == 1)
            #expect(try QuizMarkdown.parse(#require(examples.first)).questions.count == 13)
        }
    }

    @Test func searchFindsTextInsideBlocks() {
        let topics = HelpContent.topics(for: .mac)
        #expect(topics.contains { $0.searchableText.localizedStandardContains("nuage de mots") })
        #expect(topics.contains { $0.searchableText.localizedStandardContains("corbeille") })
    }
}
