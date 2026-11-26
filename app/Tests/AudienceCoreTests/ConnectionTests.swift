import Testing
import Foundation
import Synchronization
@testable import AudienceCore

struct ConnectionTests {
    @Test func participantLinkUsesTheParameterReadByTheWebsite() {
        #expect(RemoteClient.participantURL(code: "913244")?.absoluteString == "https://www.ralentirtravaux.com/apps/audience/r.html?c=913244")
    }
    @Test func sessionCookieSurvivesLoginAndCanAuthenticateTheNextRequest() throws {
        let configuration = RemoteClient.sessionConfiguration()
        let url = try #require(URL(string: "https://audience.example/apps/audience/login.php"))
        let storage = try #require(configuration.httpCookieStorage)
        // This is the session cookie emitted by PHP after session_regenerate_id(true).
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "PHPSESSID=synthetic-session; path=/; secure; HttpOnly; SameSite=Lax"
        ], for: url)
        #expect(cookies.count == 1)
        storage.setCookies(cookies, for: url, mainDocumentURL: url)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let nextURL = try #require(URL(string: "auth_me.php", relativeTo: url))
        let saved = try #require(session.configuration.httpCookieStorage?.cookies(for: nextURL))
        #expect(HTTPCookie.requestHeaderFields(with: saved)["Cookie"]?.contains("PHPSESSID=synthetic-session") == true)
        // A fresh connection must have its own private jar, without previous sessions.
        let other = RemoteClient.sessionConfiguration()
        #expect(other.httpCookieStorage?.cookies(for: nextURL)?.isEmpty == true)
    }

    private func client() -> RemoteClient {
        RemoteClient(configurationFactory: {
            let config = RemoteClient.sessionConfiguration()
            config.protocolClasses = [ConnectionProtocol.self]
            return config
        })
    }
    @Test func connectionPreservesSpecialCharactersInCredentialsAndChecksTheSession() async throws {
        let client = client()
        let name = try await client.connect(address: "  https://success.example/apps/audience/\n", email: " teacher+test@example.org ", password: " a+b&c=d#é?% ")
        #expect(name == "Test enseignant")
        await client.disconnect()
    }
    @Test func termsOfUseAreAskedOnlyWhenTheAccountHasNotAcceptedThem() async throws {
        let older = client()
        _ = try await older.connect(address: "https://legacy.example/apps/audience/", email: "synthetic@example.org", password: "synthetic")
        #expect(await !older.needsTermsAcceptance()) // A site without the field asks nothing.
        let client = client()
        _ = try await client.connect(address: "https://terms.example/apps/audience/", email: "synthetic@example.org", password: "synthetic")
        #expect(await client.needsTermsAcceptance())
        try await client.acceptTerms()
        #expect(await !client.needsTermsAcceptance())
        await client.disconnect()
        #expect(await !client.needsTermsAcceptance())
    }
    @Test func invalidCredentialsDisplayTheServerMessage() async {
        await expectFailure(host: "invalid.example", containing: "Identifiants invalides.")
    }
    @Test func onlyRefusedCredentialsAreReportedAsSuch() async {
        // The app forgets a saved password only for this error, never for a network or server failure.
        func isRejection(_ host: String) async -> Bool {
            do { _ = try await client().connect(address: "https://\(host)/apps/audience/", email: "synthetic@example.org", password: "synthetic") }
            catch AudienceError.rejectedCredentials { return true }
            catch {}
            return false
        }
        #expect(await isRejection("invalid.example"))
        #expect(await !isRejection("limited.example"))
        #expect(await !isRejection("offline.example"))
    }
    @Test func expiredSessionIsRenewedWithTheSavedPasswordAndTheRequestRetried() async throws {
        let client = RemoteClient(configurationFactory: {
            let config = RemoteClient.sessionConfiguration()
            config.protocolClasses = [ConnectionProtocol.self]
            return config
        }, savedCredentials: { ("synthetic@example.org", "synthetic") })
        _ = try await client.connect(address: "https://expired.example/apps/audience/", email: "synthetic@example.org", password: "synthetic")
        let identity = try await client.accountIdentity()
        try await client.acceptTerms() // HTTP 401 first, accepted after the second sign-in.
        #expect(ConnectionProtocol.logins(for: "expired.example") == 2)
        #expect(try await client.accountIdentity() == identity)
        await client.disconnect()
    }
    @Test func expiredSessionWithoutSavedPasswordAsksToSignInAgain() async throws {
        let client = client()
        _ = try await client.connect(address: "https://unsaved.example/apps/audience/", email: "synthetic@example.org", password: "synthetic")
        do {
            try await client.acceptTerms()
            Issue.record("The request should report the expired session")
        } catch AudienceError.sessionExpired {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(ConnectionProtocol.logins(for: "unsaved.example") == 1)
    }
    @Test func rateLimitsAreNotReportedAsInvalidCredentials() async {
        await expectFailure(host: "limited.example", containing: "Trop de tentatives")
    }
    @Test func missingSessionEndpointIsReportedPrecisely() async {
        await expectFailure(host: "outdated.example", containing: "auth_me.php")
    }
    @Test func networkFailureKeepsItsCause() async {
        await expectFailure(host: "offline.example", code: URLError.notConnectedToInternet.rawValue)
    }
    private func expectFailure(host: String, containing message: String? = nil, code: Int? = nil) async {
        do {
            _ = try await client().connect(address: "https://\(host)/apps/audience/", email: "synthetic@example.org", password: "synthetic")
            Issue.record("Connection should fail for this fixture")
        } catch {
            if let message { #expect(error.localizedDescription.contains(message)) }
            if let code { #expect((error as NSError).code == code) }
        }
    }
}

/// No real server or real credentials are used in these connection fixtures.
private final class ConnectionProtocol: URLProtocol, @unchecked Sendable {
    /// Sign-ins per host: on expired.example and unsaved.example, the first session expires at once.
    private static let signIns = Mutex<[String: Int]>([:])
    static func logins(for host: String) -> Int { signIns.withLock { $0[host] ?? 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        let host = url.host ?? ""
        if host == "offline.example" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        var status = 200
        var body = "<html><body>Audience</body></html>"
        if url.lastPathComponent == "login.php" {
            Self.signIns.withLock { $0[host, default: 0] += 1 }
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://\(host)")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            if host == "success.example" {
                let text = String(decoding: requestBody, as: UTF8.self)
                let items = URLComponents(string: "https://fixture.example/?" + text)?.queryItems ?? []
                #expect(items.first(where: { $0.name == "email" })?.value == "teacher+test@example.org")
                #expect(items.first(where: { $0.name == "password" })?.value == " a+b&c=d#é?% ")
                #expect(!text.contains("+")) // PHP treats a raw '+' as a space.
            }
            if host == "invalid.example" { body = #"<div class="error">Identifiants invalides.</div>"# }
            if host == "limited.example" { status = 429 }
        } else if url.lastPathComponent == "accept_terms.php" {
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://\(host)")
            if (host == "expired.example" || host == "unsaved.example") && Self.logins(for: host) < 2 {
                status = 401; body = #"{"success":false,"error":"Authentification requise"}"#
            } else {
                body = #"{"success":true}"#
            }
        } else if url.lastPathComponent == "auth_me.php" {
            if host == "outdated.example" { status = 404; body = "Not Found" }
            else if host == "terms.example" { body = #"{"success":true,"user":{"id":3,"username":"Nouveau","termsAccepted":false}}"# }
            else { body = #"{"success":true,"user":{"username":"Test enseignant"}}"# }
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    private var requestBody: Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
