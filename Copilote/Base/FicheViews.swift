import AppKit
import CopiloteKit
import SwiftUI

// The personal fiches shown in the overlay. Shared with `copilote-render` (off-screen PNGs with
// ImageRenderer), so: SwiftUI and CopiloteKit only, images loaded synchronously, no lazy stacks.

enum FicheStyle {
    /// The one accent: same violet as `--accent` in overlay.css; `AccentColor.colorset` is its deep
    /// tone, for system controls filled under a white label.
    static let accent = Color(red: 0.66, green: 0.61, blue: 1.0)
    /// The deep tone (the AccentColor asset, #6c5ae2): filled controls with white text (5,2:1).
    static let accentFill = Color(red: 0.422, green: 0.354, blue: 0.886)
    /// Lighter than the panel's material: the card is what you read and act on.
    static let surface = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.08)
    /// Errors: the answer page's `--danger` (≈ 5.5:1 on a card, where the system red is 3.7:1).
    static let danger = Color(red: 1.0, green: 0.54, blue: 0.5)

    /// An edge: as given, or one you can see with "Increase contrast" (stronger still for emphasis).
    static func edge(_ normal: Color, contrast: ColorSchemeContrast, emphasized: Bool = false) -> Color {
        guard contrast == .increased else { return normal }
        return Color.white.opacity(emphasized ? 0.6 : 0.3)
    }
    /// Critically damped: things settle without overshoot. A short fade with Reduce Motion.
    static func motion(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1)
    }
}

extension View {
    /// The card chrome of the panel: a solid surface lighter than the material, a thin edge.
    func ficheCard(padding: CGFloat = 12) -> some View {
        modifier(FicheCard(padding: padding))
    }
}

private struct FicheCard: ViewModifier {
    let padding: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.padding(padding)
            .background(FicheStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(FicheStyle.edge(FicheStyle.stroke, contrast: contrast), lineWidth: 1)
            )
    }
}

/// Thumbnails and captures are small files read once and kept.
final class FicheImages {
    static let shared = FicheImages()
    private let cache = NSCache<NSURL, NSImage>()

    func image(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Fiche text as written in Markdown: "- " lists as bullets, inline bold and italics kept.
func ficheText(_ text: String) -> Text {
    let bulleted = text.components(separatedBy: "\n")
        .map { $0.hasPrefix("- ") ? "• " + $0.dropFirst(2) : $0 }
        .joined(separator: "\n")
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return Text((try? AttributedString(markdown: bulleted, options: options)) ?? AttributedString(bulleted))
}

/// A full fiche: the card for its kind, then where it comes from and what you can do.
struct FicheView: View {
    let fiche: Fiche
    var onAnswer: (() -> Void)?
    var onClose: (() -> Void)?
    /// An answer is on screen: the fiche can fold back to one line.
    var onFold: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: fiche.symbol).font(.system(size: 10, weight: .semibold))
                Text(fiche.kindName.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                Spacer()
                if let onFold {
                    Button(action: onFold) {
                        Image(systemName: "chevron.up").font(.system(size: 9.5, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .overlayHint("Replier la fiche")
                    .accessibilityLabel("Replier la fiche")
                }
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Absolute, not hierarchical: the header around it is accent-coloured.
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Close source card")
                }
            }
            .foregroundStyle(FicheStyle.accent)

            switch fiche.content {
            case let .project(card): ProjectCardContent(card: card)
            case let .trip(card): TripCardContent(card: card)
            case let .photos(grid): PhotoGridContent(grid: grid)
            case let .extract(extract): ExtractContent(extract: extract)
            }

            if let onAnswer {
                Button(action: onAnswer) {
                    Label("Answer using this source card", systemImage: "text.bubble")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FicheStyle.accent)
            }
        }
        .ficheCard()
    }
}

/// The fiche folded above an answer: what to say comes first, the fiche stays one click away.
struct FicheFoldedLine: View {
    let fiche: Fiche
    let onOpen: () -> Void
    var onClose: (() -> Void)?

