import SwiftUI

public enum MinidiscColors {
    
    public static let accent = Color("MinidiscAccent")

    public static let accentBackground = Color("MinidiscAccentBackground")

    public static let accentForeground = Color("MinidiscAccentForeground")

    public static let backgroundPrimary = Color("MinidiscBackgroundPrimary")

    public static let backgroundSecondary = Color("MinidiscBackgroundSecondary")

    public static let backgroundTertiary = Color("MinidiscBackgroundTertiary")

    public static let textPrimary = Color("MinidiscTextPrimary")

    public static let textSecondary = Color("MinidiscTextSecondary")

    public static let textTertiary = Color("MinidiscTextTertiary")

    public static let separator = Color("MinidiscSeparator")

    public static let border = Color("MinidiscBorder")
    
    // MARK: — Accent Ramp (brand red stops, light-mode only — gradients, artwork tints, brand chips).
    public enum AccentRamp {
        public static let v50  = Color(hex: "#FFF0F2")
        public static let v100 = Color(hex: "#FFD9DE")
        public static let v200 = Color(hex: "#FFB0BB")
        public static let v300 = Color(hex: "#FF8996")
        public static let v400 = Color(hex: "#FA5B6E")
        public static let v500 = Color(hex: "#F32239") // brand chip base — keeps white legible (~4.7:1)
        public static let v600 = Color(hex: "#C51B2E")
        public static let v700 = Color(hex: "#941423")
        public static let v800 = Color(hex: "#690E19")
        public static let v900 = Color(hex: "#3E080F")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// AccentColor mirrors MinidiscAccent. Apply branded tints locally, not at WindowGroup,
// so secondary actions and alerts retain their contextual appearance.
