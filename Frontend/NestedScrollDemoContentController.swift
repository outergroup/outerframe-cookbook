import Foundation
import AppKit
import QuartzCore

@MainActor
@objc final class NestedScrollDemoContentController: NSObject, CookbookPageController {
    private let appConnection: OuterframeHost

    private struct Layers {
        let rootLayer: CALayer
        let outerViewportLayer: CALayer
        let outerContentLayer: CALayer
        let headerLayer: CATextLayer
        let backgroundLayer: CALayer
        let innerViewportLayer: CALayer
        let innerContentLayer: CALayer
        let innerBorderLayer: CALayer
        let innerTitleLayer: CATextLayer
        let outerItemLayers: [CATextLayer]
        let innerItemLayers: [CATextLayer]
    }

    private struct InnerViewportLayers {
        let viewportLayer: CALayer
        let contentLayer: CALayer
        let borderLayer: CALayer
        let titleLayer: CATextLayer
        let itemLayers: [CATextLayer]
    }

    private var layers: Layers?

    private var currentSize: CGSize = .zero
    private var outerScrollOffset: CGFloat = 0
    private var innerScrollOffset: CGFloat = 0

    private let scrollbarWidth: CGFloat = 8
    private let scrollbarInset: CGFloat = 4
    private var outerScrollbarController: ScrollbarController<CookbookScrollbarDelegate>?
    private var innerScrollbarController: ScrollbarController<CookbookScrollbarDelegate>?
    private var outerScrollbarDelegate: CookbookScrollbarDelegate?
    private var innerScrollbarDelegate: CookbookScrollbarDelegate?

    private let outerItems = (1...24).map { "Outer row \($0)" }
    private let innerItems = (1...36).map { "Inner row \($0)" }

    private let outerRowHeight: CGFloat = 44
    private let innerRowHeight: CGFloat = 26
    private let outerTopPadding: CGFloat = 56
    private let outerBottomPadding: CGFloat = 40
    private let innerSpacingAbove: CGFloat = 24
    private let innerSpacingBelow: CGFloat = 24
    private let innerViewportHeight: CGFloat = 200
    private let innerInsertionIndex = 6
    private let innerHeaderHeight: CGFloat = 32

    init(appConnection: OuterframeHost) {
        self.appConnection = appConnection
        super.init()
    }

