import SwiftUI

struct HgPalette {
    let paper: Color
    let ink: Color
    let muted: Color
    let faint: Color
    let card: Color
    let line: Color
    let accent: Color
    let onAccent: Color
    let soft: Color
    let danger: Color

    static let light = HgPalette(
        paper: Color(red: 0.980, green: 0.976, blue: 0.961),
        ink: Color(red: 0.102, green: 0.098, blue: 0.082),
        muted: Color(red: 0.431, green: 0.416, blue: 0.384),
        faint: Color(red: 0.604, green: 0.584, blue: 0.549),
        card: .white,
        line: Color(red: 0.906, green: 0.890, blue: 0.847),
        accent: Color(red: 0.788, green: 0.392, blue: 0.259),
        onAccent: Color(red: 1, green: 0.973, blue: 0.957),
        soft: Color(red: 0.965, green: 0.906, blue: 0.878),
        danger: Color(red: 0.706, green: 0.137, blue: 0.094)
    )

    static let dark = HgPalette(
        paper: Color(red: 0.110, green: 0.106, blue: 0.098),
        ink: Color(red: 0.953, green: 0.941, blue: 0.910),
        muted: Color(red: 0.698, green: 0.675, blue: 0.635),
        faint: Color(red: 0.541, green: 0.518, blue: 0.478),
        card: Color(red: 0.149, green: 0.145, blue: 0.133),
        line: Color(red: 0.227, green: 0.220, blue: 0.200),
        accent: Color(red: 0.878, green: 0.541, blue: 0.431),
        onAccent: Color(red: 0.165, green: 0.071, blue: 0.047),
        soft: Color(red: 0.227, green: 0.173, blue: 0.149),
        danger: Color(red: 1, green: 0.706, blue: 0.659)
    )
}

private struct HgKey: EnvironmentKey {
    static let defaultValue = HgPalette.light
}

extension EnvironmentValues {
    var hg: HgPalette {
        get { self[HgKey.self] }
        set { self[HgKey.self] = newValue }
    }
}

extension Font {
    static func hgTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }
}
