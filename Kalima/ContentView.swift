import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var isDrawerOpen = false
    @State private var dragOffset: CGFloat = 0
    @ObservedObject var auth = AuthManager.shared
    
    var body: some View {
        if auth.isLoggedIn {
            mainAppContent
        } else {
            LoginView()
        }
    }
    
    var mainAppContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main Application Layer
                MainListView()
                
                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isDrawerOpen = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.title.weight(.bold))
                                .foregroundColor(.white)
                                .padding(20)
                                .background(Color.theme)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
                
            }
            .sheet(isPresented: $isDrawerOpen) {
                AddWordView()
            }
        }
    }
}



// Ensure proper SwiftData preview context if you preview this file
#Preview {
    ContentView()
        // .modelContainer(for: Word.self, inMemory: true)
}
