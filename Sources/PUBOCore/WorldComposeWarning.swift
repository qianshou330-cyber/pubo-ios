public enum WorldComposeWarning {
    /// Match the archived H5 nonblank check, without rewriting the annotation or its length limit.
    public static func needsAnnotation(enabled: Bool, text: String, isReply: Bool, isQuote: Bool, isChannel: Bool) -> Bool {
        guard enabled, !isReply, !isQuote, !isChannel else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            // ECMAScript TrimString WhiteSpace and LineTerminator code points.
            switch scalar.value {
            case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
                 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
                return true
            default:
                return false
            }
        }
    }
}
