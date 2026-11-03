import SwiftUI
import PUBOCore

/// One level only. Use the permission-filtered snapshot, never cached old bodies or public prefetch.
struct NoteContextCard: View {
    @Environment(\.openNoteCard) private var navigate
    @Environment(AppSession.self) private var session
    let value: JSONValue
    let targetID: String?
    let label: String
    private var note: Record { Record(value) }
    private var available: Bool { !note.id.isEmpty && !note["isHidden"].bool && !session.deletedNoteIDs.contains(note.id) }
    var body: some View {
        Group {
            if available {
                Button { navigate(.note(note.id)) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(label + " · " + note.user.displayName, systemImage: "arrowshape.turn.up.left").font(.caption).foregroundStyle(PUBOTheme.secondary)
                        Text(NoteContext.summary(note)).font(.subheadline).lineLimit(4).multilineTextAlignment(.leading)
                        if !note["files"].array.isEmpty { Label("\(note["files"].array.count) 个附件", systemImage: "paperclip").font(.caption) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10)
                }.buttonStyle(.plain).accessibilityIdentifier("note.context." + note.id)
            } else {
                Label("\(label)：原帖已删除或无权查看", systemImage: "lock").font(.caption).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10)
                    .accessibilityIdentifier("note.context.unavailable")
            }
        }.background(PUBOTheme.button.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}
