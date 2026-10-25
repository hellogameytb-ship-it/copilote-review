// Generates the binary files of the fictional demo base (fixtures/base-demo): drawn photos with
// EXIF day + GPS, the Revisio screenshot, a PDF and a DOCX reference. Deterministic.
//   swift scripts/make_base_demo_assets.swift
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let base = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/base-demo")

enum Scene { case beach, city, tram, night, mountain, temple, garden, castle, food, street }

struct Photo {
    let folder: String
    let name: String
    let day: String  // "2026:07:08 18:20:00"
    let place: (Double, Double)?
    let scene: Scene
}

let lisbon = (38.7139, -9.1394), ericeira = (38.9637, -9.4176), porto = (41.1496, -8.6109)
let tokyo = (35.6762, 139.6503), kyoto = (35.0116, 135.7681), edinburgh = (55.9533, -3.1883)

let photos: [Photo] = [
    Photo(folder: "portugal-2026", name: "01-lisbonne-alfama.jpg", day: "2026:07:06 19:12:00", place: lisbon, scene: .city),
    Photo(folder: "portugal-2026", name: "02-tram-28.jpg", day: "2026:07:07 08:40:00", place: lisbon, scene: .tram),
    Photo(folder: "portugal-2026", name: "03-pasteis.jpg", day: "2026:07:08 16:05:00", place: lisbon, scene: .food),
    Photo(folder: "portugal-2026", name: "04-ericeira-surf.jpg", day: "2026:07:10 10:30:00", place: ericeira, scene: .beach),
    Photo(folder: "portugal-2026", name: "05-ericeira-coucher.jpg", day: "2026:07:11 21:02:00", place: ericeira, scene: .beach),
    Photo(folder: "portugal-2026", name: "06-porto-ribeira.jpg", day: "2026:07:15 18:44:00", place: porto, scene: .street),
    Photo(folder: "portugal-2026", name: "07-porto-pont.jpg", day: "2026:07:16 22:10:00", place: porto, scene: .night),
    Photo(folder: "portugal-2026", name: "08-porto-jardin.jpg", day: "2026:07:18 11:20:00", place: porto, scene: .garden),
    Photo(folder: "japon-2025", name: "01-tokyo-shibuya.jpg", day: "2025:04:03 20:15:00", place: tokyo, scene: .night),
    Photo(folder: "japon-2025", name: "02-tokyo-ramen.jpg", day: "2025:04:05 13:00:00", place: tokyo, scene: .food),
    Photo(folder: "japon-2025", name: "03-kyoto-temple.jpg", day: "2025:04:10 09:30:00", place: kyoto, scene: .temple),
    Photo(folder: "japon-2025", name: "04-kyoto-jardin.jpg", day: "2025:04:11 15:45:00", place: kyoto, scene: .garden),
    Photo(folder: "japon-2025", name: "05-kyoto-montagne.jpg", day: "2025:04:13 07:50:00", place: kyoto, scene: .mountain),
    Photo(folder: "ecosse-2025", name: "01-edimbourg-chateau.jpg", day: "2025:12:21 15:10:00", place: edinburgh, scene: .castle),
    Photo(folder: "ecosse-2025", name: "02-edimbourg-rue.jpg", day: "2025:12:22 17:30:00", place: edinburgh, scene: .street),
    Photo(folder: "ecosse-2025", name: "03-arthurs-seat.jpg", day: "2025:12:24 11:00:00", place: edinburgh, scene: .mountain),
    Photo(folder: "divers", name: "escalade-salle.jpg", day: "2026:02:14 19:00:00", place: nil, scene: .mountain),
    Photo(folder: "divers", name: "soupe-legumes.jpg", day: "2026:01:04 12:30:00", place: nil, scene: .food),
    Photo(folder: "divers", name: "annecy-lac.jpg", day: "2026:05:02 17:20:00", place: (45.8992, 6.1294), scene: .garden),
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func gradient(_ context: CGContext, _ colors: [UInt32], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map { color($0) } as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// A drawn, recognisable scene (no real photo of anyone).
func draw(_ scene: Scene, seed: Int, width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    var random = UInt64(seed * 7919 + 17)
    func next() -> CGFloat {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(random >> 33) / CGFloat(UInt32.max >> 1)
    }
    switch scene {
    case .beach:
        gradient(context, [0xf6b26b, 0xf9d9a8, 0x7fb3d5], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.45))
        context.setFillColor(color(0xffe08a)); context.fillEllipse(in: CGRect(x: w * 0.62, y: h * 0.52, width: h * 0.16, height: h * 0.16))
        context.setFillColor(color(0x2e6f95)); context.fill(CGRect(x: 0, y: h * 0.22, width: w, height: h * 0.23))
        context.setFillColor(color(0xe9d3a6)); context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.22))
        context.setStrokeColor(color(0xffffff, 0.55)); context.setLineWidth(3)
        for row in 0..<5 { let y = h * (0.25 + CGFloat(row) * 0.04); context.move(to: CGPoint(x: w * next() * 0.3, y: y)); context.addLine(to: CGPoint(x: w * (0.5 + next() * 0.5), y: y)); context.strokePath() }
    case .city, .street:
        gradient(context, scene == .city ? [0xbcd4e6, 0xf2e2c4] : [0xd9a07a, 0x8e6c88], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.3))
        let palette: [UInt32] = [0xe8c39e, 0xd98f6b, 0xf4e1c1, 0xc97b63, 0xe6d3a3, 0x9fb7c9]
        var x: CGFloat = 0
        while x < w {
            let bw = w * (0.08 + next() * 0.08), bh = h * (0.3 + next() * 0.35)
            context.setFillColor(color(palette[Int(next() * 5.99)])); context.fill(CGRect(x: x, y: 0, width: bw, height: bh))
            context.setFillColor(color(0x4a3b35, 0.55))
            var wy = bh * 0.15
            while wy < bh - 20 { context.fill(CGRect(x: x + bw * 0.2, y: wy, width: bw * 0.18, height: 14)); context.fill(CGRect(x: x + bw * 0.6, y: wy, width: bw * 0.18, height: 14)); wy += 34 }
            x += bw + 2
        }
    case .tram:
        gradient(context, [0x9cc3e0, 0xf3ead8], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.4))
        context.setFillColor(color(0xd8c3a5)); context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.3))
        context.setFillColor(color(0xf2c230)); context.fill(CGRect(x: w * 0.2, y: h * 0.18, width: w * 0.55, height: h * 0.34))
        context.setFillColor(color(0xf7f1e3)); context.fill(CGRect(x: w * 0.2, y: h * 0.18, width: w * 0.55, height: h * 0.07))
        context.setFillColor(color(0x3b4a5a, 0.8))
        for i in 0..<5 { context.fill(CGRect(x: w * (0.24 + CGFloat(i) * 0.1), y: h * 0.32, width: w * 0.07, height: h * 0.12)) }
        context.setStrokeColor(color(0x333333)); context.setLineWidth(3); context.move(to: CGPoint(x: 0, y: h * 0.62)); context.addLine(to: CGPoint(x: w, y: h * 0.66)); context.strokePath()
    case .night:
        gradient(context, [0x0b1026, 0x2b1d4f], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: 0))
        for _ in 0..<40 { context.setFillColor(color(0xffffff, 0.3 + next() * 0.6)); context.fillEllipse(in: CGRect(x: next() * w, y: h * (0.5 + next() * 0.5), width: 3, height: 3)) }
        var x: CGFloat = 0
        while x < w {
            let bw = w * (0.06 + next() * 0.07), bh = h * (0.25 + next() * 0.4)
            context.setFillColor(color(0x151a33)); context.fill(CGRect(x: x, y: 0, width: bw, height: bh))
            for _ in 0..<Int(bh / 30) { context.setFillColor(color([0xffd27a, 0xff7ab6, 0x7ad7ff][Int(next() * 2.99)], 0.85)); context.fill(CGRect(x: x + next() * (bw - 10), y: next() * bh, width: 8, height: 10)) }
            x += bw + 3
        }
    case .mountain:
        gradient(context, [0x8fb8de, 0xe8f1f8], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.3))
        for (layer, tint) in [(0, 0x6b7f99), (1, 0x4f6478), (2, 0x3b4d3f)] as [(Int, UInt32)] {
            context.setFillColor(color(tint)); context.move(to: CGPoint(x: 0, y: 0))
            var x: CGFloat = 0
            while x <= w { context.addLine(to: CGPoint(x: x, y: h * (0.35 - CGFloat(layer) * 0.08 + next() * 0.25))); x += w / 6 }
            context.addLine(to: CGPoint(x: w, y: 0)); context.closePath(); context.fillPath()
        }
    case .temple:
        gradient(context, [0xf7d9c4, 0xfbeee2], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.3))
        context.setFillColor(color(0x5c7a4a)); context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.22))
        context.setFillColor(color(0xc8382e))
        context.fill(CGRect(x: w * 0.3, y: h * 0.22, width: w * 0.04, height: h * 0.45)); context.fill(CGRect(x: w * 0.66, y: h * 0.22, width: w * 0.04, height: h * 0.45))
        context.fill(CGRect(x: w * 0.24, y: h * 0.67, width: w * 0.52, height: h * 0.05)); context.fill(CGRect(x: w * 0.28, y: h * 0.58, width: w * 0.44, height: h * 0.03))
        for _ in 0..<30 { context.setFillColor(color(0xf4a6c1, 0.7)); context.fillEllipse(in: CGRect(x: next() * w, y: h * (0.6 + next() * 0.4), width: 18, height: 18)) }
    case .garden:
        gradient(context, [0xcfe8d5, 0xf3f7ea], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.4))
        context.setFillColor(color(0x7aa874)); context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.35))
        for _ in 0..<9 {
            let x = next() * w, size = h * (0.18 + next() * 0.18)
            context.setFillColor(color(0x6b4f3a)); context.fill(CGRect(x: x + size * 0.45, y: h * 0.3, width: size * 0.1, height: size * 0.6))
            context.setFillColor(color([0x3f7d4e, 0x5e9b5a, 0x88b04b][Int(next() * 2.99)])); context.fillEllipse(in: CGRect(x: x, y: h * 0.3 + size * 0.45, width: size, height: size))
        }
    case .castle:
        gradient(context, [0x9aa7b8, 0xd7dde5], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.3))
        context.setFillColor(color(0x5b5f57)); context.move(to: CGPoint(x: 0, y: 0)); context.addLine(to: CGPoint(x: 0, y: h * 0.3)); context.addLine(to: CGPoint(x: w * 0.4, y: h * 0.42)); context.addLine(to: CGPoint(x: w, y: h * 0.28)); context.addLine(to: CGPoint(x: w, y: 0)); context.closePath(); context.fillPath()
        context.setFillColor(color(0x6e6a63))
        context.fill(CGRect(x: w * 0.3, y: h * 0.4, width: w * 0.4, height: h * 0.2))
        for i in 0..<4 { context.fill(CGRect(x: w * (0.3 + CGFloat(i) * 0.12), y: h * 0.6, width: w * 0.06, height: h * 0.06)) }
        context.fill(CGRect(x: w * 0.44, y: h * 0.6, width: w * 0.08, height: h * 0.16))
    case .food:
        gradient(context, [0x8a5a3c, 0x5e3b26], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: 0))
        context.setFillColor(color(0xf5efe6)); context.fillEllipse(in: CGRect(x: w * 0.25, y: h * 0.12, width: w * 0.5, height: h * 0.76))
        for _ in 0..<5 {
            let x = w * (0.33 + next() * 0.25), y = h * (0.25 + next() * 0.4)
            context.setFillColor(color(0xe9a948)); context.fillEllipse(in: CGRect(x: x, y: y, width: w * 0.1, height: w * 0.1))
            context.setFillColor(color(0x7a3e12, 0.8)); context.fillEllipse(in: CGRect(x: x + w * 0.03, y: y + w * 0.03, width: w * 0.035, height: w * 0.035))
        }
    }
    return context.makeImage()!
}

