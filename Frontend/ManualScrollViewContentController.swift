import Foundation
import AppKit
import QuartzCore

@MainActor
@objc final class ManualScrollViewContentController: NSObject, CookbookPageController {
    private let appConnection: OuterframeHost

    struct Layers {
        let rootLayer: CALayer
        let viewportLayer: CALayer
        let contentLayer: CALayer
        let backgroundLayer: CALayer
        let titleLayer: CATextLayer
        let subtitleLayer: CATextLayer
        let itemLayers: [CATextLayer]
    }

    private var layers: Layers? = nil

    private var currentSize: CGSize = .zero
    private var scrollOffset: CGFloat = 0

    private let scrollbarWidth: CGFloat = 8
    private let scrollbarInset: CGFloat = 4
    private var scrollbarController: ScrollbarController<ManualScrollViewContentController>?

    private let items = (1...60).map { "Manual scroll row \($0)" }
    private let rowHeight: CGFloat = 44
    private let topPadding: CGFloat = 72
    private let bottomPadding: CGFloat = 48
    private let horizontalPadding: CGFloat = 24
    private let backgroundInset: CGFloat = 16
    private let titleVerticalOffset: CGFloat = 48
    private let subtitleVerticalOffset: CGFloat = 22

    init(appConnection: OuterframeHost) {
        self.appConnection = appConnection
        super.init()
    }

    @objc func initialize(with data: Data, size: CGSize) -> CALayer? {
        currentSize = size
        scrollOffset = 0

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let viewport = CALayer()
        viewport.frame = root.bounds
        viewport.isGeometryFlipped = true
        viewport.masksToBounds = true
        root.addSublayer(viewport)

        let content = CALayer()
        viewport.addSublayer(content)

        scrollbarController = ScrollbarController<ManualScrollViewContentController>(appConnection: appConnection,
                                                                                    viewportLayer: viewport,
                                                                                    appearance: NSAppearance.currentDrawing(),
                                                                                    width: scrollbarWidth,
                                                                                    inset: scrollbarInset)
        scrollbarController?.delegate = self
        updateScrollbarLayout()

        let background = CALayer()
        background.cornerRadius = 12
        background.backgroundColor = NSColor.clear.cgColor
        background.backgroundColor = NSColor.textBackgroundColor.cgColor
        background.borderColor = NSColor.separatorColor.cgColor
        background.borderWidth = 1
        background.shadowColor = NSColor.black.withAlphaComponent(0.08).cgColor
        background.shadowOpacity = 1
        background.shadowRadius = 6
        content.insertSublayer(background, at: 0)

        let title = makeTextLayer(font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                                  fontSize: 20,
                                  color: NSColor.labelColor)
        title.string = "Manual Scroll View"
        content.addSublayer(title)

        let subtitle = makeTextLayer(font: NSFont.systemFont(ofSize: 14, weight: .regular),
                                     fontSize: 14,
                                     color: NSColor.secondaryLabelColor)
        subtitle.string = "This view scrolls entirely inside the outerframe layer tree."
        subtitle.isWrapped = true
        content.addSublayer(subtitle)

        var itemLayers: [CATextLayer] = []
        for (index, title) in items.enumerated() {
            let row = makeTextLayer(font: NSFont.systemFont(ofSize: 16, weight: .medium),
                                    fontSize: 16,
                                    color: NSColor.labelColor)
            row.string = title
            // Alternate opacity for visual rhythm
            if index % 2 == 1 {
                row.foregroundColor = NSColor.labelColor.withAlphaComponent(0.8).cgColor
            }
            itemLayers.append(row)
            content.addSublayer(row)
        }

        layers = Layers(rootLayer: root, viewportLayer: viewport, contentLayer: content, backgroundLayer: background, titleLayer: title, subtitleLayer: subtitle, itemLayers: itemLayers)

        layoutContent()

        return root
    }

    @objc func resize(width: Int, height: Int) {
        currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        guard let layers else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layers.rootLayer.frame = CGRect(origin: .zero, size: currentSize)
        layers.viewportLayer.frame = CGRect(origin: .zero, size: currentSize)

        layoutContent()

        CATransaction.commit()
    }

    @objc func updateLayer(timestamp _: CFTimeInterval) {}

    @objc func cleanup() {
        scrollbarController?.cleanup()
        scrollbarController = nil
        layers = nil
    }

    @objc func scrollWheel(delta: CGPoint,
                           at point: CGPoint,
                           modifierFlags: NSEvent.ModifierFlags,
                           phase: NSEvent.Phase,
                           momentumPhase: NSEvent.Phase,
                           isMomentum: Bool,
                           isPrecise: Bool) {
        let multiplier: CGFloat = isPrecise ? 1.0 : rowHeight
        let adjustedDeltaY = delta.y * multiplier
        guard adjustedDeltaY != 0 else { return }

        scrollbarController?.cancelAnimation()

        let maxOffset = maxScrollOffsetValue()
        let proposedOffset = max(min(scrollOffset - adjustedDeltaY, maxOffset), 0)

        if abs(proposedOffset - scrollOffset) < 0.01 {
            return
        }

        setScrollOffset(proposedOffset)
    }

