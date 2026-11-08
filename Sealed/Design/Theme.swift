import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    // Palette from the design canvas.
    static let sBackground = Color(hex: 0x0E1013)
    static let sSurface = Color(hex: 0x171A1F)
    static let sSurfaceRaised = Color(hex: 0x2A2F37)
    static let sLine = Color(hex: 0x262A31)
    static let sText = Color(hex: 0xEDEEF0)
    static let sSecondary = Color(hex: 0xC9CDD3)
    static let sMuted = Color(hex: 0x9BA1AB)
    static let sAccent = Color(hex: 0x7BE0B5)
    static let sWarn = Color(hex: 0xF2B36F)
    static let sSuccessBg = Color(hex: 0x1A2420)
    static let sSuccessLine = Color(hex: 0x2C4A3E)
    static let sWarnBg = Color(hex: 0x251E15)
    static let sWarnLine = Color(hex: 0x4A3820)
}

extension Font {
    static let sDisplay = Font.system(size: 34, weight: .semibold)
    static let sMono = Font.system(size: 13, design: .monospaced)
    static let sMonoSmall = Font.system(size: 11, design: .monospaced)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.sBackground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.sAccent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.sText)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.sSurface.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sLine))
    }
}

struct CardModifier: ViewModifier {
    var selected = false
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Color.sAccent : Color.sLine, lineWidth: selected ? 1.5 : 1))
    }
}

extension View {
    func card(selected: Bool = false, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(selected: selected, padding: padding))
    }

    func fieldStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color.sSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sLine))
    }

    func sectionLabel() -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.sMuted)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

/// Small rounded initials circle used for contacts and hosts.
struct Avatar: View {
    var initials: String
    var size: CGFloat = 38

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(Color.sText)
            .frame(width: size, height: size)
            .background(Color.sSurfaceRaised, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Labelled text field matching the mocks.
struct LabeledField<Field: View>: View {
    var label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sMuted)
            field.fieldStyle()
        }
    }
}
