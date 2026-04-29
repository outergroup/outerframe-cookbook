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
    func scrollWheel(delta: CGPoint,
                     at point: CGPoint,
                     modifierFlags: NSEvent.ModifierFlags,
                     phase: NSEvent.Phase,
                     momentumPhase: NSEvent.Phase,
                     isMomentum: Bool,
                     isPrecise: Bool)
    func accessibilitySnapshotData() -> Data?
}

extension CookbookPageController {
    func mouseMoved(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {}
    func mouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {}
    func mouseDragged(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {}
    func mouseUp(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {}
    func scrollWheel(delta: CGPoint,
                     at point: CGPoint,
                     modifierFlags: NSEvent.ModifierFlags,
                     phase: NSEvent.Phase,
                     momentumPhase: NSEvent.Phase,
                     isMomentum: Bool,
                     isPrecise: Bool) {}
    func accessibilitySnapshotData() -> Data? {
        OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
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
        case manualScroll
        case nestedScroll
        case timelineRange
        case giantPageWithAnimations

        var pageTitle: String {
            switch self {
            case .tableOfContents:
                return "Outerframe Cookbook"
            case .manualScroll:
                return "Manual Scroll View"
            case .nestedScroll:
                return "Nested Scroll Demo"
            case .timelineRange:
                return "Timeline Range Selector"
            case .giantPageWithAnimations:
                return "Giant Page With Animations"
            }
        }

        var description: String {
            switch self {
            case .tableOfContents:
                return "Choose a cookbook entry."
            case .manualScroll:
                return "A manual layer-backed scroll view with a custom scrollbar."
            case .nestedScroll:
                return "Nested scroll regions with independent hit testing."
            case .timelineRange:
                return "A draggable chart selection surface with hover feedback."
            case .giantPageWithAnimations:
                return "A virtualized page with many synchronized animations."
            }
        }

        static func make(from identifier: String?) -> Route {
            guard var slug = identifier, !slug.isEmpty else {
                return .tableOfContents
            }

            if slug.hasPrefix("!") {
                slug.removeFirst()
            }

            slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
            while slug.hasPrefix("/") {
                slug.removeFirst()
            }

            slug = slug.replacingOccurrences(of: "-", with: "_").lowercased()

            switch slug {
            case "manual_scroll", "manual":
                return .manualScroll
            case "nested_scroll", "nested":
                return .nestedScroll
            case "timeline_range", "timeline", "brush":
                return .timelineRange
            case "giant_page", "giant", "animations":
                return .giantPageWithAnimations
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
    private var currentHeaderHeight: CGFloat = 0
    private var initialData = Data()
    private var didRegisterLayer = false

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
            let metrics = Self.contentMetrics(from: arguments.contentShape)
            currentSize = metrics.size
            currentHeaderHeight = metrics.headerHeight

            let root = CALayer()
            root.frame = CGRect(origin: .zero, size: currentSize)
            root.backgroundColor = NSColor.windowBackgroundColor.cgColor
            rootLayer = root

            registerRootLayerIfNeeded()
            switchToRoute(Route.make(from: outerframeHost.pluginURL()?.fragment))
            outerframeHost.updateStartPageMetadata(title: "Outerframe Cookbook",
                                                   iconPNGData: nil,
                                                   iconWidth: 0,
                                                   iconHeight: 0)

        case .resizeContent(let width, let height):
            currentSize = CGSize(width: width, height: height)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rootLayer?.frame = CGRect(origin: .zero, size: currentSize)
            let contentSize = currentContentSize
            currentPageLayer?.frame = CGRect(origin: .zero, size: contentSize)
            currentController?.resize(width: Int(contentSize.width), height: Int(contentSize.height))
            CATransaction.commit()

        case .mouseEvent(let kind, let x, let y, let modifierFlags, let clickCount):
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
            guard Self.contentRect(size: currentSize, headerHeight: currentHeaderHeight).contains(point) else { return }
            let flags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlags))
            switch kind {
            case .mouseMoved:
                currentController?.mouseMoved(to: point, modifierFlags: flags)
            case .mouseDown:
                currentController?.mouseDown(at: point, modifierFlags: flags, clickCount: Int(clickCount))
            case .mouseDragged:
                currentController?.mouseDragged(to: point, modifierFlags: flags)
            case .mouseUp:
                currentController?.mouseUp(at: point, modifierFlags: flags)
            case .rightMouseDown, .rightMouseUp:
                break
            }

        case .scrollWheelEvent(let x, let y, let deltaX, let deltaY, let modifierFlags, let phase, let momentumPhase, let isMomentum, let isPrecise):
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
            guard Self.contentRect(size: currentSize, headerHeight: currentHeaderHeight).contains(point) else { return }
            currentController?.scrollWheel(delta: CGPoint(x: CGFloat(deltaX), y: CGFloat(deltaY)),
                                           at: point,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(modifierFlags)),
                                           phase: NSEvent.Phase(rawValue: UInt(phase)),
                                           momentumPhase: NSEvent.Phase(rawValue: UInt(momentumPhase)),
                                           isMomentum: isMomentum,
                                           isPrecise: isPrecise)

        case .systemAppearanceUpdate(let appearance):
            self.appearance = appearance
            switchToRoute(currentRoute)

        case .headerMetricsUpdate(let headerHeight):
            currentHeaderHeight = headerHeight
            layoutCurrentPage()

        case .copySelectedPasteboardRequest(let requestId):
            outerframeHost.sendCopySelectedPasteboardResponse(requestId: requestId, items: [])

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
                                                                  selectRoute: { [weak self] route in
                                                                      self?.switchToRoute(route)
                                                                  })
        case .manualScroll:
            controller = ManualScrollViewContentController(appConnection: outerframeHost)
        case .nestedScroll:
            controller = NestedScrollDemoContentController(appConnection: outerframeHost)
        case .timelineRange:
            controller = TimelineRangeSelectorContentController(appConnection: outerframeHost)
        case .giantPageWithAnimations:
            controller = GiantPageWithAnimations(appConnection: outerframeHost)
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

        outerframeHost.updatePageMetadata(title: route.pageTitle,
                                          iconPNGData: nil,
                                          iconWidth: 0,
                                          iconHeight: 0)
        outerframeHost.notifyAccessibilityTreeChanged(.layoutChanged)
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
        Self.contentRect(size: currentSize, headerHeight: currentHeaderHeight).size
    }

    private func layoutCurrentPage() {
        let contentSize = currentContentSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentPageLayer?.frame = CGRect(origin: .zero, size: contentSize)
        currentController?.resize(width: Int(contentSize.width), height: Int(contentSize.height))
        CATransaction.commit()
    }

    private static func contentMetrics(from shape: ContentShape?) -> (size: CGSize, headerHeight: CGFloat) {
        switch shape {
        case .rectangle(let width, let height):
            return (CGSize(width: width, height: height), 0)
        case .contentWithHeader(let totalWidth, let totalHeight, let headerHeight):
            return (CGSize(width: totalWidth, height: totalHeight), headerHeight)
        case nil:
            return (CGSize(width: 800, height: 600), 0)
        }
    }

    private static func contentRect(size: CGSize, headerHeight: CGFloat) -> CGRect {
        let contentHeight = max(size.height - headerHeight, 0)
        return CGRect(x: 0, y: 0, width: size.width, height: contentHeight)
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
    private let selectRoute: (OuterframeCookbookHandler.Route) -> Void
    private var rootLayer: CALayer?
    private var viewportLayer: CALayer?
    private var titleLayer: CATextLayer?
    private var subtitleLayer: CATextLayer?
    private var entryLayers: [EntryLayers] = []
    private var currentSize = CGSize(width: 800, height: 600)
    private var highlightedRoute: OuterframeCookbookHandler.Route?

    private let entries: [Entry] = [
        Entry(route: .manualScroll,
              title: OuterframeCookbookHandler.Route.manualScroll.pageTitle,
              description: OuterframeCookbookHandler.Route.manualScroll.description),
        Entry(route: .nestedScroll,
              title: OuterframeCookbookHandler.Route.nestedScroll.pageTitle,
              description: OuterframeCookbookHandler.Route.nestedScroll.description),
        Entry(route: .timelineRange,
              title: OuterframeCookbookHandler.Route.timelineRange.pageTitle,
              description: OuterframeCookbookHandler.Route.timelineRange.description),
        Entry(route: .giantPageWithAnimations,
              title: OuterframeCookbookHandler.Route.giantPageWithAnimations.pageTitle,
              description: OuterframeCookbookHandler.Route.giantPageWithAnimations.description)
    ]

    init(appearance: NSAppearance, selectRoute: @escaping (OuterframeCookbookHandler.Route) -> Void) {
        self.appearance = appearance
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

        let title = makeTextLayer(font: .systemFont(ofSize: 30, weight: .semibold),
                                  fontSize: 30,
                                  color: .labelColor)
        title.string = "Outerframe Cookbook"
        viewport.addSublayer(title)

        let subtitle = makeTextLayer(font: .systemFont(ofSize: 15, weight: .regular),
                                     fontSize: 15,
                                     color: .secondaryLabelColor)
        subtitle.string = "Pick a layer-backed outerframe example."
        viewport.addSublayer(subtitle)

        var layers: [EntryLayers] = []
        for entry in entries {
            let container = CALayer()
            container.isGeometryFlipped = true
            container.cornerRadius = 8
            container.borderWidth = 1
            viewport.addSublayer(container)

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
        titleLayer = title
        subtitleLayer = subtitle
        entryLayers = layers
        updateColors()
        layout()
        return root
    }

    func resize(width: Int, height: Int) {
        currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        layout()
    }

    func cleanup() {
        rootLayer = nil
        viewportLayer = nil
        titleLayer = nil
        subtitleLayer = nil
        entryLayers = []
    }

    func mouseMoved(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        let route = route(at: point)
        if route != highlightedRoute {
            highlightedRoute = route
            updateColors()
        }
    }

    func mouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {
        highlightedRoute = route(at: point)
        updateColors()
    }

    func mouseUp(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard let route = route(at: point) else {
            highlightedRoute = nil
            updateColors()
            return
        }
        selectRoute(route)
    }

    func accessibilitySnapshotData() -> Data? {
        guard let rootLayer, let viewportLayer else {
            return OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
        }

        let children = entryLayers.enumerated().map { index, entry in
            OuterframeAccessibilityNode(identifier: UInt32(index + 1),
                                    role: .button,
                                    frame: viewportLayer.convert(entry.containerLayer.frame, to: rootLayer),
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
        guard let rootLayer, let viewportLayer, let titleLayer, let subtitleLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        rootLayer.frame = CGRect(origin: .zero, size: currentSize)
        viewportLayer.frame = rootLayer.bounds

        let contentWidth = min(max(currentSize.width - 48, 280), 760)
        let contentX = max((currentSize.width - contentWidth) * 0.5, 24)
        let top: CGFloat = 56
        let rowHeight: CGFloat = 78
        let rowGap: CGFloat = 12

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

        CATransaction.commit()
    }

    private func updateColors() {
        appearance.performAsCurrentDrawingAppearance {
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
        }
    }

    private func route(at point: CGPoint) -> OuterframeCookbookHandler.Route? {
        guard let rootLayer, let viewportLayer else {
            return nil
        }
        let viewportPoint = rootLayer.convert(point, to: viewportLayer)
        return entryLayers.first { $0.containerLayer.frame.contains(viewportPoint) }?.route
    }
}
