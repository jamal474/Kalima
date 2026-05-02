import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @ObservedObject var auth = AuthManager.shared
    @State private var isLoading = false
    @State private var errorMessage: String?

    // iOS Client ID (auto-created by Firebase for com.shabbirjamal)
    // This client type supports PKCE (authorization code flow) with a custom scheme
    private let clientID      = "288856934868-tsq7vcs0qgsu42e70lq787hscmqu7r8e.apps.googleusercontent.com"
    private let redirectURI   = "com.googleusercontent.apps.288856934868-tsq7vcs0qgsu42e70lq787hscmqu7r8e:/oauth2redirect"
    private let callbackScheme = "com.googleusercontent.apps.288856934868-tsq7vcs0qgsu42e70lq787hscmqu7r8e"

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.theme.gradient)
                        .frame(width: 100, height: 100)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.black)
                }
                Text("kalima")
                    .font(.system(size: 48, weight: .bold, design: .serif))
                Text("Master your vocabulary with AI & Cloud sync")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            if isLoading {
                ProgressView("Signing you in...")
                    .padding()
            } else {
                Button(action: startGoogleSignIn) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Sign in with Google")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Text("By signing in, your words and progress will be protected in the cloud.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // ─────────────────────────────────────────────
    // MARK: OAuth PKCE Flow
    // ─────────────────────────────────────────────

    func startGoogleSignIn() {
        isLoading = true
        errorMessage = nil

        // Step 1: Generate PKCE code_verifier and code_challenge
        let codeVerifier  = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        // Step 2: Build the authorization URL (response_type=code for iOS client)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: clientID),
            URLQueryItem(name: "redirect_uri",          value: redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "openid profile email"),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else {
            errorMessage = "Could not build authentication URL."
            isLoading = false
            return
        }

        // Step 3: Open Google login in a secure in-app browser
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            DispatchQueue.main.async {
                isLoading = false

                // User cancelled — silently ignore
                if let err = error as? ASWebAuthenticationSessionError, err.code == .canceledLogin { return }
                if let err = error {
                    errorMessage = "Sign-in failed: \(err.localizedDescription)"
                    return
                }

                // Step 4: Extract the authorization code from the redirect URL
                guard let callbackURL = callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value else {
                    errorMessage = "No authorization code returned."
                    return
                }

                isLoading = true
                Task {
                    await handleAuthorizationCode(code, codeVerifier: codeVerifier)
                }
            }
        }

        session.presentationContextProvider = AuthPresentationContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    // ─────────────────────────────────────────────
    // MARK: Token Exchange
    // ─────────────────────────────────────────────

    /// Exchange authorization code for id_token, then sign into Firebase
    @MainActor
    private func handleAuthorizationCode(_ code: String, codeVerifier: String) async {
        do {
            // Step 5: Exchange code for tokens at Google's token endpoint
            // Native/iOS clients don't require a client_secret when using PKCE
            let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
            var tokenRequest = URLRequest(url: tokenURL)
            tokenRequest.httpMethod = "POST"
            tokenRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let params = [
                "code=\(code)",
                "client_id=\(clientID)",
                "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
                "code_verifier=\(codeVerifier)",
                "grant_type=authorization_code"
            ].joined(separator: "&")
            tokenRequest.httpBody = params.data(using: .utf8)

            let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
            if let http = tokenResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: tokenData, encoding: .utf8) ?? "Unknown"
                throw NSError(domain: "OAuth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(msg)"])
            }

            guard let tokenJSON = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
                  let idToken = tokenJSON["id_token"] as? String else {
                throw NSError(domain: "OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No id_token in token response"])
            }

            // Step 6: Sign into Firebase with the Google id_token
            let fbUser = try await FirebaseService.shared.signInWithGoogle(idToken: idToken)

            // Step 7: Update local session
            auth.updateAuth(
                uid:          fbUser.uid,
                email:        fbUser.email,
                name:         fbUser.name,
                photo:        fbUser.photo,
                token:        idToken,
                refreshToken: fbUser.refreshToken
            )

        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // ─────────────────────────────────────────────
    // MARK: PKCE Helpers
    // ─────────────────────────────────────────────

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// ─────────────────────────────────────────────
// MARK: Presentation Context
// ─────────────────────────────────────────────

class AuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContextProvider()
    private override init() {}

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
