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
                    .disabled(isDrawerOpen)
                    .blur(radius: isDrawerOpen ? 4 : 0)
                    .animation(.easeInOut(duration: 0.3), value: isDrawerOpen)
                
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
                        .opacity(isDrawerOpen ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isDrawerOpen)
                    }
                }
                
                // Dimmed Overlay
                if isDrawerOpen {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isDrawerOpen = false
                                dragOffset = 0
                            }
                        }
                        .transition(.opacity)
                }
                
                // Custom Bottom Sheet Drawer
                if isDrawerOpen {
                    VStack(spacing: 0) {
                        // Grabber Handle
                        Capsule()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 40, height: 5)
                            .padding(.top, 12)
                            .padding(.bottom, 10)
                        
                        AddWordView()
                    }
                    .frame(height: geometry.size.height * 0.85)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: -5)
                    .ignoresSafeArea(.all, edges: .bottom)
                    .offset(y: max(0, dragOffset))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                let threshold = geometry.size.height * 0.2
                                if value.translation.height > threshold || value.velocity.height > 500 {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isDrawerOpen = false
                                        dragOffset = 0
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                    .transition(.move(edge: .bottom))
                    // Ensure the content spans the full screen width to match the 100vw bottom anchor
                    .frame(width: geometry.size.width)
                }
            }
        }
    }
}



// Ensure proper SwiftData preview context if you preview this file
#Preview {
    ContentView()
        // .modelContainer(for: Word.self, inMemory: true)
}
