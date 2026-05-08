import AppKit
import QuartzCore

@MainActor
@objc public final class OuterframeCookbookContent: NSObject, OuterframeContentLibrary {
    @objc public static func start(
        socketFD: Int32,
        appConnection: OuterframeAppConnection
    ) -> Int32 {
        let outerframeHost = OuterframeHost(socketFD: socketFD)
        let handler = OuterframeCookbookHandler(outerframeHost: outerframeHost, appConnection: appConnection)
        outerframeHost.delegate = handler
        return 0
    }
}

@MainActor
protocol CookbookPageController: AnyObject {
    func initialize(with data: Data, size: CGSize) -> CALayer?
    func resize(width: Int, height: Int)
    func cleanup()
    func mouseMoved(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags)
    func mouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int)
    func mouseDragged(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags)
    func mouseUp(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags)
    func rightMouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int)
    func scrollWheel(delta: CGPoint,
                     at point: CGPoint,
                     modifierFlags: NSEvent.ModifierFlags,
                     phase: NSEvent.Phase,
                     momentumPhase: NSEvent.Phase,
                     hasPreciseScrollingDeltas: Bool)
    func accessibilitySnapshotData() -> Data?
    func pasteboardItemsForCopy() -> [OuterContentPasteboardItem]
}

