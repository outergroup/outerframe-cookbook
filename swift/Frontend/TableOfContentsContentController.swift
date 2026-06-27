import AppKit
import QuartzCore

@MainActor
final class CookbookTableOfContentsContentController: NSObject, CookbookPageController {
    private struct Entry {
        let route: CookbookRoute
        let title: String
        let description: String
    }

    private struct EntryLayers {
        let route: CookbookRoute
        let containerLayer: CALayer
        let titleLayer: CATextLayer
        let descriptionLayer: CATextLayer
        let arrowLayer: CATextLayer
    }

    private let appearance: NSAppearance
    private let appConnection: OuterframeHost
    private let navigateToRoute: (CookbookRoute) -> Void
    private var rootLayer: CALayer?
    private var viewportLayer: CALayer?
    private var contentLayer: CALayer?
    private var titleLayer: CATextLayer?
    private var subtitleLayer: CATextLayer?
    private var entryLayers: [EntryLayers] = []
    private var scrollbarController: ScrollbarController<CookbookTableOfContentsContentController>?
    private var currentSize = CGSize(width: 800, height: 600)
    private var scrollOffset: CGFloat = 0
    private var highlightedRoute: CookbookRoute?
    private var isPressingEntry = false

    private let entries: [Entry] = [
        Entry(route: .textRegion,
              title: CookbookRoute.textRegion.pageTitle,
              description: CookbookRoute.textRegion.description),
        Entry(route: .nestedScroll,
              title: CookbookRoute.nestedScroll.pageTitle,
              description: CookbookRoute.nestedScroll.description),
        Entry(route: .timelineRange,
              title: CookbookRoute.timelineRange.pageTitle,
              description: CookbookRoute.timelineRange.description),
        Entry(route: .giantPageWithAnimations,
              title: CookbookRoute.giantPageWithAnimations.pageTitle,
              description: CookbookRoute.giantPageWithAnimations.description),
        Entry(route: .nDimensionalCubeShadow,
              title: CookbookRoute.nDimensionalCubeShadow.pageTitle,
              description: CookbookRoute.nDimensionalCubeShadow.description)
    ]

    private let rowHeight: CGFloat = 78
    private let rowGap: CGFloat = 12
    private let bottomPadding: CGFloat = 56
    private let scrollbarWidth: CGFloat = 8
    private let scrollbarInset: CGFloat = 4

    init(appearance: NSAppearance,
         appConnection: OuterframeHost,
         navigateToRoute: @escaping (CookbookRoute) -> Void) {
        self.appearance = appearance
        self.appConnection = appConnection
        self.navigateToRoute = navigateToRoute
        super.init()
    }

    func initialize(with data: Data, size: CGSize) -> CALayer? {
        currentSize = size

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = true

        let viewport = CALayer()
        viewport.frame = root.bounds
        viewport.isGeometryFlipped = true
        viewport.masksToBounds = true
        root.addSublayer(viewport)

        let content = CALayer()
        viewport.addSublayer(content)

        let title = makeTextLayer(font: .systemFont(ofSize: 30, weight: .semibold),
                                  fontSize: 30,
                                  color: .labelColor)
        title.string = "Outerframe Cookbook"
        content.addSublayer(title)

        let subtitle = makeTextLayer(font: .systemFont(ofSize: 15, weight: .regular),
                                     fontSize: 15,
                                     color: .secondaryLabelColor)
        subtitle.string = "Pick a page:"
        content.addSublayer(subtitle)

        var layers: [EntryLayers] = []
        for entry in entries {
            let container = CALayer()
            container.isGeometryFlipped = true
            container.cornerRadius = 8
            container.borderWidth = 1
            content.addSublayer(container)

            let entryTitle = makeTextLayer(font: .systemFont(ofSize: 17, weight: .semibold),
                                           fontSize: 17,
                                           color: .labelColor)
            entryTitle.string = entry.title
            container.addSublayer(entryTitle)

            let description = makeTextLayer(font: .systemFont(ofSize: 13, weight: .regular),
                                            fontSize: 13,
                                            color: .secondaryLabelColor)
            description.string = entry.description
            description.isWrapped = true
            container.addSublayer(description)

            let arrow = makeTextLayer(font: .systemFont(ofSize: 20, weight: .medium),
                                      fontSize: 20,
                                      color: .secondaryLabelColor)
            arrow.string = ">"
            arrow.alignmentMode = .right
            container.addSublayer(arrow)

            layers.append(EntryLayers(route: entry.route,
                                      containerLayer: container,
                                      titleLayer: entryTitle,
                                      descriptionLayer: description,
                                      arrowLayer: arrow))
        }

        rootLayer = root
        viewportLayer = viewport
        contentLayer = content
        titleLayer = title
        subtitleLayer = subtitle
        entryLayers = layers

        let scrollbar = ScrollbarController<CookbookTableOfContentsContentController>(appConnection: appConnection,
                                                                                     viewportLayer: viewport,
                                                                                     appearance: appearance,
                                                                                     width: scrollbarWidth,
                                                                                     inset: scrollbarInset)
        scrollbar.delegate = self
        scrollbarController = scrollbar

        updateColors()
        layout()
        return root
    }

