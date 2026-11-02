import SwiftUI
import UIKit

// The Bloom logo, used wherever the leaf stood in as the brand mark (About
// header, Welcome screen). Decorative: the app name text sits beside it. If
// the BloomLogo asset is missing, the old leaf symbol is shown instead so
// nothing is blank. `onFill` draws that fallback on a filled circle.
struct BrandMark: View {
    var onFill = false

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 80

    private static let hasLogo = UIImage(named: "BloomLogo") != nil

    var body: some View {
        Group {
            if Self.hasLogo {
                Image("BloomLogo")
                    .resizable()
                    .scaledToFit()
            } else if onFill {
                ZStack {
                    Circle().fill(Theme.Colors.actionFill)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Theme.Colors.onActionFill)
                }
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(Theme.Colors.blooming)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
