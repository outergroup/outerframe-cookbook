import Foundation
import AppKit
import QuartzCore

@MainActor
@objc final class GiantPageWithAnimations: NSObject, CookbookPageController {
    private let appConnection: OuterframeHost

    private struct Layers {
        let rootLayer: CALayer
        let viewportLayer: CALayer
        let contentLayer: CALayer
        let backgroundLayer: CALayer
        let titleLayer: CATextLayer
        let subtitleLayer: CATextLayer
    }

    private struct ItemLayers {
        let containerLayer: CALayer
        let dotLayer: CALayer
        let label: String
    }

    private var layers: Layers?
    private var scrollbarController: ScrollbarController<GiantPageWithAnimations>?
    private var currentSize: CGSize = .zero
    private var scrollOffset: CGFloat = 0
    private var animationBaseTime: CFTimeInterval = 0
    private var visibleItems: [Int: ItemLayers] = [:]
    private var rowsStartY: CGFloat = 0

    private let itemCount = 420
    private let rowHeight: CGFloat = 80
    private let topPadding: CGFloat = 96
    private let bottomPadding: CGFloat = 96
    private let horizontalPadding: CGFloat = 24
    private let backgroundInset: CGFloat = 14
    private let shapeSize = CGSize(width: 28, height: 48)
    private let travelInset: CGFloat = 20
    private let travelWidth: CGFloat = 240
    private let overscan: CGFloat = 220
    private let scrollbarWidth: CGFloat = 8
    private let scrollbarInset: CGFloat = 4

    init(appConnection: OuterframeHost) {
        self.appConnection = appConnection
        super.init()
    }

    @objc func initialize(with _: Data, size: CGSize) -> CALayer? {
        currentSize = size
        scrollOffset = 0
        animationBaseTime = CACurrentMediaTime()

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

        let background = CALayer()
        background.cornerRadius = 12
        background.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.9).cgColor
        background.borderColor = NSColor.separatorColor.cgColor
        background.borderWidth = 1
        background.shadowColor = NSColor.black.withAlphaComponent(0.1).cgColor
        background.shadowOpacity = 1
        background.shadowRadius = 7
        content.insertSublayer(background, at: 0)

        let title = makeTextLayer(font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                                  fontSize: 20,
                                  color: NSColor.labelColor)
        title.string = "Giant page with animations"
        content.addSublayer(title)

        let subtitle = makeTextLayer(font: NSFont.systemFont(ofSize: 14, weight: .regular),
                                     fontSize: 14,
                                     color: NSColor.secondaryLabelColor)
        subtitle.string = "Layers only exist while visible. Animations continue in sync even when created mid-scroll. The animation runs inside WindowServer, not this OuterContent process."
        subtitle.isWrapped = true
        content.addSublayer(subtitle)

        layers = Layers(rootLayer: root,
                        viewportLayer: viewport,
                        contentLayer: content,
                        backgroundLayer: background,
                        titleLayer: title,
                        subtitleLayer: subtitle)

        layoutContent()

        let scrollbar = ScrollbarController<GiantPageWithAnimations>(appConnection: appConnection,
                                                                     viewportLayer: viewport,
                                                                     appearance: NSAppearance.currentDrawing(),
                                                                     width: scrollbarWidth,
                                                                     inset: scrollbarInset)
        scrollbar.delegate = self
        scrollbarController = scrollbar
        updateScrollbarLayout()