    func handleMessage(_ message: BrowserToContentMessage, context: CookbookPageContext) {
        switch message {
        case .initializeContent(let arguments):
            context.configure(with: arguments)
            context.installPageLayer(initialize(with: context.initialData, size: context.currentSize))
            context.updateRootAppearance()

        case .resizeContent(let size):
            context.resizeRootAndPageLayer(to: size)
            resize(width: Int(size.width), height: Int(size.height))

        case .systemAppearanceUpdate(let appearance):
            context.appearance = appearance
            context.switchToRoute(context.route)

        case .historyTraversal(let entryID, let urlString):
            let route = context.routeForHistoryEntry(entryID, urlString: urlString)
            context.recordHistoryRoute(route, for: entryID)
            if route != context.route {
                context.switchToRoute(route)
            }

        case .historyEntryRejected(let entryID, _):
            context.removeHistoryRoute(for: entryID)

        case .accessibilitySnapshotRequest(let requestID):
            context.sendAccessibilitySnapshotResponse(requestID: requestID, data: accessibilitySnapshotData())

        case .selectionToPasteboardCopyRequest(let requestID):
            context.sendCopySelectedPasteboardResponse(requestID: requestID, items: pasteboardItemsForCopy())

        case .selectionToPasteboardCutRequest(let requestID):
            context.sendCopySelectedPasteboardResponse(requestID: requestID, items: [])

        case .editCommandValidationRequest(let requestID, let commands):
            context.sendEditCommandValidationResponse(requestID: requestID, enabledCommands: enabledEditCommands(for: commands))

        case .mouseMoved(let point, let modifierFlags):
            guard context.isPointInsideContent(point) else { return }
            mouseMoved(to: point, modifierFlags: modifierFlags)

        case .mouseDown(let point, let modifierFlags, let clickCount):
            guard context.isPointInsideContent(point) else { return }
            mouseDown(at: point, modifierFlags: modifierFlags, clickCount: clickCount)

        case .mouseDragged(let point, let modifierFlags):
            guard context.isPointInsideContent(point) else { return }
            mouseDragged(to: point, modifierFlags: modifierFlags)

        case .mouseUp(let point, let modifierFlags):
            guard context.isPointInsideContent(point) else { return }
            mouseUp(at: point, modifierFlags: modifierFlags)

        case .scrollWheelEvent(let point, let delta, let modifierFlags, let phase, let momentumPhase, let hasPreciseScrollingDeltas):
            guard context.isPointInsideContent(point) else { return }
            scrollWheel(delta: delta,
                        at: point,
                        modifierFlags: modifierFlags,
                        phase: phase,
                        momentumPhase: momentumPhase,
                        hasPreciseScrollingDeltas: hasPreciseScrollingDeltas)

        case .shutdown:
            context.requestShutdown()

        default:
            break
        }
    }

    func resize(width: Int, height: Int) {
        currentSize = CGSize(width: width, height: height)
        layout()
    }

    func cleanup() {
        scrollbarController?.cleanup()
        scrollbarController = nil
        rootLayer = nil
        viewportLayer = nil
        contentLayer = nil
        titleLayer = nil
        subtitleLayer = nil
        entryLayers = []
    }

