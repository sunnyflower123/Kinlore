import SwiftUI

/// Design constants that keep the app usable for an 80-year-old.
///
/// These are not style preferences but the core of the product: if a screen does
/// not work at the largest text size, it is not done. Apple's minimum tap target
/// is 44 pt, but that is designed for a steady hand — we use 60 pt.
enum Elder {
    /// The smallest tap target. Never below this, not even for secondary
    /// actions.
    static let minTapTarget: CGFloat = 60

    /// The diameter of the record button. It is the app's most important
    /// control, and it has to be findable without reading.
    static let recordButtonSize: CGFloat = 200

    /// Body text leading. Generous line spacing helps a person with poor
    /// eyesight keep their place on the line.
    static let lineSpacing: CGFloat = 6

    static let screenPadding: CGFloat = 24
}

extension View {
    /// Ensures a control is large enough regardless of the size of its content.
    func elderTapTarget() -> some View {
        frame(minWidth: Elder.minTapTarget, minHeight: Elder.minTapTarget)
            .contentShape(Rectangle())
    }

    /// Body text styling: generous leading, never a line limit. A truncated
    /// memory is a lost memory.
    func elderBody() -> some View {
        font(.body)
            .lineSpacing(Elder.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
