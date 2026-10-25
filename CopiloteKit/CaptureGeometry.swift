import CoreGraphics

/// Maps a region selected on screen to the pixels of the frozen screenshot.
public enum CaptureGeometry {
    /// Pixels per point of a screenshot covering a view of `viewWidth` points.
    public static func scale(viewWidth: CGFloat, imageWidth: Int) -> CGFloat {
        CGFloat(imageWidth) / max(viewWidth, 1)
    }

    /// `selection` is in the view's points (origin bottom-left, the view covering the screenshot);
    /// the result is in image pixels (origin top-left), grown to whole pixels.
    public static func pixelRect(for selection: CGRect, viewSize: CGSize, imageWidth: Int) -> CGRect {
        let scale = scale(viewWidth: viewSize.width, imageWidth: imageWidth)
        return CGRect(
            x: selection.minX * scale,
            y: (viewSize.height - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral
    }
}
