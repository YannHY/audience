import Foundation

/// Normalizes shared YouTube links before loading them in the presentation player.
public struct YouTubeVideo: Equatable, Sendable {
    public let id: String
    public let start: Int
    public let end: Int?

    public init?(url input: String, start: Int = 0, end: Int = 0) {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func isID(_ value: String) -> Bool {
            value.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil
        }
        var candidate = input
        if !isID(candidate) {
            let address = input.contains("://") ? input : "https://\(input)"
            guard let url = URLComponents(string: address),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host?.lowercased() else { return nil }
            let path = url.path.split(separator: "/").map(String.init)
            if ["youtu.be", "www.youtu.be"].contains(host) {
                candidate = path.first ?? ""
            } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
                       "youtube-nocookie.com", "www.youtube-nocookie.com"].contains(host) {
                if path == ["watch"] {
                    candidate = url.queryItems?.first(where: { $0.name == "v" })?.value ?? ""
                } else if path.count == 2, ["embed", "shorts", "live"].contains(path[0]) {
                    candidate = path[1]
                } else { return nil }
            } else { return nil }
        }
        guard isID(candidate) else { return nil }
        self.id = candidate
        self.start = min(max(start, 0), 43_200)
        let end = min(max(end, 0), 43_200)
        self.end = end > self.start ? end : nil
    }

    public var embedURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/embed/\(id)"
        components.queryItems = [URLQueryItem(name: "playsinline", value: "1"), URLQueryItem(name: "rel", value: "0")]
        if start > 0 { components.queryItems?.append(URLQueryItem(name: "start", value: "\(start)")) }
        if let end { components.queryItems?.append(URLQueryItem(name: "end", value: "\(end)")) }
        return components.url!
    }

    public var watchURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: id)]
        if start > 0 { components.queryItems?.append(URLQueryItem(name: "t", value: "\(start)s")) }
        return components.url!
    }
}