    var body: some View {
        let line = fiche.foldedLine
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: fiche.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(FicheStyle.accent)
                    (Text(line.title).font(.system(size: 12, weight: .semibold))
                        + Text(line.detail.map { " · \($0)" } ?? "").font(.system(size: 12)).foregroundStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlayHint("Expand source card")
            .accessibilityLabel([fiche.kindName, line.title, line.detail].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint("Expand source card")
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Close source card")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(FicheStyle.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(FicheStyle.stroke, lineWidth: 1))
    }
}

extension Fiche {
    /// The kind's symbol, the same open or folded.
    var symbol: String {
        switch content {
        case .project: return "hammer"
        case .trip: return "airplane"
        case .photos: return "photo.on.rectangle"
        case let .extract(extract):
            switch extract.kind {
            case .cv: return "person.text.rectangle"
            case .bio: return "person.crop.circle"
            case .reference: return "doc.text"
            case .opinion: return "quote.bubble"
            default: return "note.text"
            }
        }
    }
}

/// "Source found: Revisio — Afficher": the router was not sure enough to show it outright.
struct FicheSuggestion: View {
    let fiche: Fiche
    let onShow: () -> Void
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onShow) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.person.crop").font(.system(size: 11)).foregroundStyle(FicheStyle.accent)
                    Text("Source found: ").font(.system(size: 12)).foregroundStyle(.secondary)
                        + Text(fiche.title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 4)
                    Text("Show").font(.system(size: 11.5, weight: .medium)).foregroundStyle(FicheStyle.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(FicheStyle.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(FicheStyle.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: Project

private struct ProjectCardContent: View {
    let card: ProjectCard
    /// The diagram, opened large (it is wide: it scrolls sideways).
    @State private var diagramOpened = false
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FicheTitle(title: card.name, dates: card.dates)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    if let pitch = card.pitch {
                        Text(pitch).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    if !card.stack.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(card.stack, id: \.self) { StackBadge(name: $0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let capture = FicheImages.shared.image(card.capture) {
                    Image(nsImage: capture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 132, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(FicheStyle.stroke, lineWidth: 1))
                        .accessibilityLabel("Screenshot of \(card.name)")
                }
            }
            // The section asked about answers the question: before the diagram, not under it.
            if card.answersWithASection { highlightList }
            if let diagram = FicheImages.shared.image(card.diagram) {
                Group {
                    if diagramOpened {
                        ScrollView(.horizontal) {
                            Image(nsImage: diagram).resizable().aspectRatio(contentMode: .fit).frame(height: 230)
                        }
                        .matchedGeometryEffect(id: "diagram", in: space)
                        .overlayHint("Click to collapse")
                    } else {
                        Image(nsImage: diagram)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 130)
                            .matchedGeometryEffect(id: "diagram", in: space)
                            .overlayHint("Click to expand")
                    }
                }
                .padding(6)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(FicheStyle.motion(reduceMotion)) { diagramOpened.toggle() } }
                .accessibilityLabel("Architecture diagram for \(card.name)")
                .accessibilityHint(diagramOpened ? "Minimize" : "Expand")
                .accessibilityAddTraits(.isButton)
            }
            if !card.answersWithASection { highlightList }
            if let link = card.links.first {
                Text(link.replacingOccurrences(of: "https://", with: "")).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
    }

    private var highlightList: some View {
        ForEach(card.highlights, id: \.title) { highlight in
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                // Already cut on a word (FicheText.body): no second "…" from SwiftUI.
                ficheText(highlight.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StackBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10.5, weight: .medium))
            .tracking(0.1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(Color(red: 0.86, green: 0.84, blue: 1.0))
            .background(FicheStyle.accent.opacity(0.17), in: Capsule())
    }
}

private struct FicheTitle: View {
    let title: String
    let dates: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .semibold)).tracking(-0.2).lineLimit(2)
            Spacer(minLength: 4)
            if let dates {
                Text(dates).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Trip and photos

private struct TripCardContent: View {
    let card: TripCard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FicheTitle(title: card.place, dates: card.dates)
            if let summary = card.summary {
                ficheText(summary).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !card.photos.isEmpty {
                PhotoGridView(photos: card.photos)
            }
        }
    }
}

private struct PhotoGridContent: View {
    let grid: PhotoGrid

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FicheTitle(title: grid.title, dates: grid.subtitle)
            PhotoGridView(photos: grid.photos)
        }
    }
}

/// Square thumbnails, four per row; a click opens the photo in place, from its thumbnail, and
/// a second click sends it back the same way.
struct PhotoGridView: View {
    let photos: [PhotoThumb]
    private let columns = 4
    private let limit = 12
    @State private var opened: String?
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let opened, let photo = photos.first(where: { $0.id == opened }) {
                Button { toggle(photo) } label: {
                    PhotoImage(url: photo.thumbnail, fill: false)
                        .matchedGeometryEffect(id: photo.id, in: space)
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .overlay(alignment: .bottomLeading) { caption(photo) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close photo")
            } else {
                VStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(rows[row]) { photo in
                                Button { toggle(photo) } label: {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay(PhotoImage(url: photo.thumbnail, fill: true))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(alignment: .bottomTrailing) { more(photo) }
                                        .matchedGeometryEffect(id: photo.id, in: space)
                                }
                                .buttonStyle(PressScaleStyle())
                                .accessibilityLabel([photo.place, photo.day].compactMap { $0 }.joined(separator: ", "))
                            }
                            ForEach(0..<(columns - rows[row].count), id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                        }
                    }
                }
            }
            let places = photos.compactMap(\.place).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if !places.isEmpty {
                Text(places.joined(separator: " · ")).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var rows: [[PhotoThumb]] {
        let shown = Array(photos.prefix(limit))
        return stride(from: 0, to: shown.count, by: columns).map { Array(shown[$0..<min($0 + columns, shown.count)]) }
    }

    private func toggle(_ photo: PhotoThumb) {
        withAnimation(FicheStyle.motion(reduceMotion)) {
            opened = opened == photo.id ? nil : photo.id
        }
    }

    @ViewBuilder
    private func more(_ photo: PhotoThumb) -> some View {
        if photos.count > limit, photo.id == photos[limit - 1].id {
            Text("+\(photos.count - limit + 1)")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(4)
        }
    }

    private func caption(_ photo: PhotoThumb) -> some View {
        Text([photo.place, photo.day].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
    }
}

private struct PhotoImage: View {
    let url: URL
    let fill: Bool

    var body: some View {
        if let image = FicheImages.shared.image(url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
        } else {
            Rectangle().fill(Color.white.opacity(0.06)).overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
        }
    }
}

/// Feedback on press, at once.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: Extracts

private struct ExtractContent: View {
    let extract: Extract

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FicheTitle(title: extract.section.map { $0.components(separatedBy: " › ").last ?? $0 } ?? extract.title, dates: extract.dates)
            ficheText(extract.text).font(.system(size: 12.5)).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            Text(extract.source).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

// MARK: Layout

/// Badges that wrap onto the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
