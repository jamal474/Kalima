import Foundation
import SwiftData

@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    
    @Relationship(inverse: \Word.deck) var words: [Word]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.words = []
    }
}