func writeJPEG(_ image: CGImage, to url: URL, exif: [String: Any], gps: [String: Any]?) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var properties: [String: Any] = [kCGImagePropertyExifDictionary as String: exif, kCGImageDestinationLossyCompressionQuality as String: 0.62]
    if let gps { properties[kCGImagePropertyGPSDictionary as String] = gps }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
}

for (index, photo) in photos.enumerated() {
    let image = draw(photo.scene, seed: index + 1, width: 800, height: 600)
    var gps: [String: Any]?
    if let (latitude, longitude) = photo.place {
        gps = [
            kCGImagePropertyGPSLatitude as String: abs(latitude), kCGImagePropertyGPSLatitudeRef as String: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(longitude), kCGImagePropertyGPSLongitudeRef as String: longitude >= 0 ? "E" : "W",
        ]
    }
    writeJPEG(image, to: base.appendingPathComponent("photos/\(photo.folder)/\(photo.name)"),
              exif: [kCGImagePropertyExifDateTimeOriginal as String: photo.day], gps: gps)
}

// Revisio's screenshot: a drawn mock-up of the quiz screen.
do {
    let width = 1200, height = 750
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    context.setFillColor(color(0x15151c)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.setFillColor(color(0x1f1f2a)); context.fill(CGRect(x: 0, y: 0, width: w * 0.22, height: h))
    context.setFillColor(color(0x2a2a38))
    for i in 0..<6 { context.fill(CGRect(x: 24, y: h - 120 - CGFloat(i) * 56, width: w * 0.22 - 48, height: 36)) }
    context.setFillColor(color(0x7b73d9)); context.fill(CGRect(x: 24, y: h - 120, width: w * 0.22 - 48, height: 36))
    func text(_ string: String, size: CGFloat, at point: CGPoint, color hex: UInt32, bold: Bool = false) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex),
        ]))
        context.textPosition = point
        CTLineDraw(line, context)
    }
    text("revisio", size: 30, at: CGPoint(x: 28, y: h - 64), color: 0xececf1, bold: true)
    text("Quiz · Algorithmique, chapitre 4", size: 28, at: CGPoint(x: w * 0.26, y: h - 80), color: 0xececf1, bold: true)
    text("Question 3 sur 10 · généré à partir de tes notes du 12 mars", size: 18, at: CGPoint(x: w * 0.26, y: h - 116), color: 0x9a9ab0)
    context.setFillColor(color(0x23232f)); context.fill(CGRect(x: w * 0.26, y: h * 0.38, width: w * 0.7, height: h * 0.36))
    text("Quelle est la complexité d'une recherche dans un arbre binaire équilibré ?", size: 22, at: CGPoint(x: w * 0.28, y: h * 0.66), color: 0xececf1)
    for (i, answer) in ["O(1)", "O(log n)", "O(n)", "O(n log n)"].enumerated() {
        let y = h * (0.56 - CGFloat(i) * 0.045)
        context.setFillColor(color(i == 1 ? 0x3d376e : 0x2a2a38)); context.fill(CGRect(x: w * 0.28, y: y - 10, width: w * 0.3, height: 30))
        text(answer, size: 18, at: CGPoint(x: w * 0.3, y: y), color: i == 1 ? 0xd9d4ff : 0xc4c4d4)
    }
    context.setFillColor(color(0xe0a84a)); context.fill(CGRect(x: w * 0.26, y: h * 0.2, width: w * 0.7 * 0.3, height: 10))
    context.setFillColor(color(0x2a2a38)); context.fill(CGRect(x: w * 0.26 + w * 0.7 * 0.3, y: h * 0.2, width: w * 0.7 * 0.7, height: 10))
    text("Série en cours : 6 jours", size: 18, at: CGPoint(x: w * 0.26, y: h * 0.14), color: 0x9a9ab0)
    let url = base.appendingPathComponent("projets/captures/revisio.png")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

