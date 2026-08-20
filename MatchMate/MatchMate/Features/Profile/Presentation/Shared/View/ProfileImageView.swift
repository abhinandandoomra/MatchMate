import SwiftUI
import UIKit

/// Renders cached portrait bytes, and draws its own placeholder when there are
/// none — while the image is still being fetched, or after a permanent failure.
///
/// The placeholder is generated LOCALLY from the person's initials. It never
/// points at an external placeholder or avatar service: the brief forbids it,
/// and a remote fallback would also defeat the offline-first cache.
@MainActor
struct ProfileImageView: View {
    @Environment(\.profileStyle) private var style
    let imageData: Data?
    let initials: String
    var cornerRadius: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(side: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? style.radius.thumbnail, style: .continuous))
        .accessibilityHidden(true)
    }

    private var uiImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }

    private func placeholder(side: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(style.opacity.gradientTop), tint.opacity(style.opacity.gradientBottom)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(.system(
                    size: max(style.placeholder.minimumInitialsSize,
                              side * style.placeholder.initialsScale),
                    weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(style.text.minimumScaleFactor)
                .lineLimit(style.text.nameLineLimit)
        }
    }

    /// Stable across launches — derived from the initials rather than from
    /// `hashValue`, which is seeded per-process and would change colour on
    /// every cold start.
    private var tint: Color {
        let degrees = style.placeholder.hueDegrees
        let sum = initials.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(sum % Int(degrees)) / degrees
        return Color(hue: hue,
                     saturation: style.placeholder.saturation,
                     brightness: style.placeholder.brightness)
    }
}
