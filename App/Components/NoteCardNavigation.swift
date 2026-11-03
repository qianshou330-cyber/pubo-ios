import SwiftUI

enum NoteCardDestination: Hashable { case author(String), note(String) }
private struct OpenNoteCardKey: EnvironmentKey {
    static let defaultValue: (NoteCardDestination) -> Void = { _ in }
}
extension EnvironmentValues {
    var openNoteCard: (NoteCardDestination) -> Void {
        get { self[OpenNoteCardKey.self] }
        set { self[OpenNoteCardKey.self] = newValue }
    }
}

/// Register at the screen, outside lazy list rows. Each tap chooses one destination.
struct NoteCardNavigation: ViewModifier {
    @State private var destination: NoteCardDestination?
    func body(content: Content) -> some View {
        content.environment(\.openNoteCard, { destination = $0 })
            .navigationDestination(item: $destination) { target in
                switch target { case .author(let id): ProfileView(userID: id); case .note(let id): NoteDetailView(noteID: id) }
            }
    }
}
