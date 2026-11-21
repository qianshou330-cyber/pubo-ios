/// Presentation eligibility only. The server still decides whether any action is authorized.
public enum WorldReshareVisibility {
    public static func canShowMenu(row: Record, viewerID: String?) -> Bool {
        guard let viewerID, isID(viewerID), isID(row.id) else { return false }
        let target = NoteContext.displayed(row)
        guard isID(target.id), !target["isHidden"].bool, !NoteContext.isRepost(target) else { return false }
        if NoteContext.isRepost(row) {
            // Do not apply the wrapper's visibility/author if the original is unresolved.
            guard let original = row["renote"]["id"].string, isID(original),
                  original == target.id, original != row.id else { return false }
            if !row["renoteId"].isNull, row["renoteId"].string != original { return false }
        }
        switch target["visibility"].string {
        case "public", "home":
            return true
        case "followers":
            guard let author = target["userId"].string, isID(author) else { return false }
            let packedAuthor = target["user"]["id"]
            if !packedAuthor.isNull, packedAuthor.string != author { return false }
            return author == viewerID
        default:
            return false
        }
    }

    private static func isID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            switch byte {
            case 45, 48...57, 65...90, 95, 97...122: return true
            default: return false
            }
        }
    }
}
