import SwiftUI

enum NotchPresentation: Equatable {
  case compact
  case expanded
}

enum TeleprompterNotchLayout {
  static let expandedMinimumSize = CGSize(width: 460, height: 220)
  static let defaultExpandedSize = CGSize(width: 720, height: 340)
  static let compactWingWidth: CGFloat = 92
  static let compactExtraHeight: CGFloat = 10
  private static let expandedAccessoryWidth: CGFloat = 128

  static func attachedExpandedMinimumSize(notchWidth: CGFloat) -> CGSize {
    CGSize(
      width: max(
        expandedMinimumSize.width,
        notchWidth + compactWingWidth * 2 + expandedAccessoryWidth * 2
      ),
      height: expandedMinimumSize.height
    )
  }

  static func compactSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
    CGSize(
      width: max(320, notchWidth + compactWingWidth * 2),
      height: max(42, notchHeight + compactExtraHeight)
    )
  }
}

/// A screen-top silhouette that visually grows out of the MacBook camera housing.
/// Inspired by DynamicNotchKit's notch-connected presentation; see
/// `THIRD_PARTY_NOTICES.md` for attribution.
struct TeleprompterNotchShape: Shape {
  var topShoulderRadius: CGFloat
  var bottomCornerRadius: CGFloat

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(topShoulderRadius, bottomCornerRadius) }
    set {
      topShoulderRadius = newValue.first
      bottomCornerRadius = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let maximumRadius = min(rect.width / 4, rect.height / 2)
    let shoulder = min(max(0, topShoulderRadius), maximumRadius)
    let bottom = min(max(0, bottomCornerRadius), maximumRadius)
    var path = Path()

    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addCurve(
      to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder),
      control1: CGPoint(x: rect.minX + shoulder * 0.62, y: rect.minY),
      control2: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder * 0.36)
    )
    path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - bottom))
    path.addCurve(
      to: CGPoint(x: rect.minX + shoulder + bottom, y: rect.maxY),
      control1: CGPoint(x: rect.minX + shoulder, y: rect.maxY - bottom * 0.35),
      control2: CGPoint(x: rect.minX + shoulder + bottom * 0.35, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - shoulder - bottom, y: rect.maxY))
    path.addCurve(
      to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - bottom),
      control1: CGPoint(x: rect.maxX - shoulder - bottom * 0.35, y: rect.maxY),
      control2: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - bottom * 0.35)
    )
    path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control1: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder * 0.36),
      control2: CGPoint(x: rect.maxX - shoulder * 0.62, y: rect.minY)
    )
    path.closeSubpath()
    return path
  }
}
