import AppKit
import SwiftUI

enum ReadingAppearance: String, CaseIterable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var appAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}

enum Palette {
  static let paper = adaptive(
    light: Color(red: 0.97, green: 0.96, blue: 0.94),
    dark: Color(red: 0.11, green: 0.12, blue: 0.12))
  static let surface = adaptive(light: .white, dark: Color(red: 0.17, green: 0.19, blue: 0.18))
  static let ink = adaptive(
    light: Color(red: 0.16, green: 0.20, blue: 0.18),
    dark: Color(red: 0.91, green: 0.92, blue: 0.88))
  static let green = adaptive(
    light: Color(red: 0.21, green: 0.36, blue: 0.29),
    dark: Color(red: 0.62, green: 0.81, blue: 0.69))
  static let muted = adaptive(
    light: Color(red: 0.40, green: 0.43, blue: 0.39),
    dark: Color(red: 0.69, green: 0.73, blue: 0.69))
  static let line = adaptive(
    light: Color(red: 0.85, green: 0.86, blue: 0.81),
    dark: Color(red: 0.28, green: 0.31, blue: 0.29))

  private static func adaptive(light: Color, dark: Color) -> Color {
    let lightColor = NSColor(light)
    let darkColor = NSColor(dark)
    return Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
      })
  }
}