// References: a PDF transcript and a DOCX internship certificate, both fictional.
let transcript = """
Université de Valmont — Relevé de notes (document fictif)
Étudiante : Camille Ferrand · Master informatique, première année (2024–2025)

Systèmes distribués : 16,5 / 20
Développement web avancé : 15,0 / 20
Interaction humain-machine : 14,5 / 20
Bases de données réparties : 15,5 / 20
Projet tutoré (Revisio, première version) : 17,0 / 20

Moyenne générale : 15,2 / 20 · Mention bien · Rang : 6 sur 48
"""
do {
    let url = base.appendingPathComponent("reference/releve-notes-m1.pdf")
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
    pdf.beginPDFPage(nil)
    let attributed = NSAttributedString(string: transcript, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: box.insetBy(dx: 56, dy: 64), transform: nil), nil)
    CTFrameDraw(frame, pdf)
    pdf.endPDFPage()
    pdf.closePDF()
}
do {
    let certificate = """
    Logisto SAS (entreprise fictive) — Attestation de stage

    Nous attestons que Camille Ferrand a effectué un stage de développeuse backend au sein de notre équipe plateforme, à Lyon, du 2 juin au 29 août 2025.

    Elle a conçu trois API Python de suivi logistique et mis en place une file de tâches qui a réduit de 28 % le temps moyen de traitement des envois. Son autonomie et la clarté de sa documentation ont été appréciées par toute l'équipe.

    Fait à Lyon, le 29 août 2025. Responsable de stage : Julien Mercadier.
    """
    let attributed = NSAttributedString(string: certificate, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    let data = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    try data.write(to: base.appendingPathComponent("reference/attestation-stage.docx"))
}
print("ok: \(photos.count) photos, 1 capture, 1 PDF, 1 DOCX in \(base.path)")