        return root
    }

    @objc func resize(width: Int, height: Int) {
        currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        layoutContent()
    }

    @objc func updateLayer(timestamp _: CFTimeInterval) {}

    @objc func cleanup() {
        scrollbarController?.cleanup()
        scrollbarController = nil
        removeAllVisibleItems()
        layers = nil
    }

    @objc func scrollWheel(delta: CGPoint,
                           at _: CGPoint,
                           modifierFlags _: NSEvent.ModifierFlags,
                           phase _: NSEvent.Phase,
                           momentumPhase _: NSEvent.Phase,
                           isMomentum _: Bool,
                           isPrecise: Bool) {
        let multiplier: CGFloat = isPrecise ? 1.0 : rowHeight * 0.6
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

    @objc func mouseDown(at point: CGPoint, modifierFlags _: NSEvent.ModifierFlags, clickCount _: Int) {
        guard let layers else { return }
        if scrollbarController?.handleMouseDown(at: layers.rootLayer.convert(point, to: layers.viewportLayer)) == true {
            return
        }
    }

    @objc func mouseDragged(to point: CGPoint, modifierFlags _: NSEvent.ModifierFlags) {
        guard let layers else { return }
        _ = scrollbarController?.handleMouseDragged(to: layers.rootLayer.convert(point, to: layers.viewportLayer))
    }

    @objc func mouseUp(at point: CGPoint, modifierFlags _: NSEvent.ModifierFlags) {
        guard let layers else { return }
        _ = scrollbarController?.handleMouseUp(at: layers.rootLayer.convert(point, to: layers.viewportLayer))
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
        let rowWidth = currentRowWidth()
        let containerX = containerOriginX(forRowWidth: rowWidth, contentWidth: contentWidth)
        let titleHeight: CGFloat = 28
        let subtitleHeight: CGFloat = 72
        let spacingBelowTitle: CGFloat = 12
        let spacingBelowSubtitle: CGFloat = 24

        let titleFrame = CGRect(x: containerX,
                                y: topPadding - titleHeight,
                                width: rowWidth,
                                height: titleHeight)

        let subtitleFrame = CGRect(x: containerX,
                                   y: titleFrame.maxY + spacingBelowTitle,
                                   width: rowWidth,
                                   height: subtitleHeight)

        rowsStartY = subtitleFrame.maxY + spacingBelowSubtitle
        let contentHeight = rowsStartY + CGFloat(itemCount) * rowHeight + bottomPadding

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layers.rootLayer.frame = CGRect(origin: .zero, size: currentSize)
        layers.viewportLayer.frame = CGRect(origin: .zero, size: currentSize)
        layers.contentLayer.frame = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

        layers.titleLayer.frame = titleFrame
        layers.subtitleLayer.frame = subtitleFrame

        let backgroundTop = min(titleFrame.minY, subtitleFrame.minY) - 24
        let backgroundHeight = contentHeight - backgroundTop + 24
        layers.backgroundLayer.frame = CGRect(x: max(containerX - backgroundInset, 0),
                                              y: backgroundTop,
                                              width: max(rowWidth + backgroundInset * 2, 120),
                                              height: backgroundHeight)

        CATransaction.commit()

        let maxOffset = max(contentHeight - layers.viewportLayer.bounds.height, 0)
        scrollOffset = min(scrollOffset, maxOffset)

        relayoutVisibleItems()
        applyScrollOffset()
    }

    private func applyScrollOffset() {
        guard let layers else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers.contentLayer.frame.origin.y = -scrollOffset
        CATransaction.commit()
        updateVisibleItems()
        updateScrollbarLayout()
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
    }

    private func currentRowWidth() -> CGFloat {
        let desired = currentSize.width * 0.55
        let maxAllowed = max(currentSize.width - horizontalPadding * 2, 200)
        let minWidth: CGFloat = 220
        return max(min(desired, maxAllowed), minWidth)
    }

    private func containerOriginX(forRowWidth rowWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        max((contentWidth - rowWidth) * 0.5, backgroundInset)
    }

    private func rowOriginY(for index: Int) -> CGFloat {
        rowsStartY + CGFloat(index) * rowHeight
    }

    private func updateVisibleItems() {
        guard let layers else { return }
        let visibleRect = layers.viewportLayer.convert(layers.viewportLayer.bounds, to: layers.contentLayer)
        if visibleRect.height <= 0 {
            return
        }

        let contentHeight = layers.contentLayer.bounds.height
        let rangeStart = max(visibleRect.minY - overscan, 0)
        let rangeEnd = min(visibleRect.maxY + overscan, contentHeight)

        let firstIndex = max(Int(floor((rangeStart - topPadding) / rowHeight)), 0)
        let computedLast = Int(ceil((rangeEnd - topPadding) / rowHeight))
        let lastIndex = min(max(computedLast, 0), itemCount - 1)

        if lastIndex < firstIndex {
            removeAllVisibleItems()
            return
        }

        let required = Set(firstIndex...lastIndex)
        let existing = Set(visibleItems.keys)

        let toRemove = existing.subtracting(required)
        var newlyAdded: [(Int, ItemLayers)] = []

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for index in toRemove {
            removeItem(at: index)
        }

        let rowWidth = currentRowWidth()
        for index in required where visibleItems[index] == nil {
            let item = makeItemLayers(index: index)
            visibleItems[index] = item
            layers.contentLayer.addSublayer(item.containerLayer)
            layout(item: item, at: index, rowWidth: rowWidth)
            newlyAdded.append((index, item))
        }

        CATransaction.commit()

        for (index, item) in newlyAdded {
            startAnimations(for: item, index: index)
        }
    }

    private func removeItem(at index: Int) {
        guard let item = visibleItems[index] else { return }
        item.containerLayer.removeAllAnimations()
        item.dotLayer.removeAllAnimations()
        item.containerLayer.removeFromSuperlayer()
        visibleItems.removeValue(forKey: index)
    }

    private func removeAllVisibleItems() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in Array(visibleItems.keys) {
            removeItem(at: index)
        }
        CATransaction.commit()
    }

    private func relayoutVisibleItems() {
        guard !visibleItems.isEmpty else { return }
        let rowWidth = currentRowWidth()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, item) in visibleItems {
            layout(item: item, at: index, rowWidth: rowWidth)
        }
        CATransaction.commit()

        for (index, item) in visibleItems {
            restartAnimations(for: item, index: index)
        }
    }

    private func layout(item: ItemLayers, at index: Int, rowWidth: CGFloat) {
        let containerX = containerOriginX(forRowWidth: rowWidth, contentWidth: currentSize.width)
        let containerFrame = CGRect(x: containerX,
                                    y: rowOriginY(for: index),
                                    width: rowWidth,
                                    height: rowHeight)
        item.containerLayer.frame = containerFrame

        let rectSize = shapeSize
        let columnCenter = columnCenterX(forRowWidth: rowWidth)
        let amplitude = travelAmplitude(forRowWidth: rowWidth, centerX: columnCenter)
        let startX = columnCenter - amplitude
        let centerY = containerFrame.height * 0.5
        item.dotLayer.bounds = CGRect(origin: .zero, size: rectSize)
        item.dotLayer.position = CGPoint(x: startX, y: centerY)
        item.dotLayer.cornerRadius = min(rectSize.width, rectSize.height) * 0.35
    }

    private func makeItemLayers(index: Int) -> ItemLayers {
        let container = CALayer()
        container.isGeometryFlipped = true
        container.cornerRadius = 14
        container.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.92).cgColor
        container.borderColor = NSColor.separatorColor.cgColor
        container.borderWidth = 1
        container.shadowColor = NSColor.black.withAlphaComponent(0.08).cgColor
        container.shadowOpacity = 1
        container.shadowRadius = 6

        let dot = CALayer()
        let color = baseHue(for: index)
        dot.backgroundColor = color.cgColor
        dot.shadowColor = color.withAlphaComponent(0.85).cgColor
        dot.shadowOpacity = 1
        dot.shadowRadius = 5

        container.addSublayer(dot)

        return ItemLayers(containerLayer: container,
                          dotLayer: dot,
                          label: "Moving dot \(index + 1)")
    }

    private func restartAnimations(for item: ItemLayers, index: Int) {
        item.dotLayer.removeAllAnimations()
        startAnimations(for: item, index: index)
    }

    private func startAnimations(for item: ItemLayers, index: Int) {
        guard let layers else { return }
        let baseTime = layers.contentLayer.convertTime(animationBaseTime, from: nil)
        let rowWidth = item.containerLayer.bounds.width
        let columnCenter = columnCenterX(forRowWidth: rowWidth)
        let amplitude = travelAmplitude(forRowWidth: rowWidth, centerX: columnCenter)
        let startX = columnCenter - amplitude
        let endX = columnCenter + amplitude

        let dotTravel = CABasicAnimation(keyPath: "position.x")
        dotTravel.fromValue = startX
        dotTravel.toValue = endX
        dotTravel.autoreverses = true
        dotTravel.duration = 1.0
        dotTravel.repeatCount = .greatestFiniteMagnitude
        dotTravel.beginTime = baseTime
        dotTravel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotTravel.isRemovedOnCompletion = false
        dotTravel.fillMode = .both
        item.dotLayer.add(dotTravel, forKey: "dot-travel")
    }

    private func baseHue(for index: Int) -> NSColor {
        let hue = CGFloat((index % 48)) / 48.0
        return NSColor(calibratedHue: hue, saturation: 0.6, brightness: 0.9, alpha: 1)
    }

    private func maxScrollOffsetValue() -> CGFloat {
        guard let layers else { return 0 }
        return max(layers.contentLayer.bounds.height - layers.viewportLayer.bounds.height, 0)
    }

    private func updateScrollbarLayout() {
        guard let metrics = makeScrollbarMetrics() else { return }
        scrollbarController?.updateLayout(metrics: metrics)
    }

    private func makeScrollbarMetrics() -> ScrollbarController<GiantPageWithAnimations>.Metrics? {
        guard let layers else { return nil }

        return ScrollbarController.Metrics(viewportSize: layers.viewportLayer.bounds.size,
                                           contentHeight: layers.contentLayer.bounds.height,
                                           scrollOffset: scrollOffset)
    }

    private func columnCenterX(forRowWidth rowWidth: CGFloat) -> CGFloat {
        let minCenter = travelInset + shapeSize.width * 0.5
        let maxCenter = rowWidth - travelInset - shapeSize.width * 0.5
        let preferred = rowWidth * 0.5
        return min(max(preferred, minCenter), maxCenter)
    }

    private func travelAmplitude(forRowWidth rowWidth: CGFloat, centerX: CGFloat) -> CGFloat {
        let minCenter = travelInset + shapeSize.width * 0.5
        let maxCenter = rowWidth - travelInset - shapeSize.width * 0.5
        let allowable = max(min(centerX - minCenter, maxCenter - centerX), 0)
        let preferred = min(travelWidth * 0.5, rowWidth * 0.25)
        return min(preferred, allowable)
    }

    func accessibilitySnapshotData() -> Data? {
        guard let layers else {
            return OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
        }

        func frameInRoot(for layer: CALayer?) -> CGRect {
            guard let targetLayer = layer else { return .zero }
            let bounds = targetLayer.bounds
            return targetLayer.convert(bounds, to: layers.rootLayer)
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

        var children: [OuterframeAccessibilityNode] = []
        let titleNode = makeNode(role: .staticText,
                                 frame: frameInRoot(for: layers.titleLayer),
                                 label: (layers.titleLayer.string as? String))
        children.append(titleNode)

        let subtitleNode = makeNode(role: .staticText,
                                    frame: frameInRoot(for: layers.subtitleLayer),
                                    label: (layers.subtitleLayer.string as? String))
        children.append(subtitleNode)

        let sortedVisible = visibleItems.keys.sorted()
        var rowNodes: [OuterframeAccessibilityNode] = []
        for index in sortedVisible {
            if let item = visibleItems[index] {
                let frame = frameInRoot(for: item.containerLayer)
                rowNodes.append(makeNode(role: .staticText, frame: frame, label: item.label))
            }
        }

        let containerNode = makeNode(role: .container,
                                     frame: frameInRoot(for: layers.backgroundLayer),
                                     label: "Virtualized animation rows",
                                     children: rowNodes)
        children.append(containerNode)

        let rootNode = OuterframeAccessibilityNode(identifier: 0,
                                               role: .container,
                                               frame: layers.rootLayer.frame,
                                               label: "Virtualized animation scroll",
                                               children: children)
        let snapshot = OuterframeAccessibilitySnapshot(rootNodes: [rootNode])
        return snapshot.serializedData()
    }
}

extension GiantPageWithAnimations: ScrollbarControllerDelegate {
    func scrollbarDidChangeScrollOffset(_ offset: CGFloat) {
        setScrollOffset(offset)
    }
}