    @objc func initialize(with data: Data, size: CGSize) -> CALayer? {
        currentSize = size
        outerScrollOffset = 0
        innerScrollOffset = 0

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.cornerRadius = 0

        let outerViewport = CALayer()
        outerViewport.frame = CGRect(origin: .zero, size: currentSize)
        outerViewport.isGeometryFlipped = true
        outerViewport.masksToBounds = true
        root.addSublayer(outerViewport)

        let contentHeight = computedOuterContentHeight()
        let outerContent = CALayer()
        outerContent.isGeometryFlipped = false
        outerContent.frame = CGRect(x: 0, y: 0, width: currentSize.width, height: contentHeight)
        outerViewport.addSublayer(outerContent)

        let titleLayer = CATextLayer()
        titleLayer.contentsScale = 2.0
        titleLayer.alignmentMode = .left
        titleLayer.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLayer.fontSize = 20
        titleLayer.foregroundColor = NSColor.labelColor.cgColor
        titleLayer.string = "Nested Scroll Demo (outer surface)"
        titleLayer.frame = CGRect(x: 24,
                                  y: outerTopPadding - 36,
                                  width: max(currentSize.width - 48, 120),
                                  height: 28)
        outerContent.addSublayer(titleLayer)

        let outerBackground = CALayer()
        outerBackground.backgroundColor = NSColor.textBackgroundColor.cgColor
        outerBackground.cornerRadius = 12
        outerBackground.frame = CGRect(x: 16,
                                       y: outerTopPadding - 12,
                                       width: max(currentSize.width - 32, 120),
                                       height: contentHeight - outerTopPadding + 24)
        outerBackground.shadowColor = NSColor.black.withAlphaComponent(0.1).cgColor
        outerBackground.shadowOpacity = 1
        outerBackground.shadowRadius = 6
        outerBackground.borderColor = NSColor.separatorColor.cgColor
        outerBackground.borderWidth = 1
        outerBackground.zPosition = -1
        outerContent.insertSublayer(outerBackground, below: titleLayer)

        var outerItemLayers: [CATextLayer] = []
        var innerViewportLayers: InnerViewportLayers?

        var currentY = outerTopPadding
        for (index, title) in outerItems.enumerated() {
            if index == innerInsertionIndex {
                currentY += innerSpacingAbove
                innerViewportLayers = insertInnerViewport(atY: currentY, on: outerContent)
                currentY += innerViewportHeight + innerSpacingBelow
            }

            let layer = CATextLayer()
            layer.contentsScale = 2.0
            layer.alignmentMode = .left
            layer.font = NSFont.systemFont(ofSize: 16, weight: .medium)
            layer.fontSize = 16
            layer.string = title
            layer.foregroundColor = NSColor.labelColor.cgColor
            layer.frame = CGRect(x: 24,
                                 y: currentY,
                                 width: max(currentSize.width - 48, 120),
                                 height: outerRowHeight)
            outerContent.addSublayer(layer)
            outerItemLayers.append(layer)
            currentY += outerRowHeight
        }

        if innerViewportLayers == nil {
            currentY += innerSpacingAbove
            innerViewportLayers = insertInnerViewport(atY: currentY, on: outerContent)
            currentY += innerViewportHeight + innerSpacingBelow
        }
        guard let innerLayers = innerViewportLayers else {
            return root
        }

        currentY += outerBottomPadding
        outerContent.frame.size.height = max(currentY, currentSize.height)


        let layers = Layers(rootLayer: root,
                            outerViewportLayer: outerViewport,
                            outerContentLayer: outerContent,
                            headerLayer: titleLayer,
                            backgroundLayer: outerBackground,
                            innerViewportLayer: innerLayers.viewportLayer,
                            innerContentLayer: innerLayers.contentLayer,
                            innerBorderLayer: innerLayers.borderLayer,
                            innerTitleLayer: innerLayers.titleLayer,
                            outerItemLayers: outerItemLayers,
                            innerItemLayers: innerLayers.itemLayers)
        self.layers = layers

        applyOuterScrollOffset()
        applyInnerScrollOffset()

        let outerSC = ScrollbarController<CookbookScrollbarDelegate>(appConnection: appConnection,
                                                                     viewportLayer: layers.outerViewportLayer,
                                                                     appearance: NSAppearance.currentDrawing(),
                                                                     width: scrollbarWidth,
                                                                     inset: scrollbarInset)
        let outerDelegate = CookbookScrollbarDelegate { [weak self] newOffset in
            self?.setOuterScrollOffset(newOffset)
        }
        outerSC.delegate = outerDelegate
        if let metrics = outerScrollbarMetrics() {
            outerSC.updateLayout(metrics: metrics)
        }
        self.outerScrollbarController = outerSC
        self.outerScrollbarDelegate = outerDelegate

        let innerSC = ScrollbarController<CookbookScrollbarDelegate>(appConnection: appConnection,
                                                                     viewportLayer: layers.innerViewportLayer,
                                                                     appearance: NSAppearance.currentDrawing(),
                                                                     width: scrollbarWidth,
                                                                     inset: scrollbarInset)
        let innerDelegate = CookbookScrollbarDelegate { [weak self] newOffset in
            self?.setInnerScrollOffset(newOffset)
        }
        innerSC.delegate = innerDelegate
        if let metrics = innerScrollbarMetrics() {
            innerSC.updateLayout(metrics: metrics)
        }
        self.innerScrollbarController = innerSC
        self.innerScrollbarDelegate = innerDelegate

        return root
    }