    func accessibilitySnapshotData() -> Data? {
        guard let layers else {
            return OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
        }

        func text(from layer: CATextLayer?) -> String? {
            if let string = layer?.string as? String {
                return string
            }
            if let attributed = layer?.string as? NSAttributedString {
                return attributed.string
            }
            return nil
        }

        func frameInRoot(for layer: CALayer?) -> CGRect {
            guard let targetLayer = layer else { return .zero }
            return targetLayer.convert(targetLayer.frame, to: layers.rootLayer)
        }

        var nextIdentifier: UInt32 = 1
        func makeNode(role: OuterframeAccessibilityRole,
                      frame: CGRect,
                      label: String?,
                      children: [OuterframeAccessibilityNode] = []) -> OuterframeAccessibilityNode {
            let node = OuterframeAccessibilityNode(identifier: nextIdentifier,
                                               role: role,
                                               frame: frame,
                                               label: label,
                                               children: children)
            nextIdentifier += 1
            return node
        }

        var rootChildren: [OuterframeAccessibilityNode] = []

        if let titleText = text(from: layers.titleLayer) {
            rootChildren.append(makeNode(role: .staticText,
                                         frame: frameInRoot(for: layers.titleLayer),
                                         label: titleText))
        }

        if let subtitleText = text(from: layers.subtitleLayer) {
            rootChildren.append(makeNode(role: .staticText,
                                         frame: frameInRoot(for: layers.subtitleLayer),
                                         label: subtitleText))
        }

        let rowNodes: [OuterframeAccessibilityNode] = layers.itemLayers.compactMap { layer in
            guard let label = text(from: layer) else { return nil }
            return makeNode(role: .staticText,
                            frame: frameInRoot(for: layer),
                            label: label)
        }

        let container = makeNode(role: .container,
                                 frame: frameInRoot(for: layers.backgroundLayer),
                                 label: "Manual scroll rows",
                                 children: rowNodes)
        rootChildren.append(container)

        let rootNode = OuterframeAccessibilityNode(identifier: 0,
                                               role: .container,
                                               frame: layers.rootLayer.frame,
                                               label: "Manual Scroll View",
                                               children: rootChildren)
        let snapshot = OuterframeAccessibilitySnapshot(rootNodes: [rootNode])
        return snapshot.serializedData()
    }

    private func makeTextLayer(font: NSFont, fontSize: CGFloat, color: NSColor) -> CATextLayer {
        let layer = CATextLayer()
        layer.contentsScale = 2.0
        layer.alignmentMode = .left
        layer.font = font
        layer.fontSize = fontSize
        layer.foregroundColor = color.cgColor
        layer.truncationMode = .end
        return layer
    }

    private func layoutContent() {
        guard let layers else { return }

        let contentWidth = currentSize.width
        let rowWidth = max(contentWidth - horizontalPadding * 2, 120)
        let backgroundWidth = max(contentWidth - backgroundInset * 2, 120)

        layers.titleLayer.frame = CGRect(x: horizontalPadding,
                                   y: topPadding - titleVerticalOffset,
                                   width: rowWidth,
                                   height: 28)

        layers.subtitleLayer.frame = CGRect(x: horizontalPadding,
                                      y: topPadding - subtitleVerticalOffset,
                                      width: rowWidth,
                                      height: 40)

        var currentY = topPadding
        for layer in layers.itemLayers {
            layer.frame = CGRect(x: horizontalPadding,
                                 y: currentY,
                                 width: rowWidth,
                                 height: rowHeight)
            currentY += rowHeight
        }

        currentY += bottomPadding
        let contentHeight = max(currentY, currentSize.height)
        layers.contentLayer.frame = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

        layers.backgroundLayer.frame = CGRect(x: backgroundInset,
                                        y: topPadding - 16,
                                        width: backgroundWidth,
                                        height: contentHeight - topPadding + 32)

        let maxOffset = max(contentHeight - layers.viewportLayer.bounds.height, 0)
        if maxOffset <= 0 {
            scrollOffset = 0
        } else {
            scrollOffset = min(scrollOffset, maxOffset)
        }

        applyScrollOffset()
    }

    private func applyScrollOffset() {
        guard let layers else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers.contentLayer.frame.origin.y = -scrollOffset
        CATransaction.commit()
        updateScrollbarLayout()
    }

    @objc func mouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {
        guard let layers else { return }
        if scrollbarController?.handleMouseDown(at: layers.rootLayer.convert(point, to: layers.viewportLayer)) == true {
            return
        }
    }

    @objc func mouseDragged(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard let layers else { return }
        _ = scrollbarController?.handleMouseDragged(to: layers.rootLayer.convert(point, to: layers.viewportLayer))
    }

    private func setScrollOffset(_ value: CGFloat) {
        let clamped = max(0, min(value, maxScrollOffsetValue()))
        if abs(clamped - scrollOffset) < 0.0001 {
            scrollOffset = clamped
            updateScrollbarLayout()
            return
        }
        scrollOffset = clamped
        applyScrollOffset()
        appConnection.notifyAccessibilityTreeChanged(.layoutChanged)
    }

    private func maxScrollOffsetValue() -> CGFloat {
        guard let layers else { return 0 }
        return max(layers.contentLayer.bounds.height - layers.viewportLayer.bounds.height, 0)
    }

    @objc func mouseUp(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        _ = scrollbarController?.handleMouseUp(at: point)
    }

    private func updateScrollbarLayout() {
        guard let metrics = makeScrollbarMetrics() else { return }
        scrollbarController?.updateLayout(metrics: metrics)
    }

    private func makeScrollbarMetrics() -> ScrollbarController<ManualScrollViewContentController>.Metrics? {
        guard let layers else { return nil }

        return ScrollbarController.Metrics(viewportSize: layers.viewportLayer.bounds.size,
                                           contentHeight: layers.contentLayer.bounds.height,
                                           scrollOffset: scrollOffset)
    }
}

extension ManualScrollViewContentController: ScrollbarControllerDelegate {
    func scrollbarDidChangeScrollOffset(_ offset: CGFloat) {
        setScrollOffset(offset)
    }
}
