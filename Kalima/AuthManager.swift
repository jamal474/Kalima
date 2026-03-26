import SwiftUI
import Combine

/// Manages User Session and AI Keys.
/// Keys are cached locally in UserDefaults and synced to/from Firestore for multi-device access.
public class AuthManager: ObservableObject {
    public static let shared = AuthManager()
    
    @Published public var isLoggedIn: Bool = false
    @Published public var userName: String = "Guest User"
    @Published public var userEmail: String = ""
    @Published public var profileImageURL: URL?
    
    // AI Keys
    @Published public var geminiKey: String = ""
    @Published public var elevenLabsKey: String = ""
    @Published public var merriamWebsterKey: String = ""
    @Published public var groqKey: String = ""
    
    // Auth Tokens for Firestore
    private(set) var idToken: String = ""
    private(set) var uid: String = ""
    private(set) var refreshToken: String = ""   // Used to get a fresh idToken after expiry
    
    private init() {
        self.geminiKey         = UserDefaults.standard.string(forKey: "gemini_api_key")       ?? ""
        self.elevenLabsKey     = UserDefaults.standard.string(forKey: "eleven_labs_api_key") ?? ""
        self.merriamWebsterKey = UserDefaults.standard.string(forKey: "mw_api_key")          ?? ""
        self.groqKey           = UserDefaults.standard.string(forKey: "groq_api_key")        ?? ""

        // Restore session if previously logged in
        if let savedUID = UserDefaults.standard.string(forKey: "user_uid"), !savedUID.isEmpty {
            self.uid          = savedUID
            self.userName     = UserDefaults.standard.string(forKey: "user_name")    ?? "User"
            self.userEmail    = UserDefaults.standard.string(forKey: "user_email")   ?? ""
            self.idToken      = UserDefaults.standard.string(forKey: "user_idtoken") ?? ""
            self.refreshToken = UserDefaults.standard.string(forKey: "user_refresh") ?? ""
            self.isLoggedIn   = true
            if let photoURLStr = UserDefaults.standard.string(forKey: "user_photo") {
                self.profileImageURL = URL(string: photoURLStr)
            }
        }
    }
    
    public func updateAuth(uid: String, email: String, name: String, photo: String?, token: String, refreshToken: String = "") {
        self.uid          = uid
        self.userEmail    = email
        self.userName     = name
        self.idToken      = token
        self.refreshToken = refreshToken
        self.isLoggedIn   = true

        if let photoString = photo {
            self.profileImageURL = URL(string: photoString)
        }

        UserDefaults.standard.set(uid,          forKey: "user_uid")
        UserDefaults.standard.set(name,         forKey: "user_name")
        UserDefaults.standard.set(email,        forKey: "user_email")
        UserDefaults.standard.set(token,        forKey: "user_idtoken")
        UserDefaults.standard.set(refreshToken, forKey: "user_refresh")
        if let photo { UserDefaults.standard.set(photo, forKey: "user_photo") }
    }

    /// Called by FirebaseService when a 401 is received.
    /// Uses the stored refreshToken to get a new idToken from Firebase.
    /// Returns the new token, or throws if the refresh token is expired/missing.
    func refreshIdToken() async throws -> String {
        guard !refreshToken.isEmpty else {
            throw NSError(domain: "Auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "No refresh token available. Please sign in again."])
        }

        let urlStr = "https://securetoken.googleapis.com/v1/token?key=REMOVED_API_KEY"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw NSError(domain: "Auth", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Token refresh failed: \(msg)"])
        }

        guard let json         = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newIdToken   = json["id_token"]     as? String,
              let newRefresh   = json["refresh_token"] as? String else {
            throw NSError(domain: "Auth", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Malformed token refresh response."])
        }

        // Update in-memory and persisted tokens
        await MainActor.run {
            self.idToken      = newIdToken
            self.refreshToken = newRefresh
        }
        UserDefaults.standard.set(newIdToken, forKey: "user_idtoken")
        UserDefaults.standard.set(newRefresh, forKey: "user_refresh")
        print("🔑 Firebase ID token refreshed successfully.")
        return newIdToken
    }
    
    public func saveKeys(gemini: String, elevenLabs: String, merriamWebster: String, groq: String) {
        self.geminiKey         = gemini
        self.elevenLabsKey     = elevenLabs
        self.merriamWebsterKey = merriamWebster
        self.groqKey           = groq
        // Local cache — used immediately and on next launch before network fetch
        UserDefaults.standard.set(gemini,         forKey: "gemini_api_key")
        UserDefaults.standard.set(elevenLabs,     forKey: "eleven_labs_api_key")
        UserDefaults.standard.set(merriamWebster, forKey: "mw_api_key")
        UserDefaults.standard.set(groq,           forKey: "groq_api_key")
        // Cloud sync — fire-and-forget so the UI doesn't block
        if isLoggedIn, !uid.isEmpty, !idToken.isEmpty {
            Task {
                try? await FirebaseService.shared.uploadKeys(
                    gemini: gemini, elevenLabs: elevenLabs, merriamWebster: merriamWebster, groq: groq,
                    uid: uid, idToken: idToken
                )
            }
        }
    }

    /// Called after login to pull keys from Firestore and apply them (overrides local cache).
    /// If Firestore has no keys yet, bootstraps by uploading whatever is stored locally.
    @MainActor
    public func pullKeys() async {
        guard isLoggedIn, !uid.isEmpty else { return }

        if let keys = await FirebaseService.shared.fetchKeys(uid: uid, idToken: idToken) {
            // ── Cloud has keys — apply them ──────────────────────────────
            if !keys.gemini.isEmpty         { self.geminiKey         = keys.gemini;         UserDefaults.standard.set(keys.gemini,         forKey: "gemini_api_key")       }
            if !keys.elevenLabs.isEmpty     { self.elevenLabsKey     = keys.elevenLabs;     UserDefaults.standard.set(keys.elevenLabs,     forKey: "eleven_labs_api_key") }
            if !keys.merriamWebster.isEmpty { self.merriamWebsterKey = keys.merriamWebster; UserDefaults.standard.set(keys.merriamWebster, forKey: "mw_api_key")          }
            if !keys.groq.isEmpty           { self.groqKey           = keys.groq;           UserDefaults.standard.set(keys.groq,           forKey: "groq_api_key")        }
            print("☁️ API keys pulled from Firestore.")
        } else {
            // ── No keys in Firestore yet — bootstrap by uploading local ones ──
            let hasLocalKeys = !geminiKey.isEmpty || !elevenLabsKey.isEmpty
                            || !merriamWebsterKey.isEmpty || !groqKey.isEmpty
            if hasLocalKeys {
                print("☁️ No cloud keys found — uploading local keys to Firestore for the first time.")
                try? await FirebaseService.shared.uploadKeys(
                    gemini: geminiKey, elevenLabs: elevenLabsKey,
                    merriamWebster: merriamWebsterKey, groq: groqKey,
                    uid: uid, idToken: idToken
                )
            } else {
                print("No keys locally or in cloud — nothing to sync.")
            }
        }
    }
    
    public func logout() {
        isLoggedIn      = false
        userName        = "Guest User"
        userEmail       = ""
        uid             = ""
        idToken         = ""
        profileImageURL = nil

        for key in ["user_uid", "user_name", "user_email", "user_idtoken", "user_refresh", "user_photo"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Note: API keys are intentionally kept after logout so user doesn't have to re-enter them
    }
}