    @objc public func resize(width: Int, height: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        guard let layers else {
            CATransaction.commit()
            return
        }
        layers.rootLayer.frame = CGRect(origin: .zero, size: currentSize)

        func newWidth(_ frame: CGRect, _ newWidth: CGFloat) -> CGRect {
            CGRect(origin: frame.origin, size: CGSize(width: newWidth, height: frame.height))
        }

        layers.outerViewportLayer.frame = newWidth(layers.outerViewportLayer.frame, currentSize.width)

        layers.outerContentLayer.frame = newWidth(layers.outerContentLayer.frame, currentSize.width)

        layers.headerLayer.frame = newWidth(layers.headerLayer.frame, max(currentSize.width - 48, 120))

        layers.backgroundLayer.frame = newWidth(layers.backgroundLayer.frame, max(currentSize.width - 32, 120))

        for layer in layers.outerItemLayers {
            layer.frame = newWidth(layer.frame, max(currentSize.width - 48, 120))
        }

        let innerWidth = max(currentSize.width - 48, 120)
        let innerHeaderWidth = max(innerWidth - 24, 60)

        layers.innerViewportLayer.frame = newWidth(layers.innerViewportLayer.frame, innerWidth)
        layers.innerTitleLayer.frame = newWidth(layers.innerTitleLayer.frame, innerHeaderWidth)
        layers.innerBorderLayer.frame = newWidth(layers.innerBorderLayer.frame, innerWidth)
        layers.innerContentLayer.frame = newWidth(layers.innerContentLayer.frame, innerWidth)

        for layer in layers.innerItemLayers {
            layer.frame = newWidth(layer.frame, innerHeaderWidth)
        }

        let maxOuter = maxOuterScrollOffset()
        outerScrollOffset = min(outerScrollOffset, maxOuter)
        applyOuterScrollOffset()

        let maxInner = maxInnerScrollOffset()
        innerScrollOffset = min(innerScrollOffset, maxInner)
        applyInnerScrollOffset()

        updateOuterScrollbarLayout()
        updateInnerScrollbarLayout()

        CATransaction.commit()
    }

    @objc public func scrollWheel(delta: CGPoint,
                                  at point: CGPoint,
                                  modifierFlags _: NSEvent.ModifierFlags,
                                  phase _: NSEvent.Phase,
                                  momentumPhase _: NSEvent.Phase,
                                  isMomentum _: Bool,
                                  isPrecise: Bool) {
        guard let layers else { return }
        let root = layers.rootLayer

        var handledInner = false
        if maxInnerScrollOffset() > 0 {
            let innerViewport = layers.innerViewportLayer
            let pointInInner = innerViewport.convert(point, from: root)
            if innerViewport.bounds.contains(pointInInner) {
                let multiplier: CGFloat = isPrecise ? 1.0 : innerRowHeight
                let adjustedDeltaY = delta.y * multiplier
                if adjustedDeltaY != 0 {
                    innerScrollbarController?.cancelAnimation()
                    handledInner = scrollInner(byAdjustedDeltaY: adjustedDeltaY)
                }
            }
        }

        if handledInner {
            return
        }

        let multiplier: CGFloat = isPrecise ? 1.0 : outerRowHeight
        let adjustedDeltaY = delta.y * multiplier
        guard adjustedDeltaY != 0 else { return }
        outerScrollbarController?.cancelAnimation()
        _ = scrollOuter(byAdjustedDeltaY: adjustedDeltaY)
    }

    @objc public func mouseDown(at point: CGPoint, modifierFlags _: NSEvent.ModifierFlags, clickCount _: Int) {
        guard let layers else { return }
        let root = layers.rootLayer
        if innerScrollbarController?.handleMouseDown(at: root.convert(point, to: layers.innerViewportLayer)) == true {
            return
        }
        _ = outerScrollbarController?.handleMouseDown(at: root.convert(point, to: layers.outerViewportLayer))
    }

