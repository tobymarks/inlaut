import SwiftUI

/// Use the kit's vector wordmark; all interface copy stays in the system font.
struct InlautBrandHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image("InlautWordmark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 36)
                .foregroundStyle(Color.inlautBrand)
                .accessibilityLabel("inlaut")
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.inlautInk)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.inlautMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
