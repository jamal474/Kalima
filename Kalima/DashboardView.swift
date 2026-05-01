import SwiftUI
import SwiftData

struct MainListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.term) private var allWords: [Word]
    @State private var showingReviewSession = false
    @State private var showingSettings = false
    @ObservedObject var auth = AuthManager.shared
    
    // Computed reactive properties
    private var dueTodayCount: Int {
        let now = Date()
        return allWords.filter {
            if case .review = $0.srsData.cardStatus {
                return ($0.srsData.nextReviewDate ?? Date()) <= now
            }
            return false
        }.count
    }
    private var newCardsCount: Int { allWords.filter { $0.srsData.isNew }.count }
    private var learningCardsCount: Int {
        let now = Date()
        return allWords.filter {
            switch $0.srsData.cardStatus {
            case .learning, .relearning: return ($0.srsData.nextReviewDate ?? Date()) <= now
            default: return false
            }
        }.count
    }
    private var totalQueueCount: Int { dueTodayCount + learningCardsCount + min(20, newCardsCount) }
    
    // Search and Filter State
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    private let posFilters = ["All", "Noun", "Verb", "Adjective", "Adverb"]
    
    // Filtered Output
    private var filteredWords: [Word] {
        var result = allWords
        
        if !searchText.isEmpty {
            // Case-insensitive flexible search anywhere in the term
            result = result.filter { $0.term.localizedCaseInsensitiveContains(searchText) }
        }
        
        if selectedFilter != "All" {
            result = result.filter { $0.partOfSpeech.localizedCaseInsensitiveContains(selectedFilter) }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Header / Stats Section
                Section {
                    HStack(spacing: 16) {
                        StatBox(title: "New", count: newCardsCount, color: .theme)
                        StatBox(title: "Due", count: dueTodayCount, color: .orange)
                        StatBox(title: "Learning", count: learningCardsCount, color: .green)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                // Action Section
                Section {
                    if totalQueueCount > 0 {
                        Button(action: { showingReviewSession = true }) {
                            Text("Start Review Session (\(totalQueueCount))")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.theme)
                                .cornerRadius(12)
                        }
                    } else if !allWords.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.green)
                            Text("You're all caught up for today!")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                // Search & Filter View (Only visible if the user has words)
                if !allWords.isEmpty {
                    Section {
                        VStack(spacing: 14) {
                            // Native Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Search any word...", text: $searchText)
                                    #if os(iOS)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    #endif
                                
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(uiColor: .systemBackground))
                            .cornerRadius(10)
                            
                            // Horizontal Chip Filters
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(posFilters, id: \.self) { filter in
                                        Text(filter)
                                            .font(.subheadline.bold())
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(selectedFilter == filter ? Color.theme : Color(uiColor: .systemBackground))
                                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                                            .cornerRadius(20)
                                            .onTapGesture {
                                                withAnimation(.spring()) {
                                                    selectedFilter = filter
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .cornerRadius(0)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                
                // Word List Section
                if !allWords.isEmpty {
                    if !filteredWords.isEmpty {
                        Section(header: Text("Vocabulary Collection (\(filteredWords.count))").font(.title3.bold()).foregroundColor(.primary).textCase(nil)) {
                            ForEach(filteredWords) { word in
                            NavigationLink(destination: WordDetailView(word: word)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(word.term.capitalized)
                                            .font(.headline)
                                        Text(word.meaning)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(word.srsData.cardStatus.displayName.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.theme)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.theme.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { deleteWord(word) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                } else {
                    Section {
                        VStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)
                            Text("No words found.")
                                .font(.headline)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)
                            Text("No words added yet.")
                                .font(.headline)
                            Text("Tap the + button to search and add your first flashcard!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                
                // Add a pseudo-section to act as huge padding for the FAB
                Section {
                    Color.clear.frame(height: 120)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("kalima")
            .sheet(isPresented: $showingReviewSession) {
                ReviewSessionView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task {
                if auth.isLoggedIn {
                    await auth.pullKeys()
                    await FirebaseService.shared.pullAndMerge(context: modelContext, uid: auth.uid, idToken: auth.idToken)
                    await FirebaseService.shared.syncAll(words: allWords, uid: auth.uid, idToken: auth.idToken)
                }
            }
            .onChange(of: auth.isLoggedIn) { wasLoggedIn, isLoggedIn in
                if isLoggedIn {
                    Task {
                        await auth.pullKeys()
                        await FirebaseService.shared.pullAndMerge(context: modelContext, uid: auth.uid, idToken: auth.idToken)
                        await FirebaseService.shared.syncAll(words: allWords, uid: auth.uid, idToken: auth.idToken)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        if let url = auth.profileImageURL {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.theme)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                    .padding(.vertical, 10)
                    .padding(.horizontal, 0)
                }
            }
        }
    }
    
    private func deleteWord(_ word: Word) {
        let wordID = word.id
        let auth = AuthManager.shared
        
        modelContext.delete(word)
        do {
            try modelContext.save()
            
            // Background Firestore Delete
            if auth.isLoggedIn {
                Task {
                    try await FirebaseService.shared.deleteWord(wordID: wordID, uid: auth.uid, idToken: auth.idToken)
                }
            }
        } catch {
            print("Failed to delete word: \(error.localizedDescription)")
        }
    }
}

struct StatBox: View {
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text("\(count)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}
