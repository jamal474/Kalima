import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth = AuthManager.shared
    
    @State private var geminiKey: String = ""
    @State private var elevenLabsKey: String = ""
    @State private var mwKey: String = ""
    @State private var groqKey: String = ""
    @State private var showSavedAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                // User Profile Section
                Section("Account") {
                    HStack(spacing: 16) {
                        if let url = auth.profileImageURL {
                            AsyncImage(url: url) { image in
                                image.resizable()
                                     .aspectRatio(contentMode: .fill)
                                     .frame(width: 60, height: 60)
                                     .clipShape(Circle())
                            } placeholder: {
                                ProgressView()
                                    .frame(width: 60, height: 60)
                            }
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(auth.userName)
                                .font(.headline)
                            Text(auth.userEmail.isEmpty ? "Not signed in" : auth.userEmail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    // .padding(.vertical, 8)
                }
                
                // ── AI Services ───────────────────────────────────────
                Section {
                    // Groq (primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text("Groq API Key")
                                .font(.subheadline).fontWeight(.medium)
                        } icon: {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                        }
                        Text("Primary mnemonic engine — free & fast (LLaMA 3). console.groq.com")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                        SecureField("Paste key here…", text: $groqKey)
                            .font(.caption)
                            .padding(.leading, 28)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)

                    // Gemini
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text("Gemini API Key")
                                .font(.subheadline).fontWeight(.medium)
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                        }
                        Text("Used for AI mnemonic generation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                        SecureField("Paste key here…", text: $geminiKey)
                            .font(.caption)
                            .padding(.leading, 28)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)

                    // ElevenLabs
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text("ElevenLabs API Key")
                                .font(.subheadline).fontWeight(.medium)
                        } icon: {
                            Image(systemName: "waveform")
                                .foregroundColor(.orange)
                        }
                        Text("Used for high-quality AI pronunciation audio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                        SecureField("Paste key here…", text: $elevenLabsKey)
                            .font(.caption)
                            .padding(.leading, 28)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)

                } header: {
                    Text("AI Services")
                } footer: {
                    Text("Keys are stored securely on your device and in your cloud account.")
                }

                // ── Dictionary ────────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text("Merriam-Webster API Key")
                                .font(.subheadline).fontWeight(.medium)
                        } icon: {
                            Image(systemName: "text.book.closed.fill")
                                .foregroundColor(.blue)
                        }
                        Text("Used for word definitions, examples & pronunciation URLs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                        SecureField("Paste key here…", text: $mwKey)
                            .font(.caption)
                            .padding(.leading, 28)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)

                } header: {
                    Text("Dictionary")
                } footer: {
                    Text("Get your free key at dictionaryapi.com")
                }

                // ── Save ──────────────────────────────────────────────
                Section {
                    Button("Save All Keys") {
                        auth.saveKeys(gemini: geminiKey, elevenLabs: elevenLabsKey, merriamWebster: mwKey, groq: groqKey)
                        showSavedAlert = true
                    }
                    .disabled(geminiKey.trimmingCharacters(in: .whitespaces).isEmpty &&
                              elevenLabsKey.trimmingCharacters(in: .whitespaces).isEmpty &&
                              mwKey.trimmingCharacters(in: .whitespaces).isEmpty &&
                              groqKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .tint(.theme)
                }
                
                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        auth.logout()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Load existing keys into local state
                self.geminiKey     = auth.geminiKey
                self.elevenLabsKey = auth.elevenLabsKey
                self.mwKey         = auth.merriamWebsterKey
                self.groqKey       = auth.groqKey
            }
            .alert("Settings Saved", isPresented: $showSavedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your AI keys have been saved successfully.")
            }
        }
    }
}
