import Foundation
import Testing
@testable import AudienceCore

struct YouTubeVideoTests {
    @Test func sharedLinksLoadTheSameVideo() throws {
        for url in [
            "https://youtu.be/4oU1nmKDBtA?si=nOKPXLPZbucNM1NY",
            "https://www.youtube.com/watch?v=4oU1nmKDBtA&t=90s",
            "https://m.youtube.com/watch?v=4oU1nmKDBtA",
            "https://www.youtube.com/shorts/4oU1nmKDBtA",
            "https://www.youtube.com/live/4oU1nmKDBtA",
            "https://www.youtube-nocookie.com/embed/4oU1nmKDBtA",
            "  youtu.be/4oU1nmKDBtA  ", "4oU1nmKDBtA"
        ] {
            let video = try #require(YouTubeVideo(url: url, start: 15, end: 45))
            #expect(video.id == "4oU1nmKDBtA")
            let embed = try #require(URLComponents(url: video.embedURL, resolvingAgainstBaseURL: false))
            #expect(embed.host == "www.youtube.com" && embed.path == "/embed/4oU1nmKDBtA")
            #expect(embed.queryItems?.contains(URLQueryItem(name: "start", value: "15")) == true)
            #expect(embed.queryItems?.contains(URLQueryItem(name: "end", value: "45")) == true)
            #expect(!video.embedURL.absoluteString.contains("si="))
            #expect(video.watchURL.absoluteString.contains("t=15s"))
        }
    }

    @Test func invalidAndUnrelatedAddressesAreRejected() {
        for url in ["", "https://youtube.com", "https://youtube.com/playlist?list=4oU1nmKDBtA",
                    "https://example.com/watch?v=4oU1nmKDBtA", "https://youtube.com.evil.test/watch?v=4oU1nmKDBtA",
                    "https://youtu.be/abc", "https://youtube.com/watch?v=4oU1nmKDBtA%22%3E",
                    "file://youtube.com/embed/4oU1nmKDBtA"] {
            #expect(YouTubeVideo(url: url) == nil)
        }
    }

    @Test func videoBoundsUseQuestionSettings() throws {
        for (start, end, expectedStart, expectedEnd) in [(0, 0, 0, nil), (-5, -1, 0, nil),
                                                       (30, 15, 30, nil), (30, 30, 30, nil),
                                                       (0, 45, 0, 45), (90_000, 99_000, 43_200, nil)] as [(Int, Int, Int, Int?)] {
            let video = try #require(YouTubeVideo(url: "https://youtu.be/4oU1nmKDBtA?t=999", start: start, end: end))
            #expect(video.start == expectedStart && video.end == expectedEnd)
            if expectedStart == 0 { #expect(!video.embedURL.absoluteString.contains("start=")) }
            if expectedEnd == nil { #expect(!video.embedURL.absoluteString.contains("end=")) }
        }
    }
}