    func mouseMoved(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard !isPressingEntry else { return }
        let route = route(at: point)
        if route != highlightedRoute {
            highlightedRoute = route
            updateColors(disableActions: true)
        }
    }

    func mouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {
        guard let rootLayer, let viewportLayer else { return }
        let viewportPoint = rootLayer.convert(point, to: viewportLayer)
        if scrollbarController?.handleMouseDown(at: viewportPoint) == true {
            highlightedRoute = nil
            isPressingEntry = false
            updateColors(disableActions: true)
            return
        }

        highlightedRoute = route(at: point)
        isPressingEntry = highlightedRoute != nil
        updateColors(disableActions: true)
    }

    func mouseDragged(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard let rootLayer, let viewportLayer else { return }
        let viewportPoint = rootLayer.convert(point, to: viewportLayer)
        if scrollbarController?.handleMouseDragged(to: viewportPoint) == true {
            highlightedRoute = nil
            isPressingEntry = false
            updateColors(disableActions: true)
            return
        }

        guard isPressingEntry else { return }
        let route = route(at: point)
        if route != highlightedRoute {
            highlightedRoute = route
            updateColors(disableActions: true)
        }
    }

    func mouseUp(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        if let rootLayer, let viewportLayer {
            _ = scrollbarController?.handleMouseUp(at: rootLayer.convert(point, to: viewportLayer))
        }

        defer {
            isPressingEntry = false
        }

        guard isPressingEntry else {
            highlightedRoute = route(at: point)
            updateColors(disableActions: true)
            return
        }

        guard let route = route(at: point) else {
            highlightedRoute = nil
            updateColors(disableActions: true)
            return
        }
        appConnection.setCursor(.arrow)
        navigateToRoute(route)
    }

    func scrollWheel(delta: CGPoint,
                     at point: CGPoint,
                     modifierFlags: NSEvent.ModifierFlags,
                     phase: NSEvent.Phase,
                     momentumPhase: NSEvent.Phase,
                     hasPreciseScrollingDeltas: Bool) {
        let multiplier: CGFloat = hasPreciseScrollingDeltas ? 1.0 : rowHeight
        let adjustedDeltaY = delta.y * multiplier
        guard adjustedDeltaY != 0 else { return }

        scrollbarController?.cancelAnimation()
        setScrollOffset(scrollOffset - adjustedDeltaY)
        let route = route(at: point)
        if route != highlightedRoute {
            highlightedRoute = route
            updateColors(disableActions: true)
        }
    }

    func accessibilitySnapshotData() -> Data? {
        guard let rootLayer, let contentLayer else {
            return OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
        }

        let children = entryLayers.enumerated().map { index, entry in
            OuterframeAccessibilityNode(identifier: UInt32(index + 1),
                                        role: .button,
                                        frame: contentLayer.convert(entry.containerLayer.frame, to: rootLayer),
                                        label: entry.titleLayer.string as? String,
                                        hint: entry.descriptionLayer.string as? String)
        }

        let rootNode = OuterframeAccessibilityNode(identifier: 0,
                                                   role: .container,
                                                   frame: rootLayer.frame,
                                                   label: "Outerframe Cookbook",
                                                   children: children)
        return OuterframeAccessibilitySnapshot(rootNodes: [rootNode]).serializedData()
    }

    private func makeTextLayer(font: NSFont, fontSize: CGFloat, color: NSColor) -> CATextLayer {
        let layer = CATextLayer()
        layer.contentsScale = 2.0
        layer.font = font
        layer.fontSize = fontSize
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = .left
        layer.truncationMode = .end
        return layer
    }

