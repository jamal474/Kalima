import SwiftUI
import SwiftData

struct AddWordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AddWordViewModel()
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastTask: Task<Void, Never>? = nil
    
// Start body replacement
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Search Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search Dictionary")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("Enter an English word...", text: $viewModel.searchQuery)
                                .onSubmit {
                                    Task { await viewModel.searchWord() }
                                }
                                .submitLabel(.search)
                            
                            if viewModel.isSearching {
                                ProgressView()
                                    .padding(.leading, 4)
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                    }

                    if !viewModel.searchResults.isEmpty {
                        // Definitions Cards
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Definitions Found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                            
                            ForEach(viewModel.searchResults, id: \.id) { result in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.word.capitalized)
                                                .font(.title2.bold())
                                            
                                            if let phonetic = result.phonetic {
                                                Text(phonetic)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Text(result.partOfSpeech.uppercased())
                                            .font(.caption.bold())
                                            .foregroundColor(.theme)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.theme.opacity(0.1))
                                            .cornerRadius(6)
                                        
                                        Button(action: {
                                            withAnimation {
                                                if let idx = viewModel.searchResults.firstIndex(where: { $0.id == result.id }) {
                                                    viewModel.searchResults.remove(at: idx)
                                                }
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .foregroundColor(Color.secondary.opacity(0.5))
                                                .padding(.leading, 4)
                                        }
                                    }
                                    
                                    ForEach(result.shortDefinitions, id: \.self) { def in
                                        Text("• \(def)")
                                            .font(.body)
                                    }
                                    
                                    let uniqueForms = result.stems.filter { $0.lowercased() != result.word.lowercased() }
                                    if !uniqueForms.isEmpty {
                                        Text("Forms: \(uniqueForms.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if !result.examples.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Examples")
                                                .font(.caption.bold())
                                                .foregroundColor(.secondary)
                                            
                                            ForEach(Array(result.examples.prefix(3)), id: \.self) { example in
                                                Text("• \"\(example)\"")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                        
                        if !viewModel.fetchedMnemonics.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AI Generated Mnemonics")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                    .padding(.leading, 4)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(viewModel.fetchedMnemonics, id: \.self) { item in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("• \(item.mnemonic)")
                                                .font(.subheadline)
                                                .bold()
                                            Text(item.explanation)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(.leading, 12)
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                        
                        // User Context
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Personal Study Context")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                            
                            VStack(spacing: 12) {
                                TextField("Add tags (e.g., GRE, Week1)", text: $viewModel.tags)
                                    .padding()
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Personal Mnemonic")
                                        .font(.caption.bold())
                                        .foregroundColor(.purple)
                                        .padding(.leading, 4)
                                    
                                    TextField("Memory trick (e.g., sounds like...)", text: $viewModel.mnemonicText)
                                        .padding()
                                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                        .cornerRadius(10)
                                    
                                    TextField("Why it works / explanation", text: $viewModel.mnemonicDescription)
                                        .padding()
                                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                        .cornerRadius(10)
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        
                        // Save Button
                        Button(action: {
                            viewModel.saveWord(context: modelContext)
                            dismiss()
                        }) {
                            Text("Save Word")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.theme)
                                .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Add New Word")
            .navigationBarTitleDisplayMode(.inline)
            // Floating toast overlay
            .overlay(alignment: .top) {
                if showToast {
                    HStack(alignment: .top, spacing: 12) {
                        // Icon with amber glow
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 36, height: 36)
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.orange, Color.yellow],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Rate Limit Reached")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text(toastMessage
                                .replacingOccurrences(of: "⏳ ", with: "")
                                .replacingOccurrences(of: "AI mnemonics unavailable — ", with: ""))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            // Dark blurred base
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(white: 0.1).opacity(0.95))
                            // Subtle inner border
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                            // Amber glow strip at the bottom
                            VStack {
                                Spacer()
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.8), Color.yellow.opacity(0.4)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 2)
                                    .clipShape(
                                        .rect(
                                            bottomLeadingRadius: 16,
                                            bottomTrailingRadius: 16
                                        )
                                    )
                            }
                        }
                    )
                    .shadow(color: Color.orange.opacity(0.15), radius: 16, y: 6)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .onChange(of: viewModel.rateLimitMessage) { _, newValue in
                if let msg = newValue {
                    toastMessage = msg
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showToast = true }
                    // Cancel previous auto-dismiss if still pending
                    toastTask?.cancel()
                    toastTask = Task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.35)) { showToast = false }
                    }
                } else {
                    // New search started — dismiss immediately
                    toastTask?.cancel()
                    withAnimation(.easeOut(duration: 0.25)) { showToast = false }
                }
            }
// End body replacement
        }
    }
}
