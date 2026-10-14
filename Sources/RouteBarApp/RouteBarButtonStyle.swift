import SwiftUI

struct RouteBarButtonStyle: ButtonStyle {
  var prominent = false
  var destructive = false
  var compact = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.custom("Manrope", size: 13).weight(.semibold))
      .foregroundStyle(foreground)
      .lineLimit(1).fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, compact ? 7 : 14)
      .frame(minWidth: compact ? 32 : 64, minHeight: compact ? 30 : 34)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(border))
      .brightness(configuration.isPressed && isEnabled ? -0.06 : 0)
      .contentShape(RoundedRectangle(cornerRadius: 7))
  }

  private var foreground: Color {
    if !isEnabled {
      return colorScheme == .dark
        ? Color(red: 0.65, green: 0.69, blue: 0.71)
        : Color(red: 0.36, green: 0.41, blue: 0.43)
    }
    if prominent { return .white }
    if destructive {
      return colorScheme == .dark
        ? Color(red: 1.0, green: 0.61, blue: 0.57)
        : Color(red: 0.68, green: 0.17, blue: 0.15)
    }
    return colorScheme == .dark
      ? Color(red: 0.84, green: 0.92, blue: 0.94)
      : Color(red: 0.09, green: 0.25, blue: 0.30)
  }

  private var background: Color {
    if !isEnabled {
      return colorScheme == .dark
        ? Color(red: 0.19, green: 0.21, blue: 0.22)
        : Color(red: 0.90, green: 0.92, blue: 0.92)
    }
    if prominent { return Color(red: 0.09, green: 0.25, blue: 0.30) }
    return Color(nsColor: .controlBackgroundColor)
  }

  private var border: Color {
    if prominent && isEnabled {
      return colorScheme == .dark ? Color.white.opacity(0.35) : .clear
    }
    return Color.primary.opacity(isEnabled ? 0.22 : 0.12)
  }
}
