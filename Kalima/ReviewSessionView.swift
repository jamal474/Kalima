import SwiftUI
import SwiftData
import AVFoundation

struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = FlashcardViewModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.sessionCompleted {
                    VStack(spacing: 24) {
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.orange)
                        Text("Session Complete!")
                            .font(.title.bold())
                        Text("You've reviewed all cards due for today.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Finish") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                    }
                } else if let card = viewModel.currentCard {
                    FlashcardView(
                        card: card,
                        isShowingAnswer: viewModel.isShowingAnswer,
                        onReveal: { viewModel.revealAnswer() },
                        onRate: { rating in
                            viewModel.submitRating(rating, context: modelContext)
                        }
                    )
                } else {
                    ProgressView("Loading cards...")
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundColor(.theme)
                    }
                }
            }
            .onAppear {
                viewModel.getDailyQueue(context: modelContext)
            }
        }
    }
}

struct FlashcardView: View {
    let card: Word
    let isShowingAnswer: Bool
    let onReveal: () -> Void
    let onRate: (SRSEngine.ResponseRating) -> Void
    @ObservedObject private var pronunciation = PronunciationService.shared
    
    var body: some View {
        VStack {
            // Front of Card
            VStack(spacing: 4) {
                Text(card.term)
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 10) {
                    if let phonetic = card.phoneticSpelling {
                        Text(phonetic)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        if pronunciation.isPlaying {
                            pronunciation.stopAll()
                        } else {
                            pronunciation.speak(word: card.term, audioURL: card.pronunciationUrl)
                        }
                    }) {
                        Image(systemName: pronunciation.isPlaying ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundColor(.theme)
                            .animation(.easeInOut(duration: 0.2), value: pronunciation.isPlaying)
                    }
                }
            }
            .padding(.top, 32)
            .padding(.horizontal)
            
            if isShowingAnswer {
                ScrollView {
                    VStack(spacing: 20) {
                        Divider()
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            if let details = card.detailedMeanings, !details.isEmpty {
                                ForEach(details, id: \.self) { detail in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(detail.partOfSpeech.uppercased())
                                            .font(.caption.bold())
                                            .foregroundColor(.theme)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.theme.opacity(0.1))
                                            .cornerRadius(6)
                                        
                                        if let firstDef = detail.definitions.first {
                                            Text(firstDef)
                                                .font(.title3)
                                        }
                                        
                                        if let firstExample = detail.examples.first {
                                            Text("\"\(firstExample)\"")
                                                .font(.subheadline)
                                                .italic()
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if detail != details.last {
                                        Divider()
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(card.partOfSpeech.uppercased())
                                        .font(.caption.bold())
                                        .foregroundColor(.theme)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.theme.opacity(0.1))
                                        .cornerRadius(6)
                                    
                                    Text(card.meaning)
                                        .font(.title3)
                                    
                                    if let firstExample = card.examples.first {
                                        Text("\"\(firstExample)\"")
                                            .font(.subheadline)
                                            .italic()
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            // Personal Mnemonics (max 2 in review card)
                            if let personalMnemonics = card.personalMnemonics, !personalMnemonics.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Personal Mnemonics:")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                    ForEach(Array(personalMnemonics.prefix(2)), id: \.self) { item in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("• \(item.mnemonic)")
                                                .font(.subheadline)
                                                .bold()
                                            if !item.explanation.isEmpty {
                                                Text(item.explanation)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(.leading, 12)
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            } else if let mnemonic = card.mnemonics, !mnemonic.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("Personal Mnemonic:")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                    Text(mnemonic)
                                        .font(.subheadline)
                                        .italic()
                                }
                                .padding(.top, 4)
                            }
                            
                            if let fetchedItems = card.fetchedMnemonics, !fetchedItems.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("AI Mnemonics:")
                                        .font(.caption.bold())
                                        .foregroundColor(.purple)
                                    
                                    ForEach(Array(fetchedItems.prefix(2)), id: \.self) { item in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("• \(item.mnemonic)")
                                                .font(.subheadline)
                                                .italic()
                                            Text(item.explanation)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(.leading, 12)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                // Rating Buttons pinned to the bottom
                HStack(spacing: 12) {
                    RatingButton(title: "Again", color: .red) { onRate(.again) }
                    RatingButton(title: "Hard", color: .orange) { onRate(.hard) }
                    RatingButton(title: "Good", color: .green) { onRate(.good) }
                    RatingButton(title: "Easy", color: .theme) { onRate(.easy) }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
                .background(Color(uiColor: .systemBackground))
            } else {
                Spacer()
                Button(action: onReveal) {
                    Text("Show Answer")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.theme)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
    }
}

struct RatingButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(gradient: Gradient(colors: [color.opacity(0.7), color]), startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
        }
    }
}
