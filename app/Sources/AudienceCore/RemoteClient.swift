import Foundation
import CryptoKit

/// A private, in-memory cookie jar. Passwords and session cookies are never persisted.
public actor RemoteClient: SyncRemote, OrganizationRemote {
    public static let siteURL = URL(string: "https://www.ralentirtravaux.com/apps/audience/")!
    /// Same link as the website's QR code: r.html reads the session code from `c`.
    public static func participantURL(code: String, site: URL = siteURL) -> URL? {
        guard var url = URLComponents(url: site.appending(path: "r.html"), resolvingAgainstBaseURL: false) else { return nil }
        url.queryItems = [URLQueryItem(name: "c", value: code)]
        return url.url
    }
    private var base: URL?
    private var session: URLSession?
    private var identity: String?
    private var folders: [RemoteFolder]?
    private var termsAccepted = true
    private let configurationFactory: @Sendable () -> URLSessionConfiguration

    public init() { configurationFactory = Self.sessionConfiguration }
    init(configurationFactory: @escaping @Sendable () -> URLSessionConfiguration) {
        self.configurationFactory = configurationFactory
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        // Keep the private storage provided by .ephemeral. HTTPCookieStorage()
        // creates a nonfunctional store on macOS and silently drops PHPSESSID.
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 25
        return configuration
    }

    public func connect(address: String, email: String, password: String) async throws -> String {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address.hasSuffix("/") ? address : address + "/"),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            throw AudienceError.message("Saisissez l’adresse HTTPS du dossier Audience.")
        }
        disconnect()
        session = URLSession(configuration: configurationFactory())
        base = url
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "email", value: email.trimmingCharacters(in: .whitespacesAndNewlines)), URLQueryItem(name: "password", value: password)]
        let body = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        do {
            let login = try await request("login.php", body: body, contentType: "application/x-www-form-urlencoded", json: false)
            // PHP returns HTTP 200 with the login form for invalid credentials.
            // Show its explicit error instead of blaming credentials for every failure.
            if let error = Self.loginError(in: login.string) { throw AudienceError.rejectedCredentials(error) }
            let me = try await request("auth_me.php")
            let user = me["user"]
            // Older sites do not send the field: only an explicit false asks for acceptance.
            termsAccepted = user["termsAccepted"] != .bool(false)
            let key = user["id"].int > 0 ? String(user["id"].int) : email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            identity = SHA256.hash(data: Data("\(url.absoluteString)|\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
            return me["user"]["username"].string
        } catch {
            disconnect()
            throw error
        }
    }
    public func accountIdentity() throws -> String {
        guard let identity else { throw AudienceError.message("Connectez-vous à votre compte Audience.") }; return identity
    }
    public func disconnect() { session?.invalidateAndCancel(); session = nil; base = nil; identity = nil; folders = nil; termsAccepted = true }
    /// True when the signed-in account has not yet accepted the website's terms of use.
    public func needsTermsAcceptance() -> Bool { identity != nil && !termsAccepted }
    /// Records the acceptance of the terms of use for the account (accept_terms.php).
    public func acceptTerms() async throws {
        _ = try await request("accept_terms.php", body: Data("{}".utf8))
        termsAccepted = true
    }
    /// Folders returned with the last inventory, or `nil` if the website does not support them.
    public func remoteFolders() -> [RemoteFolder]? { folders }

    private static func loginError(in html: String) -> String? {
        let pattern = #"<div\b[^>]*class=["'][^"']*\berror\b[^"']*["'][^>]*>[\s\S]*?</div>"#
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let message = String(html[range]).plainText
        return message.isEmpty ? nil : String(message.prefix(300))
    }

    private func request(_ path: String, body: Data? = nil, contentType: String = "application/json", json: Bool = true) async throws -> JSONValue {
        guard let base, let session, let url = URL(string: path, relativeTo: base)?.absoluteURL else { throw AudienceError.message("Connectez-vous au site dans les réglages.") }
        var r = URLRequest(url: url)
        r.httpMethod = body == nil ? "GET" : "POST"
        r.httpBody = body
        r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        r.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        var origin = URLComponents(url: base, resolvingAgainstBaseURL: true)!
        origin.path = ""; origin.query = nil; origin.fragment = nil
        r.setValue(origin.string, forHTTPHeaderField: "Origin")
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse,
              response.url?.host == base.host, response.url?.scheme == "https" else {
            throw AudienceError.message("Le site a redirigé la requête vers une autre adresse. Vérifiez l’adresse HTTPS du dossier Audience.")
        }
        if http.statusCode == 429 {
            throw AudienceError.message("Trop de tentatives de connexion. Réessayez dans quelques minutes.")
        }
        if http.statusCode == 404 {
            throw AudienceError.message("Le site ne propose pas la page \(url.lastPathComponent). Vérifiez l’adresse du dossier Audience et la mise à jour du site.")
        }
        let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            if let message = value?["error"].string, !message.isEmpty {
                throw AudienceError.message("\(message) (HTTP \(http.statusCode)).")
            }
            if !json, let message = Self.loginError(in: String(decoding: data, as: UTF8.self)) {
                throw AudienceError.rejectedCredentials(message)
            }
            throw AudienceError.message("Le site a refusé la requête (HTTP \(http.statusCode)). Réessayez ou vérifiez l’adresse du site.")
        }
        if !json { return .string(String(decoding: data, as: UTF8.self)) }
        guard let value else { throw AudienceError.message("Le site n’a pas renvoyé une réponse Audience valide.") }
        guard value["success"].bool else { throw AudienceError.message(value["error"].string.isEmpty ? "La requête a échoué." : value["error"].string) }
        return value
    }
    public func inventory() async throws -> [RemoteItem] {
        let active = try await request("list_quizzes.php")
        let trash = try await request("list_deleted_quizzes.php")
        if case .array(let list) = active["folders"] { folders = list.compactMap(RemoteFolder.init(json:)) } else { folders = nil }
        return (active["items"].array + trash["items"].array).map { RemoteItem(fields: $0) }
    }
    public func read(_ item: RemoteItem) async throws -> RemoteQuiz {
        let escaped = item.code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await request("get_batch.php?code=\(escaped)")
        var quiz = Quiz(fields: data.object)
        quiz["code"] = .string(item.code)
        quiz["deletedAt"] = .null
        quiz["isFavorite"] = item.fields["isFavorite"]
        quiz["updatedAt"] = item.fields.object["updatedAt"] ?? .string(Quiz.timestamp)
        var questions = quiz.questions
        for i in questions.indices {
            let path = questions[i]["questionImage"].string
            if !path.isEmpty, !path.hasPrefix("data:"), let base,
               let url = URL(string: path, relativeTo: base)?.absoluteURL, url.scheme == "https" {
                // An unavailable image must not hide all questionnaires from the library.
                questions[i]["questionImage"] = .string(url.absoluteString)
                if url.host == base.host, let session,
                   let (bytes, response) = try? await session.data(from: url),
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let mime = response.mimeType, mime.hasPrefix("image/"), bytes.count <= 2 * 1024 * 1024 {
                    questions[i]["questionImage"] = .string("data:\(mime);base64,\(bytes.base64EncodedString())")
                }
            }
        }
        quiz.questions = questions
        // Empty drafts have no results endpoint; that must not prevent their appearance.
        var downloadedResults: JSONValue?
        var warning: String?
        if !quiz.questions.isEmpty {
            do { downloadedResults = try await results(code: item.code) }
            catch { warning = "Résultats non actualisés : \(error.localizedDescription)" }
        }
        return RemoteQuiz(quiz: quiz, results: downloadedResults, warning: warning)
    }
    public func write(_ quiz: Quiz, replacing item: RemoteItem?) async throws -> RemoteQuiz {
        if let item {
            let fresh = try await read(item)
            if fresh.quiz["liveActive"].bool {
                throw AudienceError.message("Ce questionnaire est en direct sur le site. Ses modifications seront envoyées après la session.")
            }
            if let expected = item.fields.object["expectedFingerprint"]?.string,
               fresh.quiz.syncFingerprint != expected {
                throw AudienceError.message("Ce questionnaire vient de changer sur le site. Les deux versions seront comparées à la prochaine synchronisation.")
            }
        }
        try await send(quiz, draft: true)
        let favorite: JSONValue = .object(["code": .string(quiz.code), "favorite": .bool(quiz.isFavorite)])
        _ = try await request("set_quiz_favorite.php", body: JSONEncoder().encode(favorite))
        var fields = item?.fields.object ?? [:]
        fields["code"] = .string(quiz.code); fields["isFavorite"] = .bool(quiz.isFavorite)
        fields["updatedAt"] = .string(Quiz.timestamp)
        return try await read(RemoteItem(fields: .object(fields)))
    }
    public func setDeleted(code: String, deleted: Bool) async throws {
        let payload: JSONValue = .object(["code": .string(code)])
        _ = try await request(deleted ? "delete_batch.php" : "restore_batch.php", body: JSONEncoder().encode(payload))
    }
    public func purge(code: String) async throws {
        let payload: JSONValue = .object(["code": .string(code)])
        _ = try await request("purge_batch.php", body: JSONEncoder().encode(payload))
    }
    /// Uploads a questionnaire. A live presentation passes a `runID`, as the website does:
    /// the server locks each participant's vote per question *and* per run, so without a new
    /// run a phone that answered in an earlier session could never answer again.
    @discardableResult
    public func send(_ quiz: Quiz, index: Int = 0, live: Bool = false, draft: Bool = false,
                     runID: String? = nil, resetResponses: Bool = false) async throws -> JSONValue {
        if let message = quiz.validationMessage { throw AudienceError.message(message) }
        var upload = quiz
        var questions = quiz.questions
        for i in questions.indices {
            if let runID { questions[i]["runId"] = .string(runID) }
            // Keep escaped characters intact through PHP's rich-text normalizer.
            let text = questions[i]["question"].string
            if !text.contains("<") { questions[i]["question"] = .string("<p>\(text)</p>") }
            let image = questions[i]["questionImage"].string
            if image.hasPrefix("data:"), let comma = image.firstIndex(of: ","),
               let bytes = Data(base64Encoded: String(image[image.index(after: comma)...])) {
                let mime = String(image.dropFirst(5).prefix(while: { $0 != ";" }))
                let boundary = UUID().uuidString
                var body = Data()
                func append(_ string: String) { body.append(Data(string.utf8)) }
                append("--\(boundary)\r\nContent-Disposition: form-data; name=\"code\"\r\n\r\n\(quiz.code)\r\n")
                append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"image\"\r\nContent-Type: \(mime)\r\n\r\n")
                body.append(bytes); append("\r\n--\(boundary)--\r\n")
                let result = try await request("upload_question_image.php", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
                questions[i]["questionImage"] = result["imageUrl"]
            }
        }
        upload.questions = questions
        var payload = upload.payload(index: index, live: live).object
        payload["draftMode"] = .bool(draft)
        payload["resetAllResponses"] = .bool(resetResponses && !draft)
        return try await request("save_question.php", body: JSONEncoder().encode(JSONValue.object(payload)))
    }
    /// Starts the current question's timer again (set_live.php), without uploading the questionnaire.
    public func restartQuestion(code: String) async throws -> JSONValue {
        let value: JSONValue = .object(["code": .string(code), "liveActive": .bool(true)])
        return try await request("set_live.php", body: JSONEncoder().encode(value))
    }
    /// Participants whose page reported in during the last 20 seconds.
    public func presence(code: String) async throws -> Int {
        try await request("get_presence_count.php?code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")["connectedCount"].int
    }
    public static func makeRunID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let token = String((0..<8).map { _ in alphabet.randomElement()! })
        return "run_\(Int(Date().timeIntervalSince1970 * 1000))_\(token)"
    }
    public func organize(_ request: JSONValue) async throws -> JSONValue {
        try await self.request("quiz_organize.php", body: JSONEncoder().encode(request))
    }
    public func stop(code: String) async throws {
        let value: JSONValue = .object(["code": .string(code), "liveActive": .bool(false)])
        _ = try await request("set_live.php", body: JSONEncoder().encode(value))
    }
    public func results(code: String) async throws -> JSONValue {
        try await request("get_batch_results.php?code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }
}
