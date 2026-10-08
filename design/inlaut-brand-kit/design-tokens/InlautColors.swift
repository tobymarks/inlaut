import SwiftUI

enum InlautColors {
    static let petrol = Color(red: 16/255, green: 61/255, blue: 59/255)
    static let mint = Color(red: 188/255, green: 235/255, blue: 217/255)
    static let porcelain = Color(red: 246/255, green: 247/255, blue: 244/255)
    static func accent(for scheme: ColorScheme) -> Color { scheme == .dark ? mint : Color(red: 35/255, green: 110/255, blue: 100/255) }
}