    @objc public func mouseDragged(to point: CGPoint, modifierFlags _: NSEvent.ModifierFlags) {
        guard let layers else { return }
        let root = layers.rootLayer
        _ = innerScrollbarController?.handleMouseDragged(to: root.convert(point, to: layers.innerViewportLayer))
        _ = outerScrollbarController?.handleMouseDragged(to: root.convert(point, to: layers.outerViewportLayer))
    }

    @objc public func mouseUp(at point: CGPoint, modifierFlags _: NSEvent.ModifierFlags) {
        guard let layers else { return }
        let root = layers.rootLayer
        _ = innerScrollbarController?.handleMouseUp(at: root.convert(point, to: layers.innerViewportLayer))
        _ = outerScrollbarController?.handleMouseUp(at: root.convert(point, to: layers.outerViewportLayer))
    }

    @objc public func updateLayer(timestamp: CFTimeInterval) {}

    @objc public func cleanup() {
        outerScrollbarController?.cleanup()
        innerScrollbarController?.cleanup()
        outerScrollbarController = nil
        innerScrollbarController = nil
        outerScrollbarDelegate = nil
        innerScrollbarDelegate = nil
        layers = nil
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
            let bounds = targetLayer.bounds
            return targetLayer.convert(bounds, to: layers.rootLayer)
        }

        var nextIdentifier: UInt32 = 1
        func makeNode(role: OuterframeAccessibilityRole,
                      frame: CGRect,
                      label: String? = nil,
                      value: String? = nil,
                      hint: String? = nil,
                      children: [OuterframeAccessibilityNode] = []) -> OuterframeAccessibilityNode {
            let node = OuterframeAccessibilityNode(identifier: nextIdentifier,
                                               role: role,
                                               frame: frame,
                                               label: label,
                                               value: value,
                                               hint: hint,
                                               children: children)
            nextIdentifier += 1
            return node
        }

        var rootChildren: [OuterframeAccessibilityNode] = []

        let headerNode = makeNode(role: .staticText,
                                  frame: frameInRoot(for: layers.headerLayer),
                                  label: text(from: layers.headerLayer))
        rootChildren.append(headerNode)

        let outerBackground = layers.backgroundLayer
        var outerChildren: [OuterframeAccessibilityNode] = []

        let sortedOuterLayers = layers.outerItemLayers.enumerated()
        let insertionIndex = innerInsertionIndex
        for (index, layer) in sortedOuterLayers {
            if index == insertionIndex {
                let innerViewportLayer = layers.innerViewportLayer
                var innerChildren: [OuterframeAccessibilityNode] = []

                let innerTitleLayer = layers.innerTitleLayer
                let innerHeaderNode = makeNode(role: .staticText,
                                               frame: frameInRoot(for: innerTitleLayer),
                                               label: text(from: innerTitleLayer))
                innerChildren.append(innerHeaderNode)

                for layer in layers.innerItemLayers {
                    let label = text(from: layer)
                    let frame = frameInRoot(for: layer)
                    innerChildren.append(makeNode(role: .staticText,
                                                  frame: frame,
                                                  label: label))
                }

                let innerContainerNode = makeNode(role: .container,
                                                  frame: frameInRoot(for: innerViewportLayer),
                                                  label: "Inner rows",
                                                  children: innerChildren)
                outerChildren.append(innerContainerNode)
            }

            let label = text(from: layer)
            let frame = frameInRoot(for: layer)
            outerChildren.append(makeNode(role: .staticText,
                                          frame: frame,
                                          label: label))
        }

        if innerInsertionIndex >= layers.outerItemLayers.count {
            var innerChildren: [OuterframeAccessibilityNode] = []
            let innerTitleLayer = layers.innerTitleLayer
            innerChildren.append(makeNode(role: .staticText,
                                          frame: frameInRoot(for: innerTitleLayer),
                                          label: text(from: innerTitleLayer)))
            for layer in layers.innerItemLayers {
                innerChildren.append(makeNode(role: .staticText,
                                              frame: frameInRoot(for: layer),
                                              label: text(from: layer)))
            }
            let innerContainerNode = makeNode(role: .container,
                                              frame: frameInRoot(for: layers.innerViewportLayer),
                                              label: "Inner rows",
                                              children: innerChildren)
            outerChildren.append(innerContainerNode)
        }

