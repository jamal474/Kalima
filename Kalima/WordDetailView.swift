import SwiftUI
import AVFoundation

struct WordDetailView: View {
    let word: Word
    @ObservedObject private var pronunciation = PronunciationService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text(word.term.capitalized)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 10) {
                        if let phonetic = word.phoneticSpelling {
                            Text(phonetic)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            if pronunciation.isPlaying {
                                pronunciation.stopAll()
                            } else {
                                pronunciation.speak(word: word.term, audioURL: word.pronunciationUrl)
                            }
                        }) {
                            Image(systemName: pronunciation.isPlaying ? "stop.circle.fill" : "speaker.wave.2.fill")
                                .font(.title3)
                                .foregroundColor(.theme)
                                .animation(.easeInOut(duration: 0.2), value: pronunciation.isPlaying)
                        }
                    }
                }
                .padding(.top, 20)
                
                // Detailed Information
                VStack(alignment: .leading, spacing: 16) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Part of Speech")
                            .font(.caption.bold())
                            .foregroundColor(.theme)
                        Text(word.partOfSpeech.replacingOccurrences(of: ",", with: ", "))
                            .font(.subheadline)
                    }
                    
                    Divider()
                    
                    if let details = word.detailedMeanings, !details.isEmpty {
                        ForEach(details, id: \.self) { detail in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.partOfSpeech.capitalized)
                                    .font(.caption.bold())
                                    .foregroundColor(.theme)
                                
                                ForEach(detail.definitions, id: \.self) { def in
                                    Text("• \(def)")
                                        .font(.body)
                                }
                                
                                if !detail.examples.isEmpty {
                                    Text("Examples")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                        .padding(.top, 4)
                                    
                                    ForEach(detail.examples, id: \.self) { example in
                                        HStack(alignment: .top) {
                                            Text("•")
                                            Text(example)
                                                .italic()
                                        }
                                        .font(.subheadline)
                                    }
                                }
                            }
                            
                            if detail != details.last {
                                Divider()
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Definition")
                                .font(.caption.bold())
                                .foregroundColor(.theme)
                            Text(word.meaning)
                                .font(.body)
                        }
                        
                        if !word.examples.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Examples")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                
                                ForEach(word.examples, id: \.self) { example in
                                    HStack(alignment: .top) {
                                        Text("•")
                                        Text(example)
                                            .italic()
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                    
                    // Personal Mnemonics (structured, all shown)
                    if let personalMnemonics = word.personalMnemonics, !personalMnemonics.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Personal Mnemonics")
                                .font(.caption.bold())
                                .foregroundColor(.theme)
                            
                            ForEach(personalMnemonics, id: \.self) { item in
                                VStack(alignment: .leading, spacing: 4) {
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
                    } else if let mnemonic = word.mnemonics, !mnemonic.isEmpty {
                        // Legacy single-string fallback
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Personal Mnemonic")
                                .font(.caption.bold())
                                .foregroundColor(.theme)
                            Text(mnemonic)
                                .font(.subheadline)
                                .italic()
                        }
                    }
                    
                    // AI Generated Mnemonics (all shown in detail view)
                    if let fetchedMnemonics = word.fetchedMnemonics, !fetchedMnemonics.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AI Generated Mnemonics")
                                .font(.caption.bold())
                                .foregroundColor(.theme)
                            
                            ForEach(fetchedMnemonics, id: \.self) { item in
                                VStack(alignment: .leading, spacing: 4) {
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
                    }
                    
                    if !word.synonyms.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Synonyms & Related Forms")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text(word.synonyms.joined(separator: ", "))
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Learning Status Tag
                HStack {
                    Text("Current Status:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(word.srsData.cardStatus.displayName.uppercased())
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor(for: word.srsData.cardStatus))
                        .cornerRadius(8)
                }
                .padding(.top, 8)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Word Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func statusColor(for status: CardStatus) -> Color {
        switch status {
        case .new:        return .theme
        case .learning:   return .orange
        case .review:     return .green
        case .relearning: return .red
        }
    }
}