    private func layout() {
        guard let rootLayer, let viewportLayer, let contentLayer, let titleLayer, let subtitleLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        rootLayer.frame = CGRect(origin: .zero, size: currentSize)
        viewportLayer.frame = rootLayer.bounds

        let contentWidth = min(max(currentSize.width - 48, 280), 760)
        let contentX = max((currentSize.width - contentWidth) * 0.5, 24)
        let top: CGFloat = 56

        titleLayer.frame = CGRect(x: contentX,
                                  y: top,
                                  width: contentWidth,
                                  height: 38)
        subtitleLayer.frame = CGRect(x: contentX,
                                     y: titleLayer.frame.maxY + 8,
                                     width: contentWidth,
                                     height: 24)

        var rowY = subtitleLayer.frame.maxY + 28
        for entry in entryLayers {
            entry.containerLayer.frame = CGRect(x: contentX,
                                                y: rowY,
                                                width: contentWidth,
                                                height: rowHeight)
            entry.titleLayer.frame = CGRect(x: 18,
                                            y: 13,
                                            width: max(contentWidth - 72, 120),
                                            height: 24)
            entry.descriptionLayer.frame = CGRect(x: 18,
                                                  y: 39,
                                                  width: max(contentWidth - 72, 120),
                                                  height: 34)
            entry.arrowLayer.frame = CGRect(x: contentWidth - 46,
                                            y: 25,
                                            width: 24,
                                            height: 28)
            rowY += rowHeight + rowGap
        }

        let contentHeight = max(rowY - rowGap + bottomPadding, currentSize.height)
        contentLayer.frame = CGRect(x: 0,
                                    y: -scrollOffset,
                                    width: currentSize.width,
                                    height: contentHeight)
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffsetValue())
        contentLayer.frame.origin.y = -scrollOffset

        CATransaction.commit()
        updateScrollbarLayout()
    }

    private func updateColors(disableActions: Bool = false) {
        appearance.performAsCurrentDrawingAppearance {
            if disableActions {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
            }

            rootLayer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            titleLayer?.foregroundColor = NSColor.labelColor.cgColor
            subtitleLayer?.foregroundColor = NSColor.secondaryLabelColor.cgColor

            for entry in entryLayers {
                let isHighlighted = entry.route == highlightedRoute
                entry.containerLayer.backgroundColor = isHighlighted ?
                    NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).cgColor :
                    NSColor.textBackgroundColor.cgColor
                entry.containerLayer.borderColor = isHighlighted ?
                    NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor :
                    NSColor.separatorColor.cgColor
                entry.titleLayer.foregroundColor = NSColor.labelColor.cgColor
                entry.descriptionLayer.foregroundColor = NSColor.secondaryLabelColor.cgColor
                entry.arrowLayer.foregroundColor = isHighlighted ?
                    NSColor.controlAccentColor.cgColor :
                    NSColor.tertiaryLabelColor.cgColor
            }

            if disableActions {
                CATransaction.commit()
            }
        }
    }

    private func route(at point: CGPoint) -> CookbookRoute? {
        guard let rootLayer, let contentLayer else {
            return nil
        }
        let contentPoint = rootLayer.convert(point, to: contentLayer)
        return entryLayers.first { $0.containerLayer.frame.contains(contentPoint) }?.route
    }

    private func setScrollOffset(_ value: CGFloat) {
        let clamped = min(max(value, 0), maxScrollOffsetValue())
        if abs(clamped - scrollOffset) < 0.0001 {
            scrollOffset = clamped
            updateScrollbarLayout()
            return
        }

        scrollOffset = clamped
        applyScrollOffset()
        appConnection.notifyAccessibilityTreeChanged(.layoutChanged)
    }

    private func applyScrollOffset() {
        guard let contentLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame.origin.y = -scrollOffset
        CATransaction.commit()
        updateScrollbarLayout()
    }

    private func maxScrollOffsetValue() -> CGFloat {
        guard let viewportLayer, let contentLayer else { return 0 }
        return max(contentLayer.bounds.height - viewportLayer.bounds.height, 0)
    }

    private func updateScrollbarLayout() {
        guard let metrics = makeScrollbarMetrics() else { return }
        scrollbarController?.updateLayout(metrics: metrics)
    }

    private func makeScrollbarMetrics() -> ScrollbarController<CookbookTableOfContentsContentController>.Metrics? {
        guard let viewportLayer, let contentLayer else { return nil }
        return ScrollbarController.Metrics(viewportSize: viewportLayer.bounds.size,
                                           contentHeight: contentLayer.bounds.height,
                                           scrollOffset: scrollOffset)
    }
}

extension CookbookTableOfContentsContentController: ScrollbarControllerDelegate {
    func scrollbarDidChangeScrollOffset(_ offset: CGFloat) {
        setScrollOffset(offset)
    }
}