        let outerContainerNode = makeNode(role: .container,
                                          frame: frameInRoot(for: outerBackground),
                                          label: "Outer rows",
                                          children: outerChildren)
        rootChildren.append(outerContainerNode)

        let rootNode = OuterframeAccessibilityNode(identifier: 0,
                                               role: .container,
                                               frame: layers.rootLayer.bounds,
                                               label: "Nested Scroll Demo",
                                               children: rootChildren)
        let snapshot = OuterframeAccessibilitySnapshot(rootNodes: [rootNode])
        return snapshot.serializedData()
    }

    private func insertInnerViewport(atY y: CGFloat, on parent: CALayer) -> InnerViewportLayers {
        let width = max(currentSize.width - 48, 120)
        let frame = CGRect(x: 24, y: y, width: width, height: innerViewportHeight)

        let viewport = CALayer()
        viewport.frame = frame
        viewport.isGeometryFlipped = false
        viewport.masksToBounds = true
        viewport.cornerRadius = 10
        viewport.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
        parent.addSublayer(viewport)

        let border = CALayer()
        border.frame = viewport.bounds
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        border.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        border.borderWidth = 2
        border.cornerRadius = 10
        border.backgroundColor = CGColor.clear
        border.zPosition = 5
        viewport.addSublayer(border)

        let innerHeader = CATextLayer()
        innerHeader.contentsScale = 2.0
        innerHeader.alignmentMode = .left
        innerHeader.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        innerHeader.fontSize = 14
        innerHeader.foregroundColor = NSColor.systemBlue.cgColor
        innerHeader.string = "Nested inner surface"
        innerHeader.frame = CGRect(x: 12,
                                   y: 12,
                                   width: max(frame.width - 24, 60),
                                   height: 20)
        viewport.addSublayer(innerHeader)

        let contentHeight = computedInnerContentHeight()
        let content = CALayer()
        content.isGeometryFlipped = false
        content.frame = CGRect(x: 0,
                               y: innerHeaderHeight,
                               width: frame.width,
                               height: contentHeight)
        viewport.addSublayer(content)

        var itemLayers: [CATextLayer] = []

        for (index, title) in innerItems.enumerated() {
            let layer = CATextLayer()
            layer.contentsScale = 2.0
            layer.alignmentMode = .left
            layer.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            layer.fontSize = 13
            layer.string = title
            layer.foregroundColor = NSColor.labelColor.withAlphaComponent(0.8).cgColor
            layer.frame = CGRect(x: 12,
                                 y: CGFloat(index) * innerRowHeight,
                                 width: max(frame.width - 24, 60),
                                 height: innerRowHeight)
            content.addSublayer(layer)
            itemLayers.append(layer)
        }

        return InnerViewportLayers(viewportLayer: viewport,
                                   contentLayer: content,
                                   borderLayer: border,
                                   titleLayer: innerHeader,
                                   itemLayers: itemLayers)
    }

    private func outerScrollbarMetrics() -> ScrollbarController<CookbookScrollbarDelegate>.Metrics? {
        guard let layers else { return nil }
        let viewport = layers.outerViewportLayer
        let content = layers.outerContentLayer

        return ScrollbarController.Metrics(viewportSize: viewport.bounds.size,
                                           contentHeight: content.bounds.height,
                                           scrollOffset: outerScrollOffset)
    }

    private func innerScrollbarMetrics() -> ScrollbarController<CookbookScrollbarDelegate>.Metrics? {
        guard let layers else { return nil }
        let viewport = layers.innerViewportLayer
        let content = layers.innerContentLayer

        return ScrollbarController.Metrics(viewportSize: viewport.bounds.size,
                                           contentHeight: content.bounds.height,
                                           scrollOffset: innerScrollOffset)
    }

    private func updateOuterScrollbarLayout() {
        guard let metrics = outerScrollbarMetrics() else { return }
        outerScrollbarController?.updateLayout(metrics: metrics)
    }

    private func updateInnerScrollbarLayout() {
        guard let metrics = innerScrollbarMetrics() else { return }
        innerScrollbarController?.updateLayout(metrics: metrics)
    }

    private func setOuterScrollOffset(_ value: CGFloat) {
        let clamped = max(0, min(value, maxOuterScrollOffset()))
        if abs(clamped - outerScrollOffset) < 0.0001 {
            outerScrollOffset = clamped
            updateOuterScrollbarLayout()
            return
        }
        outerScrollOffset = clamped
        applyOuterScrollOffset()
        appConnection.notifyAccessibilityTreeChanged(.layoutChanged)
    }

    private func applyOuterScrollOffset() {
        guard let layers else { return }
        let outerContent = layers.outerContentLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var frame = outerContent.frame
        frame.origin.y = -outerScrollOffset
        outerContent.frame = frame
        CATransaction.commit()
        updateOuterScrollbarLayout()
    }

    private func maxOuterScrollOffset() -> CGFloat {
        guard let layers else { return 0 }
        let viewport = layers.outerViewportLayer
        let content = layers.outerContentLayer
        return max(content.bounds.height - viewport.bounds.height, 0)
    }

    private func scrollOuter(byAdjustedDeltaY deltaY: CGFloat) -> Bool {
        let maxOffset = maxOuterScrollOffset()
        if maxOffset <= 0.0001 { return false }
        let proposed = max(min(outerScrollOffset - deltaY, maxOffset), 0)
        if abs(proposed - outerScrollOffset) < 0.0001 { return false }
        setOuterScrollOffset(proposed)
        return true
    }

    private func setInnerScrollOffset(_ value: CGFloat) {
        let clamped = max(0, min(value, maxInnerScrollOffset()))
        if abs(clamped - innerScrollOffset) < 0.0001 {
            innerScrollOffset = clamped
            updateInnerScrollbarLayout()
            return
        }
        innerScrollOffset = clamped
        applyInnerScrollOffset()
        appConnection.notifyAccessibilityTreeChanged(.layoutChanged)
    }

    private func applyInnerScrollOffset() {
        guard let layers else { return }
        let innerContent = layers.innerContentLayer
        let originY = innerHeaderHeight - innerScrollOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var frame = innerContent.frame
        frame.origin.y = originY
        innerContent.frame = frame
        CATransaction.commit()
        updateInnerScrollbarLayout()
    }

    private func maxInnerScrollOffset() -> CGFloat {
        guard let layers else { return 0 }
        let viewport = layers.innerViewportLayer
        let content = layers.innerContentLayer
        let visibleHeight = max(viewport.bounds.height - innerHeaderHeight, 0)
        return max(content.bounds.height - visibleHeight, 0)
    }

    private func scrollInner(byAdjustedDeltaY deltaY: CGFloat) -> Bool {
        let maxOffset = maxInnerScrollOffset()
        if maxOffset <= 0.0001 { return false }
        let proposed = max(min(innerScrollOffset - deltaY, maxOffset), 0)
        if abs(proposed - innerScrollOffset) < 0.0001 { return false }
        setInnerScrollOffset(proposed)
        return true
    }

    private func computedOuterContentHeight() -> CGFloat {
        let rowsHeight = CGFloat(outerItems.count) * outerRowHeight
        let innerSection = innerSpacingAbove + innerViewportHeight + innerSpacingBelow
        return outerTopPadding + rowsHeight + innerSection + outerBottomPadding
    }

    private func computedInnerContentHeight() -> CGFloat {
        CGFloat(innerItems.count) * innerRowHeight + 12
    }
}
