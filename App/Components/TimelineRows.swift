import SwiftUI
import PUBOCore

struct TimelinePendingButton: View {
    let count: Int
    let action: () -> Void
    var body: some View {
        Group {
            if count > 0 {
                Button(action: action) {
                    Label("新帖子 \(count)", systemImage: "arrow.up.circle")
                        .font(.subheadline).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(PUBOTheme.accent, in: Capsule()).foregroundStyle(PUBOTheme.panel)
                }.padding(8).accessibilityIdentifier("timeline.newPosts")
            }
        }
    }
}

struct TimelineLoadingStatus: View {
    let loading: Bool
    let empty: Bool
    let loaded: Bool
    let failed: Bool
    let hasMore: Bool
    var body: some View {
        Group {
            if loading && !empty { ProgressView().padding() }
            if empty && loaded && !loading && !failed { Text("暂时没有帖子").foregroundStyle(.secondary).padding(30) }
            if !hasMore && !empty { Text("已显示全部帖子").font(.caption).foregroundStyle(.secondary).padding(16) }
        }
    }
}

struct TimelinePostRow: View {
    let note: Record
    let first: Bool
    let last: Bool
    let dateBreak: String?
    let hideSensitive: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let dateBreak {
                Text(dateBreak).font(.caption).foregroundStyle(PUBOTheme.secondary)
                    .padding(10).frame(maxWidth: .infinity)
            }
            NoteCard(note: note, timelineStyle: true, hideSensitive: hideSensitive)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: first ? 12 : 0,
            bottomLeadingRadius: last ? 12 : 0, bottomTrailingRadius: last ? 12 : 0,
            topTrailingRadius: first ? 12 : 0))
        .padding(.horizontal, 12)
    }
}

struct NoteReactionStrip: View {
    let note: Record
    let disabled: Bool
    let pulse: Bool
    let choose: (String) -> Void
    let more: () -> Void
    private var keys: [String] { Array(note["reactions"].object.keys.sorted().prefix(16)) }

    var body: some View {
        Group {
            if note["reactionAcceptance"].string != "likeOnly" {
                FlowReactionLayout {
                    ForEach(keys, id: \.self) { reaction in
                        NoteReactionButton(reaction: reaction,
                            count: note["reactions"][reaction].int,
                            emojis: note["reactionEmojis"],
                            selected: note["myReaction"].string == reaction,
                            pulse: pulse, identifier: "note.reaction." + note.id + "." + reaction,
                            action: { choose(reaction) })
                            .disabled(disabled)
                    }
                    if note["reactions"].object.count > 16 {
                        Button("更多反应", action: more).font(.caption).frame(minHeight: 32)
                    }
                }
            }
        }
    }
}

private struct NoteReactionButton: View {
    let reaction: String
    let count: Int
    let emojis: JSONValue
    let selected: Bool
    let pulse: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ReactionImage(reaction: reaction, emojis: emojis)
                Text("\(count)").font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(selected ? PUBOTheme.accent.opacity(0.22) : PUBOTheme.button,
                in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? PUBOTheme.accent : Color.clear))
            .scaleEffect(pulse && selected ? 1.16 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reaction + " \(count)")
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityIdentifier(identifier)
    }
}
