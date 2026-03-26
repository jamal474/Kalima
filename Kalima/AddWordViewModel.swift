import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
class AddWordViewModel {
    var searchQuery: String = ""
    var isSearching: Bool = false
    var errorMessage: String? = nil
    
    var searchResults: [MWDictionaryResponse] = []
    var fetchedMnemonics: [MnemonicItem] = []
    var rateLimitMessage: String? = nil   // Non-nil when Gemini hits a rate limit
    
    // User edits
    var mnemonicText: String = ""
    var mnemonicDescription: String = ""
    var tags: String = ""
    
    func searchWord() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        rateLimitMessage = nil
        searchResults = []
        fetchedMnemonics = []
        
        do {
            // Fetch definitions
            let results = try await DictionaryService.shared.fetchWordDefinition(searchQuery.lowercased())
            self.searchResults = results
            
            // Try fetching mnemonics from Gemini non-fatally using the primary definition context
            if let primaryMeaning = results.flatMap({ $0.shortDefinitions }).first {
                do {
                    var groqSucceeded = false

                    // 1️⃣ Try Groq first (faster, more generous free tier)
                    if !AuthManager.shared.groqKey.isEmpty {
                        do {
                            let items = try await GroqService.shared.fetchMnemonics(for: searchQuery.lowercased(), meaning: primaryMeaning)
                            self.fetchedMnemonics = items
                            self.rateLimitMessage = nil
                            groqSucceeded = true
                        } catch GeminiError.rateLimited(let retryAfter) {
                            print("Groq rate limited (\(retryAfter)), falling back to Gemini")
                        } catch {
                            print("Groq error (\(error.localizedDescription)), trying Gemini…")
                        }
                    }

                    // 2️⃣ Gemini fallback (only if Groq didn't succeed)
                    if !groqSucceeded {
                        do {
                            let aiMnemonics = try await GeminiService.shared.fetchMnemonics(for: searchQuery.lowercased(), meaning: primaryMeaning)
                            self.fetchedMnemonics = aiMnemonics
                            self.rateLimitMessage = nil
                        } catch GeminiError.rateLimited(let retryAfter) {
                            self.rateLimitMessage = "⏳ AI mnemonics unavailable — rate limit hit. Retry after \(retryAfter)."
                        } catch {
                            print("Gemini also failed (non-fatal): \(error)")
                        }
                    }

                } catch {}
            }
            
            self.isSearching = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isSearching = false
        }
    }
    
    func saveWord(context: ModelContext) {
        guard let firstResult = searchResults.first else { return }
        
        // Aggregate all components across retained results
        let allPartsOfSpeech = Array(Set(searchResults.map { $0.partOfSpeech })).joined(separator: ", ")
        let primaryMeaning = searchResults.flatMap { $0.shortDefinitions }.first ?? "No definition available"
        let allExamples = searchResults.flatMap { $0.examples }
        
        // Map Tags efficiently
        let tagsArray = tags.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // We use MW's stems array as synonyms/forms so the user knows all word variations
        let forms = Array(Set(searchResults.flatMap { $0.stems }))
            .filter { $0.lowercased() != firstResult.word.lowercased() }
            
        let details = searchResults.map { result in
            MeaningDetails(
                partOfSpeech: result.partOfSpeech,
                definitions: result.shortDefinitions,
                examples: result.examples
            )
        }
        
        let auth = AuthManager.shared
        let newWord = Word(
            userId: auth.uid.isEmpty ? "local_user" : auth.uid,
            term: firstResult.word,
            partOfSpeech: allPartsOfSpeech,
            phoneticSpelling: firstResult.phonetic,
            pronunciationUrl: firstResult.audioURL,
            meaning: primaryMeaning,
            examples: allExamples,
            synonyms: forms,
            antonyms: [],
            detailedMeanings: details,
            mnemonics: nil,
            personalMnemonics: (mnemonicText.isEmpty && mnemonicDescription.isEmpty) ? nil : [MnemonicItem(mnemonic: mnemonicText, explanation: mnemonicDescription)],
            fetchedMnemonics: fetchedMnemonics.isEmpty ? nil : fetchedMnemonics,
            tags: tagsArray,
            srsData: SRSData(status: .new, nextReviewDate: Date(), interval: 0, easeFactor: 2.5, consecutiveCorrectAnswers: 0)
        )
        
        context.insert(newWord)
        
        // Background Cloud Sync
        if auth.isLoggedIn {
            Task {
                do {
                    try await FirebaseService.shared.uploadWord(word: newWord, uid: auth.uid, idToken: auth.idToken)
                } catch {
                    print("Cloud async upload failed: \(error)")
                }
            }
        }
        
        // Reset local state after save completes
        searchQuery = ""
        searchResults = []
        fetchedMnemonics = []
        mnemonicText = ""
        mnemonicDescription = ""
        tags = ""
    }
}
