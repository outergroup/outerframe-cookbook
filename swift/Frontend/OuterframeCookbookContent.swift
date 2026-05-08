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
        outerframeHost.setMessageHandler { [weak handler] host, message in
            handler?.handleInitialMessage(host, message)
        }
        outerframeHost.setDisconnectHandler { [weak handler] _ in
            handler?.requestShutdown()
        }
        return 0
    }
}

@MainActor
protocol CookbookPageController: AnyObject {
    func initialize(with data: Data, size: CGSize) -> CALayer?
    func handleMessage(_ message: BrowserToContentMessage, context: CookbookPageContext)
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

enum CookbookRoute: CaseIterable {
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

    static func make(from url: URL?) -> CookbookRoute {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let page = components.queryItems?.first(where: { $0.name == "page" })?.value else {
            return .tableOfContents
        }
        return make(fromPageIdentifier: page)
    }

    private static func make(fromPageIdentifier identifier: String?) -> CookbookRoute {
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

@MainActor
final class CookbookPageContext {
    private unowned let runtime: OuterframeCookbookHandler

    init(runtime: OuterframeCookbookHandler) {
        self.runtime = runtime
    }

    var host: OuterframeHost {
        runtime.outerframeHost
    }

    var route: CookbookRoute {
        runtime.currentRoute
    }

    var currentSize: CGSize {
        get { runtime.currentSize }
        set { runtime.currentSize = newValue }
    }

    var initialData: Data {
        runtime.initialData
    }

    var appearance: NSAppearance {
        get { runtime.appearance ?? NSAppearance.currentDrawing() }
        set { runtime.appearance = newValue }
    }

    func configure(with arguments: InitializeContentArguments) {
        runtime.outerframeHost.configure(url: arguments.url ?? "",
                                         bundleUrl: arguments.bundleUrl ?? "",
                                         proxyHost: arguments.proxy?.host,
                                         proxyPort: arguments.proxy?.port ?? 0,
                                         proxyUsername: arguments.proxy?.username,
                                         proxyPassword: arguments.proxy?.password)
        appearance = arguments.appearance ?? NSAppearance.currentDrawing()
        runtime.initialData = arguments.data ?? Data()
        currentSize = arguments.contentSize ?? CGSize(width: 800, height: 600)

        if runtime.rootLayer == nil {
            let root = CALayer()
            root.frame = CGRect(origin: .zero, size: currentSize)
            root.backgroundColor = NSColor.windowBackgroundColor.cgColor
            runtime.rootLayer = root
            runtime.registerRootLayerIfNeeded()
        }

        if let historyEntryID = arguments.historyEntryID {
            runtime.routeByHistoryEntryID[historyEntryID] = runtime.currentRoute
        }
    }

    func installPageLayer(_ pageLayer: CALayer?) {
        guard let rootLayer = runtime.rootLayer else { return }
        runtime.currentPageLayer?.removeFromSuperlayer()
        runtime.currentPageLayer = nil
        guard let pageLayer else { return }
        pageLayer.frame = CGRect(origin: .zero, size: currentSize)
        rootLayer.addSublayer(pageLayer)
        runtime.currentPageLayer = pageLayer
    }

    func resizeRootAndPageLayer(to size: CGSize) {
        currentSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        runtime.rootLayer?.frame = CGRect(origin: .zero, size: size)
        runtime.currentPageLayer?.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()
    }

    func updateRootAppearance() {
        guard let rootLayer = runtime.rootLayer else { return }
        appearance.performAsCurrentDrawingAppearance {
            rootLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    func isPointInsideContent(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: currentSize).contains(point)
    }

    func navigate(to route: CookbookRoute) {
        runtime.navigateToRoute(route)
    }

    func switchToRoute(_ route: CookbookRoute) {
        runtime.switchToRoute(route)
    }

    func route(from urlString: String) -> CookbookRoute {
        CookbookRoute.make(from: URL(string: urlString))
    }

    func recordHistoryRoute(_ route: CookbookRoute, for entryID: UUID) {
        runtime.routeByHistoryEntryID[entryID] = route
    }

    func routeForHistoryEntry(_ entryID: UUID, urlString: String) -> CookbookRoute {
        runtime.routeByHistoryEntryID[entryID] ?? route(from: urlString)
    }

    func removeHistoryRoute(for entryID: UUID) {
        runtime.routeByHistoryEntryID.removeValue(forKey: entryID)
    }

    func sendAccessibilitySnapshotResponse(requestID: UUID, data: Data?) {
        host.sendAccessibilitySnapshotResponse(
            requestID: requestID,
            snapshotData: data ?? OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
        )
    }

    func sendCopySelectedPasteboardResponse(requestID: UUID, items: [OuterContentPasteboardItem]) {
        host.sendCopySelectedPasteboardResponse(requestID: requestID, items: items)
    }

    func requestShutdown() {
        runtime.requestShutdown()
    }

    func notifyAccessibilityLayoutChanged() {
        host.notifyAccessibilityTreeChanged(.layoutChanged)
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
final class OuterframeCookbookHandler: NSObject {
    fileprivate let outerframeHost: OuterframeHost
    private let appConnection: OuterframeAppConnection
    private var retainedSelf: OuterframeCookbookHandler?

    fileprivate var appearance: NSAppearance?
    fileprivate var rootLayer: CALayer?
    fileprivate var currentPageLayer: CALayer?
    fileprivate var currentPage: CookbookPageController?
    fileprivate var currentRoute: CookbookRoute = .tableOfContents
    fileprivate var currentSize = CGSize(width: 800, height: 600)
    fileprivate var initialData = Data()
    private var didRegisterLayer = false
    fileprivate var routeByHistoryEntryID: [UUID: CookbookRoute] = [:]
    private lazy var pageContext = CookbookPageContext(runtime: self)

    init(outerframeHost: OuterframeHost, appConnection: OuterframeAppConnection) {
        self.outerframeHost = outerframeHost
        self.appConnection = appConnection
        super.init()
        retainedSelf = self
    }

    func handleInitialMessage(_ host: OuterframeHost, _ message: BrowserToContentMessage) {
        if case .initializeContent(let arguments) = message {
            pageContext.configure(with: arguments)
            let initialRoute = CookbookRoute.make(from: host.pluginURL())
            currentRoute = initialRoute
            if let historyEntryID = arguments.historyEntryID {
                routeByHistoryEntryID[historyEntryID] = initialRoute
            }
            switchToRoute(initialRoute)
            return
        }
        if case .shutdown = message {
            requestShutdown()
        }
    }

    fileprivate func switchToRoute(_ route: CookbookRoute) {
        guard let rootLayer else { return }
        let resolvedAppearance = appearance ?? NSAppearance.currentDrawing()
        let page: CookbookPageController

        switch route {
        case .tableOfContents:
            page = CookbookTableOfContentsContentController(appearance: resolvedAppearance,
                                                            appConnection: outerframeHost,
                                                            navigateToRoute: { [weak self] route in
                                                                self?.navigateToRoute(route)
                                                            })
        case .textRegion:
            page = TextRegionContentController(appConnection: outerframeHost)
        case .nestedScroll:
            page = NestedScrollDemoContentController(appConnection: outerframeHost)
        case .timelineRange:
            page = TimelineRangeSelectorContentController(appConnection: outerframeHost)
        case .giantPageWithAnimations:
            page = GiantPageWithAnimations(appConnection: outerframeHost)
        case .nDimensionalCubeShadow:
            page = NDimensionalCubeShadowContentController(appConnection: outerframeHost)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentPage?.cleanup()
        currentPageLayer?.removeFromSuperlayer()
        currentPageLayer = nil
        currentRoute = route
        currentPage = page

        if let pageLayer = page.initialize(with: initialData, size: currentSize) {
            pageLayer.frame = CGRect(origin: .zero, size: currentSize)
            rootLayer.addSublayer(pageLayer)
            currentPageLayer = pageLayer
        }

        resolvedAppearance.performAsCurrentDrawingAppearance {
            rootLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        CATransaction.commit()

        outerframeHost.setMessageHandler { [weak self, weak page] _, message in
            guard let self, let page else { return }
            page.handleMessage(message, context: self.pageContext)
        }
        outerframeHost.notifyAccessibilityTreeChanged(.layoutChanged)
    }

    fileprivate func navigateToRoute(_ route: CookbookRoute) {
        guard route != currentRoute else { return }
        let entryID = outerframeHost.pushHistoryEntry(url: url(for: route))
        routeByHistoryEntryID[entryID] = route
        switchToRoute(route)
    }

    private func url(for route: CookbookRoute) -> URL? {
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

    fileprivate func requestShutdown() {
        cleanup()
        retainedSelf = nil
    }

    private func cleanup() {
        currentPage?.cleanup()
        currentPage = nil
        currentPageLayer?.removeFromSuperlayer()
        currentPageLayer = nil
        rootLayer?.removeFromSuperlayer()
        rootLayer = nil
    }

    fileprivate func registerRootLayerIfNeeded() {
        guard !didRegisterLayer else { return }
        guard let rootLayer, let registerLayer = appConnection.registerLayer else { return }
        registerLayer(rootLayer)
        didRegisterLayer = true
    }
}