extension CookbookPageController {
    func mouseMoved(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {}
    func mouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {}
    func mouseDragged(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {}
    func mouseUp(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {}
    func rightMouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {}
    func scrollWheel(delta: CGPoint,
                     at point: CGPoint,
                     modifierFlags: NSEvent.ModifierFlags,
                     phase: NSEvent.Phase,
                     momentumPhase: NSEvent.Phase,
                     hasPreciseScrollingDeltas: Bool) {}
    func accessibilitySnapshotData() -> Data? {
        OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
    }
    func pasteboardItemsForCopy() -> [OuterContentPasteboardItem] {
        []
    }
}

extension OuterframeHost {
    func notifyAccessibilityTreeChanged(_ notification: OuterframeAccessibilityNotification) {
        Task {
            try? await socket.send(
                ContentToBrowserMessage.accessibilityTreeChanged(notificationMask: notification.rawValue).encode()
            )
        }
    }
}

@MainActor
final class CookbookScrollbarDelegate: ScrollbarControllerDelegate {
    private let didChangeScrollOffset: (CGFloat) -> Void

    init(didChangeScrollOffset: @escaping (CGFloat) -> Void) {
        self.didChangeScrollOffset = didChangeScrollOffset
    }

    func scrollbarDidChangeScrollOffset(_ offset: CGFloat) {
        didChangeScrollOffset(offset)
    }
}

@MainActor
fileprivate final class OuterframeCookbookHandler: NSObject, OuterframeHostDelegate {
    fileprivate enum Route: CaseIterable {
        case tableOfContents
        case textRegion
        case nestedScroll
        case timelineRange
        case giantPageWithAnimations
        case nDimensionalCubeShadow

        var pageTitle: String {
            switch self {
            case .tableOfContents:
                return "Outerframe Cookbook"
            case .textRegion:
                return "Text Region"
            case .nestedScroll:
                return "Nested Scroll Demo"
            case .timelineRange:
                return "Timeline Range Selector"
            case .giantPageWithAnimations:
                return "Giant Page With Animations"
            case .nDimensionalCubeShadow:
                return "N-Dimensional Cube Shadow"
            }
        }

        var description: String {
            switch self {
            case .tableOfContents:
                return "Choose a page."
            case .textRegion:
                return "A TextKit 2 scrollable text region with selection, copy, and accessibility."
            case .nestedScroll:
                return "Nested scroll regions with independent hit testing."
            case .timelineRange:
                return "A draggable chart selection surface with hover feedback."
            case .giantPageWithAnimations:
                return "A virtualized page with many synchronized animations."
            case .nDimensionalCubeShadow:
                return "Translucent face projections from a rotating N-dimensional cube."
            }
        }

        var pageIdentifier: String? {
            switch self {
            case .tableOfContents:
                return nil
            case .textRegion:
                return "text_region"
            case .nestedScroll:
                return "nested_scroll"
            case .timelineRange:
                return "timeline_range"
            case .giantPageWithAnimations:
                return "giant_page"
            case .nDimensionalCubeShadow:
                return "n_cube"
            }
        }

        static func make(from url: URL?) -> Route {
            guard let url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let page = components.queryItems?.first(where: { $0.name == "page" })?.value else {
                return .tableOfContents
            }
            return make(fromPageIdentifier: page)
        }

        private static func make(fromPageIdentifier identifier: String?) -> Route {
            guard var slug = identifier, !slug.isEmpty else {
                return .tableOfContents
            }

            slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
            while slug.hasPrefix("/") {
                slug.removeFirst()
            }

            slug = slug.replacingOccurrences(of: "-", with: "_").lowercased()

            switch slug {
            case "text_region", "text", "textkit", "textkit2", "copyable_text":
                return .textRegion
            case "nested_scroll", "nested":
                return .nestedScroll
            case "timeline_range", "timeline", "brush":
                return .timelineRange
            case "giant_page", "giant", "animations":
                return .giantPageWithAnimations
            case "n_cube", "ncube", "cube_shadow", "hypercube":
                return .nDimensionalCubeShadow
            default:
                return .tableOfContents
            }
        }
    }

    private let outerframeHost: OuterframeHost
    private let appConnection: OuterframeAppConnection
    private var retainedSelf: OuterframeCookbookHandler?

    private var appearance: NSAppearance?
    private var rootLayer: CALayer?
    private var currentPageLayer: CALayer?
    private var currentController: CookbookPageController?
    private var currentRoute: Route = .tableOfContents
    private var currentSize = CGSize(width: 800, height: 600)
    private var initialData = Data()
    private var didRegisterLayer = false
    private var routeByHistoryEntryID: [UUID: Route] = [:]

    init(outerframeHost: OuterframeHost, appConnection: OuterframeAppConnection) {
        self.outerframeHost = outerframeHost
        self.appConnection = appConnection
        super.init()
        retainedSelf = self
    }

    func outerframeHost(_ host: OuterframeHost, didReceiveMessage message: BrowserToContentMessage) {
        switch message {
        case .initializeContent(let arguments):
            outerframeHost.configure(url: arguments.url ?? "",
                                     bundleUrl: arguments.bundleUrl ?? "",
                                     proxyHost: arguments.proxy?.host,
                                     proxyPort: arguments.proxy?.port ?? 0,
                                     proxyUsername: arguments.proxy?.username,
                                     proxyPassword: arguments.proxy?.password)
            appearance = arguments.appearance ?? NSAppearance.currentDrawing()
            initialData = arguments.data ?? Data()
            currentSize = arguments.contentSize ?? CGSize(width: 800, height: 600)

            let root = CALayer()
            root.frame = CGRect(origin: .zero, size: currentSize)
            root.backgroundColor = NSColor.windowBackgroundColor.cgColor
            rootLayer = root

            registerRootLayerIfNeeded()
            let initialRoute = Route.make(from: outerframeHost.pluginURL())
            if let historyEntryID = arguments.historyEntryID {
                routeByHistoryEntryID[historyEntryID] = initialRoute
            }
            switchToRoute(initialRoute)

        case .historyTraversal(let entryID, let urlString):
            let route = routeByHistoryEntryID[entryID]
                ?? Route.make(from: URL(string: urlString))
            routeByHistoryEntryID[entryID] = route
            switchToRoute(route)

        case .historyEntryRejected(let entryID, _):
            routeByHistoryEntryID.removeValue(forKey: entryID)

        case .resizeContent(let size):
            currentSize = size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rootLayer?.frame = CGRect(origin: .zero, size: currentSize)
            let contentSize = currentContentSize
            currentPageLayer?.frame = CGRect(origin: .zero, size: contentSize)
            currentController?.resize(width: Int(contentSize.width), height: Int(contentSize.height))
            CATransaction.commit()

        case .mouseMoved(let point, let modifierFlags):
            guard CGRect(origin: .zero, size: currentSize).contains(point) else { return }
            currentController?.mouseMoved(to: point, modifierFlags: modifierFlags)

        case .mouseDown(let point, let modifierFlags, let clickCount):
            guard CGRect(origin: .zero, size: currentSize).contains(point) else { return }
            currentController?.mouseDown(at: point, modifierFlags: modifierFlags, clickCount: clickCount)

        case .mouseDragged(let point, let modifierFlags):
            guard CGRect(origin: .zero, size: currentSize).contains(point) else { return }
            currentController?.mouseDragged(to: point, modifierFlags: modifierFlags)

        case .mouseUp(let point, let modifierFlags):
            guard CGRect(origin: .zero, size: currentSize).contains(point) else { return }
            currentController?.mouseUp(at: point, modifierFlags: modifierFlags)

        case .rightMouseDown(let point, let modifierFlags, let clickCount):
            guard CGRect(origin: .zero, size: currentSize).contains(point) else { return }
            currentController?.rightMouseDown(at: point, modifierFlags: modifierFlags, clickCount: clickCount)

        case .rightMouseUp:
            break

        case .scrollWheelEvent(let point, let delta, let modifierFlags, let phase, let momentumPhase, let hasPreciseScrollingDeltas):
            guard CGRect(origin: .zero, size: currentSize).contains(point) else { return }
            currentController?.scrollWheel(delta: delta,
                                           at: point,
                                           modifierFlags: modifierFlags,
                                           phase: phase,
                                           momentumPhase: momentumPhase,
                                           hasPreciseScrollingDeltas: hasPreciseScrollingDeltas)

        case .systemAppearanceUpdate(let appearance):
            self.appearance = appearance
            switchToRoute(currentRoute)

        case .copySelectedPasteboardRequest(let requestID):
            outerframeHost.sendCopySelectedPasteboardResponse(requestID: requestID,
                                                              items: currentController?.pasteboardItemsForCopy() ?? [])

        case .shutdown:
            cleanup()
            retainedSelf = nil

        default:
            break
        }
    }

    func outerframeHostDidDisconnect(_ host: OuterframeHost) {
        cleanup()
        retainedSelf = nil
    }

    func outerframeHostAccessibilitySnapshot(_ host: OuterframeHost) -> OuterframeAccessibilitySnapshot? {
        guard let data = currentController?.accessibilitySnapshotData() else {
            return nil
        }
        return OuterframeAccessibilitySnapshot.deserialize(from: data)
    }

    fileprivate func switchToRoute(_ route: Route) {
        guard let rootLayer else { return }
        let resolvedAppearance = appearance ?? NSAppearance.currentDrawing()
        let controller: CookbookPageController
        let contentSize = currentContentSize

        switch route {
        case .tableOfContents:
            controller = CookbookTableOfContentsContentController(appearance: resolvedAppearance,
                                                                  appConnection: outerframeHost,
                                                                  selectRoute: { [weak self] route in
                                                                      self?.navigateToRoute(route)
                                                                  })
        case .textRegion:
            controller = TextRegionContentController(appConnection: outerframeHost)
        case .nestedScroll:
            controller = NestedScrollDemoContentController(appConnection: outerframeHost)
        case .timelineRange:
            controller = TimelineRangeSelectorContentController(appConnection: outerframeHost)
        case .giantPageWithAnimations:
            controller = GiantPageWithAnimations(appConnection: outerframeHost)
        case .nDimensionalCubeShadow:
            controller = NDimensionalCubeShadowContentController(appConnection: outerframeHost)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentController?.cleanup()
        currentPageLayer?.removeFromSuperlayer()
        currentRoute = route
        currentController = controller

        if let pageLayer = controller.initialize(with: initialData, size: contentSize) {
            pageLayer.frame = CGRect(origin: .zero, size: contentSize)
            rootLayer.addSublayer(pageLayer)
            currentPageLayer = pageLayer
        } else {
            currentPageLayer = nil
        }

        resolvedAppearance.performAsCurrentDrawingAppearance {
            rootLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        CATransaction.commit()

        outerframeHost.notifyAccessibilityTreeChanged(.layoutChanged)
    }

    private func navigateToRoute(_ route: Route) {
        guard route != currentRoute else { return }
        let entryID = outerframeHost.pushHistoryEntry(url: url(for: route))
        routeByHistoryEntryID[entryID] = route
        switchToRoute(route)
    }

    private func url(for route: Route) -> URL? {
        guard let baseURL = outerframeHost.pluginURL(),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = components.queryItems?.filter { $0.name != "page" } ?? []
        if let pageIdentifier = route.pageIdentifier {
            queryItems.append(URLQueryItem(name: "page", value: pageIdentifier))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.fragment = nil
        return components.url
    }

    private func cleanup() {
        currentController?.cleanup()
        currentController = nil
        currentPageLayer?.removeFromSuperlayer()
        currentPageLayer = nil
        rootLayer?.removeFromSuperlayer()
        rootLayer = nil
    }

    private func registerRootLayerIfNeeded() {
        guard !didRegisterLayer else { return }
        guard let rootLayer, let registerLayer = appConnection.registerLayer else { return }
        registerLayer(rootLayer)
        didRegisterLayer = true
    }

    private var currentContentSize: CGSize {
        currentSize
    }

    private func layoutCurrentPage() {
        let contentSize = currentContentSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentPageLayer?.frame = CGRect(origin: .zero, size: contentSize)
        currentController?.resize(width: Int(contentSize.width), height: Int(contentSize.height))
        CATransaction.commit()
    }

}

@MainActor
private final class CookbookTableOfContentsContentController: NSObject, CookbookPageController {
    private struct Entry {
        let route: OuterframeCookbookHandler.Route
        let title: String
        let description: String
    }

    private struct EntryLayers {
        let route: OuterframeCookbookHandler.Route
        let containerLayer: CALayer
        let titleLayer: CATextLayer
        let descriptionLayer: CATextLayer
        let arrowLayer: CATextLayer
    }

    private let appearance: NSAppearance
    private let appConnection: OuterframeHost
    private let selectRoute: (OuterframeCookbookHandler.Route) -> Void
    private var rootLayer: CALayer?
    private var viewportLayer: CALayer?
    private var contentLayer: CALayer?
    private var titleLayer: CATextLayer?
    private var subtitleLayer: CATextLayer?
    private var entryLayers: [EntryLayers] = []
    private var scrollbarController: ScrollbarController<CookbookTableOfContentsContentController>?
    private var currentSize = CGSize(width: 800, height: 600)
    private var scrollOffset: CGFloat = 0
    private var highlightedRoute: OuterframeCookbookHandler.Route?
    private var isPressingEntry = false

    private let entries: [Entry] = [
        Entry(route: .textRegion,
              title: OuterframeCookbookHandler.Route.textRegion.pageTitle,
              description: OuterframeCookbookHandler.Route.textRegion.description),
        Entry(route: .nestedScroll,
              title: OuterframeCookbookHandler.Route.nestedScroll.pageTitle,
              description: OuterframeCookbookHandler.Route.nestedScroll.description),
        Entry(route: .timelineRange,
              title: OuterframeCookbookHandler.Route.timelineRange.pageTitle,
              description: OuterframeCookbookHandler.Route.timelineRange.description),
        Entry(route: .giantPageWithAnimations,
              title: OuterframeCookbookHandler.Route.giantPageWithAnimations.pageTitle,
              description: OuterframeCookbookHandler.Route.giantPageWithAnimations.description),
        Entry(route: .nDimensionalCubeShadow,
              title: OuterframeCookbookHandler.Route.nDimensionalCubeShadow.pageTitle,
              description: OuterframeCookbookHandler.Route.nDimensionalCubeShadow.description)
    ]

    private let rowHeight: CGFloat = 78
    private let rowGap: CGFloat = 12
    private let bottomPadding: CGFloat = 56
    private let scrollbarWidth: CGFloat = 8
    private let scrollbarInset: CGFloat = 4

    init(appearance: NSAppearance,
         appConnection: OuterframeHost,
         selectRoute: @escaping (OuterframeCookbookHandler.Route) -> Void) {
        self.appearance = appearance
        self.appConnection = appConnection
        self.selectRoute = selectRoute
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
        selectRoute(route)
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

    private func route(at point: CGPoint) -> OuterframeCookbookHandler.Route? {
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
