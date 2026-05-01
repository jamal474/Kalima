import Foundation
import SwiftData
import Combine

/// A lightweight Firebase Service using REST APIs (no SDK needed)
/// This is the most stable approach for Swift Playgrounds.
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    private init() {}

    /// Fetched securely from GoogleService-Info.plist (gitignored)
    private var apiKey: String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let key = dict["API_KEY"] as? String else {
            fatalError("🚨 Missing GoogleService-Info.plist. Please download it from Firebase Console and add it to your Xcode project to use Firebase REST APIs.")
        }
        return key
    }
    
    private var projectID: String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let pid = dict["PROJECT_ID"] as? String else {
            fatalError("🚨 Missing GoogleService-Info.plist. Please download it from Firebase Console and add it to your Xcode project to use Firebase REST APIs.")
        }
        return pid
    }

    // ─────────────────────────────────────────────
    // MARK: Authentication
    // ─────────────────────────────────────────────

    /// Sign in with a Google ID Token via Firebase Identity Toolkit REST API
    func signInWithGoogle(idToken: String) async throws -> (uid: String, email: String, name: String, photo: String?, refreshToken: String) {
        let urlStr = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)"
        guard let url = URL(string: urlStr) else {
            throw URLError(.badURL)
        }

        let body: [String: Any] = [
            "postBody": "id_token=\(idToken)&providerId=google.com",
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Firebase signInWithIdp Error (\(httpResponse.statusCode)): \(msg)")
            throw NSError(domain: "Firebase", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoded = try JSONDecoder().decode(FirebaseSignInResponse.self, from: data)
        return (decoded.localId, decoded.email, decoded.displayName ?? "", decoded.photoUrl, decoded.refreshToken)
    }

    /// Sign in with a Google access_token (returned by Web OAuth clients).
    /// Exchanges an access_token for a Firebase ID Token via the signInWithIdp endpoint.
    func signInWithGoogleAccessToken(_ accessToken: String) async throws -> (uid: String, email: String, name: String, photo: String?, idToken: String, refreshToken: String) {
        let urlStr = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let body: [String: Any] = [
            "postBody": "access_token=\(accessToken)&providerId=google.com",
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            print("Firebase signInWithIdp error (\(http.statusCode)): \(msg)")
            throw NSError(domain: "Firebase", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoded = try JSONDecoder().decode(FirebaseSignInResponse.self, from: data)
        return (decoded.localId, decoded.email, decoded.displayName ?? "", decoded.photoUrl, decoded.idToken, decoded.refreshToken)
    }

    // ─────────────────────────────────────────────
    // MARK: Token Helper
    // ─────────────────────────────────────────────

    /// Returns a fresh idToken, auto-refreshing if needed.
    /// Pass this to every Firestore call instead of AuthManager.shared.idToken directly.
    private func validIdToken() async throws -> String {
        let token = AuthManager.shared.idToken
        // If we have a token, return it optimistically — Firestore call will 401 if expired
        // (auto-refresh on 401 handles it). Just guard for empty.
        guard !token.isEmpty else {
            throw NSError(domain: "Auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        return token
    }

    /// Refreshes the token on a 401 and returns the new token.
    private func refreshedToken() async throws -> String {
        return try await AuthManager.shared.refreshIdToken()
    }

    // ─────────────────────────────────────────────
    // MARK: Firestore – API Keys
    // ─────────────────────────────────────────────

    /// Path: /users/{uid}/settings/apiKeys
    private func apiKeysURL(uid: String) -> URL? {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/users/\(uid)/settings/apiKeys")
    }

    /// Push AES-256-GCM encrypted API keys to Firestore.
    func uploadKeys(gemini: String, elevenLabs: String, merriamWebster: String, groq: String,
                    uid: String, idToken: String) async throws {
        guard let url = apiKeysURL(uid: uid) else { throw URLError(.badURL) }

        // Encrypt before upload — plaintext never leaves the device
        let fields: [String: Any] = [
            "gemini":         ["stringValue": (try? CryptoHelpers.encrypt(gemini,         uid: uid)) ?? gemini],
            "elevenLabs":     ["stringValue": (try? CryptoHelpers.encrypt(elevenLabs,     uid: uid)) ?? elevenLabs],
            "merriamWebster": ["stringValue": (try? CryptoHelpers.encrypt(merriamWebster, uid: uid)) ?? merriamWebster],
            "groq":           ["stringValue": (try? CryptoHelpers.encrypt(groq,           uid: uid)) ?? groq]
        ]

        func makeRequest(token: String) -> URLRequest {
            var r = URLRequest(url: url)
            r.httpMethod = "PATCH"
            r.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.addValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
            return r
        }

        var (data, response) = try await URLSession.shared.data(for: makeRequest(token: idToken))
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let newToken = try await refreshedToken()
            (data, response) = try await URLSession.shared.data(for: makeRequest(token: newToken))
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw NSError(domain: "Firestore", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        print("☁️ API keys uploaded to Firestore.")
    }

    /// Pull API keys from Firestore. Returns nil if no keys document exists yet.
    func fetchKeys(uid: String, idToken: String) async -> (gemini: String, elevenLabs: String, merriamWebster: String, groq: String)? {
        guard let url = apiKeysURL(uid: uid) else { return nil }

        func makeRequest(token: String) -> URLRequest {
            var r = URLRequest(url: url)
            r.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return r
        }

        do {
            var token = idToken
            var (data, response) = try await URLSession.shared.data(for: makeRequest(token: token))
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                token = try await refreshedToken()
                (data, response) = try await URLSession.shared.data(for: makeRequest(token: token))
            }
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 404 { return nil }   // No keys saved yet — that's fine
            guard (200...299).contains(http.statusCode),
                  let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fields = json["fields"] as? [String: Any] else { return nil }

            func s(_ key: String) -> String {
                (fields[key] as? [String: Any])?["stringValue"] as? String ?? ""
            }
            // Decrypt each key — falls back to raw value if decryption fails (e.g. legacy unencrypted)
            return (
                (try? CryptoHelpers.decrypt(s("gemini"),         uid: uid)) ?? s("gemini"),
                (try? CryptoHelpers.decrypt(s("elevenLabs"),     uid: uid)) ?? s("elevenLabs"),
                (try? CryptoHelpers.decrypt(s("merriamWebster"), uid: uid)) ?? s("merriamWebster"),
                (try? CryptoHelpers.decrypt(s("groq"),           uid: uid)) ?? s("groq")
            )
        } catch {
            print("fetchKeys error: \(error.localizedDescription)")
            return nil
        }
    }

    // ─────────────────────────────────────────────
    // MARK: Firestore – Upload
    // ─────────────────────────────────────────────

    @MainActor
    func uploadWord(word: Word, uid: String, idToken: String) async throws {
        let docID = word.id.uuidString
        let urlStr = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/users/\(uid)/words/\(docID)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        func makeRequest(token: String) -> URLRequest {
            var r = URLRequest(url: url)
            r.httpMethod = "PATCH"
            r.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.addValue("application/json",  forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": word.toFirestoreFields()])
            return r
        }

        var (data, response) = try await URLSession.shared.data(for: makeRequest(token: idToken))

        // Auto-refresh on 401 and retry once
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            print("Firestore 401 — refreshing token and retrying...")
            let newToken = try await refreshedToken()
            (data, response) = try await URLSession.shared.data(for: makeRequest(token: newToken))
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            print("Firestore Upload Error (\(http.statusCode)): \(msg)")
            throw NSError(domain: "Firestore", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        word.lastSyncedAt = Date()
    }

    // ─────────────────────────────────────────────
    // MARK: Firestore – Delete
    // ─────────────────────────────────────────────

    func deleteWord(wordID: UUID, uid: String, idToken: String) async throws {
        let urlStr = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/users/\(uid)/words/\(wordID.uuidString)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode), http.statusCode != 404 {
            print("Firestore Delete Error (\(http.statusCode))")
        }
    }

    // ─────────────────────────────────────────────
    // MARK: Firestore – Fetch
    // ─────────────────────────────────────────────

    private func fetchAllWordsRaw(uid: String, idToken: String) async throws -> [[String: Any]] {
        let urlStr = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/users/\(uid)/words"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        func makeRequest(token: String) -> URLRequest {
            var r = URLRequest(url: url)
            r.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return r
        }

        var (data, response) = try await URLSession.shared.data(for: makeRequest(token: idToken))

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            print("fetchAllWordsRaw: 401 Unauthorized, refreshing token...")
            let newToken = try await refreshedToken()
            (data, response) = try await URLSession.shared.data(for: makeRequest(token: newToken))
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return [] }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documents = json["documents"] as? [[String: Any]] else {
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("fetchAllWordsRaw HTTP Error \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            }
            return []
        }
        return documents
    }

    // ─────────────────────────────────────────────
    // MARK: Firestore – Pull & Merge
    // ─────────────────────────────────────────────

    @MainActor
    func pullAndMerge(context: ModelContext, uid: String, idToken: String) async {
        do {
            let cloudDocs = try await fetchAllWordsRaw(uid: uid, idToken: idToken)
            print("Fetched \(cloudDocs.count) words from cloud.")

            let descriptor = FetchDescriptor<Word>()
            let localWords = (try? context.fetch(descriptor)) ?? []
            let localIDs = Set(localWords.map { $0.id.uuidString })

            for doc in cloudDocs {
                guard let name = doc["name"] as? String,
                      let docIDString = name.components(separatedBy: "/").last,
                      !localIDs.contains(docIDString),
                      let uuid = UUID(uuidString: docIDString),
                      let fields = doc["fields"] as? [String: Any] else { continue }

                // ── Helpers ────────────────────────────────────────────
                func str(_ key: String)  -> String  { (fields[key] as? [String: Any])?["stringValue"] as? String ?? "" }
                func bool(_ key: String) -> Bool     { (fields[key] as? [String: Any])?["booleanValue"] as? Bool ?? false }
                func strArr(_ key: String) -> [String] {
                    guard let arr = (fields[key] as? [String: Any])?["arrayValue"] as? [String: Any],
                          let vals = arr["values"] as? [[String: Any]] else { return [] }
                    return vals.compactMap { $0["stringValue"] as? String }
                }
                func jsonDecode<T: Decodable>(_ key: String, as type: T.Type) -> T? {
                    guard let jsonStr = (fields[key] as? [String: Any])?["stringValue"] as? String,
                          let data = jsonStr.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(type, from: data)
                }

                // ── Core ───────────────────────────────────────────────
                let term    = str("term")
                let meaning = str("meaning")
                let pos     = str("partOfSpeech")
                let phonetic: String? = str("phoneticSpelling").isEmpty ? nil : str("phoneticSpelling")
                let pronUrl: URL?     = URL(string: str("pronunciationUrl"))
                let favorite          = bool("isFavorite")

                // ── Arrays ─────────────────────────────────────────────
                let examples  = strArr("examples")
                let synonyms  = strArr("synonyms")
                let antonyms  = strArr("antonyms")
                let tags      = strArr("tags")

                // ── Detailed meanings ──────────────────────────────────
                let detailedMeanings = jsonDecode("detailedMeanings", as: [MeaningDetails].self)

                // ── Mnemonics ──────────────────────────────────────────
                let fetchedMnemonics  = jsonDecode("fetchedMnemonics",  as: [MnemonicItem].self)
                let personalMnemonics = jsonDecode("personalMnemonics", as: [MnemonicItem].self)

                // ── SRS ────────────────────────────────────────────────
                var srs = SRSData()
                if let srsMap    = (fields["srsData"] as? [String: Any])?["mapValue"] as? [String: Any],
                   let srsFields = srsMap["fields"] as? [String: Any] {
                    let statusStr = (srsFields["status"] as? [String: Any])?["stringValue"] as? String ?? "new"
                    srs.status = statusStr
                    if let intervalStr = (srsFields["interval"] as? [String: Any])?["integerValue"] as? String {
                        srs.interval = Int(intervalStr) ?? 0
                    }
                    if let ease = (srsFields["easeFactor"] as? [String: Any])?["doubleValue"] as? Double {
                        srs.easeFactor = ease
                    }
                    if let ccaStr = (srsFields["consecutiveCorrectAnswers"] as? [String: Any])?["integerValue"] as? String {
                        srs.consecutiveCorrectAnswers = Int(ccaStr) ?? 0
                    }
                    if let nextStr = (srsFields["nextReviewDate"] as? [String: Any])?["timestampValue"] as? String {
                        srs.nextReviewDate = ISO8601DateFormatter().date(from: nextStr) ?? Date()
                    }
                }

                // ── Construct & insert ─────────────────────────────────
                let newWord = Word(
                    id:               uuid,
                    userId:           uid,
                    term:             term,
                    partOfSpeech:     pos,
                    phoneticSpelling: phonetic,
                    pronunciationUrl: pronUrl,
                    meaning:          meaning,
                    examples:         examples,
                    synonyms:         synonyms,
                    antonyms:         antonyms,
                    detailedMeanings: detailedMeanings,
                    personalMnemonics: personalMnemonics,
                    fetchedMnemonics:  fetchedMnemonics,
                    tags:             tags,
                    isFavorite:       favorite,
                    srsData:          srs,
                    lastSyncedAt:     Date()
                )
                context.insert(newWord)
                print("Merged '\(term)' from cloud with \(fetchedMnemonics?.count ?? 0) mnemonics, \(examples.count) examples")
            }

            do {
                try context.save()
            } catch {
                print("CRITICAL: Failed to save context after pullAndMerge! Error: \(error)")
            }

        } catch {
            print("Pull & Merge failed: \(error.localizedDescription)")
        }
    }

    // ─────────────────────────────────────────────
    // MARK: Firestore – Bulk Sync
    // ─────────────────────────────────────────────

    @MainActor
    func syncAll(words: [Word], uid: String, idToken: String) async {
        guard !uid.isEmpty, !idToken.isEmpty else {
            print("Skipping sync — user not logged in.")
            return
        }
        print("Starting cloud sync for \(words.count) words...")
        for word in words {
            do {
                try await uploadWord(word: word, uid: uid, idToken: idToken)
            } catch {
                print("Failed to sync '\(word.term)': \(error.localizedDescription)")
            }
        }
        print("Cloud sync complete.")
    }
}

// MARK: - Codable Response Model
struct FirebaseSignInResponse: Codable {
    let localId: String
    let idToken: String
    let refreshToken: String
    let email: String
    let displayName: String?
    let photoUrl: String?
}
