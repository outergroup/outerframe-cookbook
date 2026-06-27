import Foundation
import AppKit
import QuartzCore

private final class TextKitDisplayLayer: CALayer {
    var textLayoutManager: NSTextLayoutManager?
    var scrollOffset: CGFloat = 0
    var textInset: CGPoint = .zero
    var visibleBounds: CGRect = .zero

    override init() {
        super.init()
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(in context: CGContext) {
        guard let textLayoutManager else { return }

        context.saveGState()
        context.translateBy(x: textInset.x, y: textInset.y - scrollOffset)

        let visibleTextRect = visibleBounds.offsetBy(dx: -textInset.x,
                                                     dy: scrollOffset - textInset.y)
        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location,
                                                        options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > visibleTextRect.maxY {
                return false
            }
            if frame.maxY >= visibleTextRect.minY {
                fragment.draw(at: frame.origin, in: context)
            }
            return true
        }

        context.restoreGState()
    }
}

@MainActor
@objc final class TextRegionContentController: NSObject, CookbookPageController {
    private let appConnection: OuterframeHost

    private struct Layers {
        let rootLayer: CALayer
        let viewportLayer: CALayer
        let backgroundLayer: CALayer
        let titleLayer: CATextLayer
        let subtitleLayer: CATextLayer
        let selectionLayer: CALayer
        let textLayer: TextKitDisplayLayer
    }

    private let contentStorage = NSTextContentStorage()
    private let textLayoutManager = NSTextLayoutManager()
    private let textContainer = NSTextContainer(size: CGSize(width: 640, height: 1_000_000))

    private var layers: Layers?
    private var currentSize: CGSize = .zero
    private var scrollOffset: CGFloat = 0
    private var dragAnchorSelections: [NSTextSelection] = []
    private var selectionRange: NSRange?
    private var selectionLayers: [CALayer] = []
    private var currentCursor: PluginCursorType = .arrow

    private let scrollbarWidth: CGFloat = 8
    private let scrollbarInset: CGFloat = 4
    private var scrollbarController: ScrollbarController<TextRegionContentController>?

    private let pageInset: CGFloat = 18
    private let headerHeight: CGFloat = 74
    private let textInsetX: CGFloat = 28
    private let textInsetY: CGFloat = 24

    private lazy var documentText: NSAttributedString = makeDocumentText()

    init(appConnection: OuterframeHost) {
        self.appConnection = appConnection
        super.init()

        textContainer.lineFragmentPadding = 0
        textLayoutManager.textContainer = textContainer
        contentStorage.addTextLayoutManager(textLayoutManager)
        contentStorage.attributedString = documentText
        textLayoutManager.usesFontLeading = true
    }

    func initialize(with data: Data, size: CGSize) -> CALayer? {
        currentSize = size
        scrollOffset = 0
        selectionRange = nil
        dragAnchorSelections = []

        let root = CALayer()
        disableImplicitAnimations(for: root)
        root.frame = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.isGeometryFlipped = true
        root.masksToBounds = true

        let title = makeTextLayer(font: .systemFont(ofSize: 22, weight: .semibold),
                                  fontSize: 22,
                                  color: .labelColor)
        title.string = "Text Region"
        root.addSublayer(title)

        let subtitle = makeTextLayer(font: .systemFont(ofSize: 14, weight: .regular),
                                     fontSize: 14,
                                     color: .secondaryLabelColor)
        subtitle.string = "TextKit 2 layout with scroll, selection, copy, and accessibility."
        subtitle.isWrapped = true
        root.addSublayer(subtitle)

        let background = CALayer()
        disableImplicitAnimations(for: background)
        background.backgroundColor = NSColor.textBackgroundColor.cgColor
        background.borderColor = NSColor.separatorColor.cgColor
        background.borderWidth = 1
        background.cornerRadius = 8
        root.addSublayer(background)

        let viewport = CALayer()
        disableImplicitAnimations(for: viewport)
        viewport.masksToBounds = true
        viewport.isGeometryFlipped = true
        root.addSublayer(viewport)

        let selectionLayer = CALayer()
        disableImplicitAnimations(for: selectionLayer)
        selectionLayer.isGeometryFlipped = true
        viewport.addSublayer(selectionLayer)

        let textLayer = TextKitDisplayLayer()
        disableImplicitAnimations(for: textLayer)
        textLayer.isGeometryFlipped = true
        textLayer.textLayoutManager = textLayoutManager
        viewport.addSublayer(textLayer)

        layers = Layers(rootLayer: root,
                        viewportLayer: viewport,
                        backgroundLayer: background,
                        titleLayer: title,
                        subtitleLayer: subtitle,
                        selectionLayer: selectionLayer,
                        textLayer: textLayer)

        scrollbarController = ScrollbarController<TextRegionContentController>(appConnection: appConnection,
                                                                                         viewportLayer: viewport,
                                                                                         appearance: NSAppearance.currentDrawing(),
                                                                                         width: scrollbarWidth,
                                                                                         inset: scrollbarInset,
                                                                                         scrollOffsetOrigin: .bottom)
        scrollbarController?.delegate = self

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

        case .rightMouseDown(let point, let modifierFlags, let clickCount):
            guard context.isPointInsideContent(point) else { return }
            rightMouseDown(at: point, modifierFlags: modifierFlags, clickCount: clickCount)

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
        currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        layout()
    }

    func cleanup() {
        scrollbarController?.cleanup()
        scrollbarController = nil
        selectionLayers = []
        layers = nil
        updateCursor(.arrow)
    }

    func mouseMoved(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        updateCursor(isPointOverText(point) ? .iBeam : .arrow, force: true)
    }

    func mouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {
        guard let layers else { return }

        let viewportPoint = layers.rootLayer.convert(point, to: layers.viewportLayer)
        if scrollbarController?.handleMouseDown(at: viewportPoint) == true {
            dragAnchorSelections = []
            return
        }

        guard isPointInTextRegion(point) else {
            setSelection(nil)
            dragAnchorSelections = []
            return
        }

        let textPoint = textContainerPoint(fromRootPoint: point)
        let textBounds = textContainerInteractionBounds()
        let selections = textLayoutManager.textSelectionNavigation.textSelections(interactingAt: textPoint,
                                                                                  inContainerAt: textLayoutManager.documentRange.location,
                                                                                  anchors: [],
                                                                                  modifiers: [],
                                                                                  selecting: false,
                                                                                  bounds: textBounds)
        dragAnchorSelections = selections

        if clickCount >= 3 {
            let fragmentSelection = textLayoutFragmentSelection(at: textPoint)
            dragAnchorSelections = fragmentSelection.map { [$0] } ?? []
            setSelection(fragmentSelection)
        } else if clickCount == 2, let selection = selections.first {
            let wordSelection = textLayoutManager.textSelectionNavigation.textSelection(for: .word,
                                                                                       enclosing: selection)
            setSelection(wordSelection)
        } else {
            setSelection(nil)
        }
    }

    func rightMouseDown(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags, clickCount: Int) {
        if !isPointInTextRegion(point) {
            return
        }

        if let location = textLocationOffset(at: point),
           let selectionRange,
           NSLocationInRange(location, selectionRange),
           let selectedText = selectedAttributedText() {
            appConnection.showContextMenu(for: selectedText, at: point)
            return
        }

        guard let selection = textSelection(at: point) else { return }
        let wordSelection = textLayoutManager.textSelectionNavigation.textSelection(for: .word,
                                                                                   enclosing: selection)
        guard let selectedText = attributedText(for: wordSelection),
              !selectedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        setSelection(wordSelection)
        appConnection.showContextMenu(for: selectedText, at: point)
    }

    func mouseDragged(to point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard let layers else { return }
        let viewportPoint = layers.rootLayer.convert(point, to: layers.viewportLayer)
        if scrollbarController?.handleMouseDragged(to: viewportPoint) == true {
            return
        }

        guard !dragAnchorSelections.isEmpty else { return }

        let textPoint = textContainerPoint(fromRootPoint: point)
        let selections = textLayoutManager.textSelectionNavigation.textSelections(interactingAt: textPoint,
                                                                                  inContainerAt: textLayoutManager.documentRange.location,
                                                                                  anchors: dragAnchorSelections,
                                                                                  modifiers: [.extend],
                                                                                  selecting: true,
                                                                                  bounds: textContainerInteractionBounds())
        setSelection(selections.first)
    }

    func mouseUp(at point: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        if let layers {
            _ = scrollbarController?.handleMouseUp(at: layers.rootLayer.convert(point, to: layers.viewportLayer))
        }
        dragAnchorSelections = []
    }

    func scrollWheel(delta: CGPoint,
                     at point: CGPoint,
                     modifierFlags: NSEvent.ModifierFlags,
                     phase: NSEvent.Phase,
                     momentumPhase: NSEvent.Phase,
                     hasPreciseScrollingDeltas: Bool) {
        let multiplier: CGFloat = hasPreciseScrollingDeltas ? 1.0 : 36.0
        let proposedOffset = scrollOffset - delta.y * multiplier
        setScrollOffset(proposedOffset)
    }

    func accessibilitySnapshotData() -> Data? {
        guard let layers else {
            return OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
        }

        let titleNode = OuterframeAccessibilityNode(identifier: 1,
                                                    role: .staticText,
                                                    frame: accessibilityFrame(fromVisualRootFrame: layers.titleLayer.frame),
                                                    label: "Text Region")
        let textNode = OuterframeAccessibilityNode(identifier: 2,
                                                   role: .container,
                                                   frame: accessibilityFrame(fromVisualRootFrame: textRegionFrame()),
                                                   label: "Scrollable selectable text",
                                                   value: documentText.string,
                                                   hint: "Select text to copy it.",
                                                   children: visibleTextFragmentAccessibilityNodes())
        let rootNode = OuterframeAccessibilityNode(identifier: 0,
                                                   role: .container,
                                                   frame: layers.rootLayer.frame,
                                                   label: "Text Region",
                                                   children: [titleNode, textNode])
        return OuterframeAccessibilitySnapshot(rootNodes: [rootNode]).serializedData()
    }

    func pasteboardItemsForCopy() -> [OuterContentPasteboardItem] {
        guard let selectedText = selectedAttributedText(), selectedText.length > 0 else {
            return []
        }

        var representations: [OuterContentPasteboardRepresentation] = []
        if let stringData = selectedText.string.data(using: .utf8) {
            representations.append(OuterContentPasteboardRepresentation(typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
                                                                        data: stringData))
        }
        if let rtfData = try? selectedText.data(from: NSRange(location: 0, length: selectedText.length),
                                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            representations.append(OuterContentPasteboardRepresentation(typeIdentifier: NSPasteboard.PasteboardType.rtf.rawValue,
                                                                        data: rtfData))
        }
        return representations.isEmpty ? [] : [OuterContentPasteboardItem(representations: representations)]
    }

    private func layout() {
        guard let layers else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layers.rootLayer.frame = CGRect(origin: .zero, size: currentSize)

        let contentWidth = max(currentSize.width - pageInset * 2, 240)
        layers.titleLayer.frame = CGRect(x: pageInset,
                                         y: 18,
                                         width: contentWidth,
                                         height: 28)
        layers.subtitleLayer.frame = CGRect(x: pageInset,
                                            y: 47,
                                            width: contentWidth,
                                            height: 34)

        let region = textRegionFrame()
        layers.backgroundLayer.frame = region
        layers.viewportLayer.frame = region.insetBy(dx: 1, dy: 1)
        layers.selectionLayer.frame = layers.viewportLayer.bounds
        layers.textLayer.frame = layers.viewportLayer.bounds
        layers.textLayer.visibleBounds = layers.viewportLayer.bounds
        layers.textLayer.textInset = CGPoint(x: textInsetX, y: textInsetY)

        let textWidth = max(layers.viewportLayer.bounds.width - textInsetX * 2 - scrollbarWidth - scrollbarInset, 80)
        textContainer.size = CGSize(width: textWidth, height: 1_000_000)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        setScrollOffset(min(scrollOffset, maxScrollOffsetValue()), notify: false)
        updateSelectionLayers()
        updateScrollbarLayout()
        layers.textLayer.setNeedsDisplay()

        CATransaction.commit()
    }

    private func setScrollOffset(_ value: CGFloat, notify: Bool = true) {
        let clamped = max(0, min(value, maxScrollOffsetValue()))
        guard abs(clamped - scrollOffset) > 0.0001 else {
            scrollOffset = clamped
            updateScrollbarLayout()
            return
        }

        scrollOffset = clamped
        layers?.textLayer.scrollOffset = clamped
        layers?.textLayer.setNeedsDisplay()
        layers?.textLayer.displayIfNeeded()
        updateSelectionLayers()
        updateScrollbarLayout()

        if notify {
            appConnection.notifyAccessibilityTreeChanged(.layoutChanged)
        }
    }

    private func setSelection(_ selection: NSTextSelection?) {
        textLayoutManager.textSelections = selection.map { [$0] } ?? []
        selectionRange = rangeOffsets(for: selection)
        updateSelectionLayers()
        appConnection.notifyAccessibilityTreeChanged(.selectedChildrenChanged)
    }

    private func updateSelectionLayers() {
        guard let layers else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for layer in selectionLayers {
            layer.removeFromSuperlayer()
        }
        selectionLayers = []

        guard let selectionRange,
              selectionRange.length > 0,
              let textRange = textRange(for: selectionRange) else {
            CATransaction.commit()
            return
        }

        let selectionColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.75).cgColor
        textLayoutManager.enumerateTextSegments(in: textRange,
                                                type: .selection,
                                                options: []) { _, rect, _, _ in
            let visibleFrame = CGRect(x: textInsetX + rect.minX,
                                      y: textInsetY + rect.minY - scrollOffset,
                                      width: rect.width,
                                      height: rect.height)
            guard visibleFrame.intersects(layers.selectionLayer.bounds) else {
                return true
            }

            let highlight = CALayer()
            disableImplicitAnimations(for: highlight)
            highlight.frame = visibleFrame
            highlight.backgroundColor = selectionColor
            highlight.cornerRadius = 2
            layers.selectionLayer.addSublayer(highlight)
            selectionLayers.append(highlight)
            return true
        }

        CATransaction.commit()
    }

    private func updateCursor(_ cursor: PluginCursorType, force: Bool = false) {
        guard force || cursor != currentCursor else { return }
        currentCursor = cursor
        appConnection.setCursor(cursor)
    }

    private func selectedAttributedText() -> NSAttributedString? {
        guard let selectionRange,
              selectionRange.length > 0,
              selectionRange.location >= 0,
              selectionRange.location + selectionRange.length <= documentText.length else {
            return nil
        }
        return documentText.attributedSubstring(from: selectionRange)
    }

    private func attributedText(for selection: NSTextSelection?) -> NSAttributedString? {
        guard let range = rangeOffsets(for: selection),
              range.location >= 0,
              range.location + range.length <= documentText.length else {
            return nil
        }
        return documentText.attributedSubstring(from: range)
    }

    private func rangeOffsets(for selection: NSTextSelection?) -> NSRange? {
        guard let textRange = selection?.textRanges.first else { return nil }
        let documentStart = textLayoutManager.documentRange.location
        let start = contentStorage.offset(from: documentStart, to: textRange.location)
        let end = contentStorage.offset(from: documentStart, to: textRange.endLocation)
        guard start != NSNotFound, end != NSNotFound else { return nil }
        let location = max(0, min(start, end))
        let length = min(documentText.length - location, abs(end - start))
        guard length > 0 else { return nil }
        return NSRange(location: location, length: length)
    }

    private func textRange(for range: NSRange) -> NSTextRange? {
        let documentStart = textLayoutManager.documentRange.location
        guard let start = contentStorage.location(documentStart, offsetBy: range.location),
              let end = contentStorage.location(documentStart, offsetBy: range.location + range.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }

    private func textRegionFrame() -> CGRect {
        let width = max(currentSize.width - pageInset * 2, 240)
        let y = headerHeight
        let height = max(currentSize.height - y - pageInset, 180)
        return CGRect(x: pageInset, y: y, width: width, height: height)
    }

    private func textContainerPoint(fromRootPoint point: CGPoint) -> CGPoint {
        guard let layers else {
            let region = textRegionFrame()
            return CGPoint(x: point.x - region.minX - textInsetX,
                           y: currentSize.height - point.y - region.minY + scrollOffset - textInsetY)
        }

        let visualRootPoint = CGPoint(x: point.x, y: currentSize.height - point.y)
        let viewportFrame = layers.viewportLayer.frame
        return CGPoint(x: visualRootPoint.x - viewportFrame.minX - textInsetX,
                       y: visualRootPoint.y - viewportFrame.minY + scrollOffset - textInsetY)
    }

    private func isPointInTextRegion(_ point: CGPoint) -> Bool {
        guard let layers else { return textRegionFrame().contains(point) }
        let visualRootPoint = CGPoint(x: point.x, y: currentSize.height - point.y)
        return layers.viewportLayer.frame.contains(visualRootPoint)
    }

    private func textSelection(at point: CGPoint) -> NSTextSelection? {
        let textPoint = textContainerPoint(fromRootPoint: point)
        return textLayoutManager.textSelectionNavigation.textSelections(interactingAt: textPoint,
                                                                        inContainerAt: textLayoutManager.documentRange.location,
                                                                        anchors: [],
                                                                        modifiers: [],
                                                                        selecting: false,
                                                                        bounds: textContainerInteractionBounds()).first
    }

    private func textLayoutFragmentSelection(at textPoint: CGPoint) -> NSTextSelection? {
        var matchingFragment: NSTextLayoutFragment?

        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location,
                                                        options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > textPoint.y {
                return false
            }

            let paragraphHitFrame = CGRect(x: 0,
                                           y: frame.minY,
                                           width: textContainer.size.width,
                                           height: max(frame.height, 1))
            if paragraphHitFrame.insetBy(dx: 0, dy: -2).contains(textPoint) {
                matchingFragment = fragment
                return false
            }
            return true
        }

        guard let range = matchingFragment?.rangeInElement else { return nil }
        return NSTextSelection([range], affinity: .downstream, granularity: .paragraph)
    }

    private func visibleTextFragmentAccessibilityNodes() -> [OuterframeAccessibilityNode] {
        guard let layers else { return [] }

        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        let viewportFrame = layers.viewportLayer.frame
        let viewportBoundsInRoot = viewportFrame
        let textWidth = max(textContainer.size.width, 1)
        var nodes: [OuterframeAccessibilityNode] = []

        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location,
                                                        options: [.ensuresLayout]) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            if fragmentFrame.minY > scrollOffset + viewportFrame.height {
                return false
            }

            let rootFrame = CGRect(x: viewportFrame.minX + textInsetX,
                                   y: viewportFrame.minY + textInsetY + fragmentFrame.minY - scrollOffset,
                                   width: textWidth,
                                   height: max(fragmentFrame.height, 1))
            guard rootFrame.intersects(viewportBoundsInRoot),
                  let fragmentText = string(for: fragment.rangeInElement),
                  !fragmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }

            let visibleFrame = accessibilityFrame(fromVisualRootFrame: rootFrame.intersection(viewportBoundsInRoot))
            let startOffset = offset(fromDocumentStartTo: fragment.rangeInElement.location)
            let identifier = UInt32(1_000 + max(0, min(startOffset, Int(UInt32.max) - 1_000)))
            nodes.append(OuterframeAccessibilityNode(identifier: identifier,
                                                     role: .staticText,
                                                     frame: visibleFrame,
                                                     value: fragmentText))
            return true
        }

        return nodes
    }

    private func accessibilityFrame(fromVisualRootFrame frame: CGRect) -> CGRect {
        CGRect(x: frame.minX,
               y: currentSize.height - frame.maxY,
               width: frame.width,
               height: frame.height)
    }

    private func string(for textRange: NSTextRange) -> String? {
        let documentStart = textLayoutManager.documentRange.location
        let start = contentStorage.offset(from: documentStart, to: textRange.location)
        let end = contentStorage.offset(from: documentStart, to: textRange.endLocation)
        guard start != NSNotFound, end != NSNotFound else { return nil }

        let location = max(0, min(start, end))
        let length = min(documentText.length - location, abs(end - start))
        guard length > 0 else { return nil }
        return documentText.attributedSubstring(from: NSRange(location: location, length: length)).string
    }

    private func offset(fromDocumentStartTo location: NSTextLocation) -> Int {
        let offset = contentStorage.offset(from: textLayoutManager.documentRange.location, to: location)
        return offset == NSNotFound ? 0 : offset
    }

    private func textLocationOffset(at point: CGPoint) -> Int? {
        guard let selection = textSelection(at: point),
              let range = selection.textRanges.first else {
            return nil
        }
        let offset = contentStorage.offset(from: textLayoutManager.documentRange.location,
                                           to: range.location)
        return offset == NSNotFound ? nil : offset
    }

    private func isPointOverText(_ point: CGPoint) -> Bool {
        guard isPointInTextRegion(point) else { return false }
        let textPoint = textContainerPoint(fromRootPoint: point)
        var found = false
        textLayoutManager.enumerateTextSegments(in: textLayoutManager.documentRange,
                                                type: .standard,
                                                options: []) { _, rect, _, _ in
            if rect.insetBy(dx: -1, dy: -2).contains(textPoint) {
                found = true
                return false
            }
            return rect.minY <= textPoint.y
        }
        return found
    }

    private func textContainerInteractionBounds() -> CGRect {
        CGRect(x: 0,
               y: 0,
               width: textContainer.size.width,
               height: max(contentHeight() - textInsetY * 2, textContainer.size.height))
    }

    private func contentHeight() -> CGFloat {
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        return max(textLayoutManager.usageBoundsForTextContainer.maxY + textInsetY * 2,
                   layers?.viewportLayer.bounds.height ?? 0)
    }

    private func maxScrollOffsetValue() -> CGFloat {
        guard let layers else { return 0 }
        return max(contentHeight() - layers.viewportLayer.bounds.height, 0)
    }

    private func updateScrollbarLayout() {
        guard let layers else { return }
        let metrics = ScrollbarController<TextRegionContentController>.Metrics(viewportSize: layers.viewportLayer.bounds.size,
                                                                                         contentHeight: contentHeight(),
                                                                                         scrollOffset: scrollOffset)
        scrollbarController?.updateLayout(metrics: metrics)
    }

    private func makeTextLayer(font: NSFont, fontSize: CGFloat, color: NSColor) -> CATextLayer {
        let layer = CATextLayer()
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer.alignmentMode = .left
        layer.font = font
        layer.fontSize = fontSize
        layer.foregroundColor = color.cgColor
        layer.truncationMode = .end
        return layer
    }

    private func disableImplicitAnimations(for layer: CALayer) {
        let null = NSNull()
        layer.actions = [
            "bounds": null,
            "position": null,
            "frame": null,
            "contents": null,
            "backgroundColor": null,
            "borderColor": null,
            "sublayers": null,
            "onOrderIn": null,
            "onOrderOut": null
        ]
    }

    private func makeDocumentText() -> NSAttributedString {
        let titleFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 16, weight: .regular)
        let captionFont = NSFont.systemFont(ofSize: 13, weight: .medium)

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineSpacing = 3
        bodyParagraph.paragraphSpacing = 14

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.paragraphSpacing = 12

        let captionParagraph = NSMutableParagraphStyle()
        captionParagraph.paragraphSpacing = 18

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "Lorem Ipsum, Selectable and Copyable\n",
                                         attributes: [
                                            .font: titleFont,
                                            .foregroundColor: NSColor.labelColor,
                                            .paragraphStyle: titleParagraph
                                         ]))
        result.append(NSAttributedString(string: "This page keeps text layout in TextKit 2 while the surrounding surface stays layer-backed. Drag through the paragraphs to highlight text, then copy it with the browser or system copy command.\n",
                                         attributes: [
                                            .font: captionFont,
                                            .foregroundColor: NSColor.secondaryLabelColor,
                                            .paragraphStyle: captionParagraph
                                         ]))

        let paragraphs = [
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer posuere, lacus at congue faucibus, lectus tortor facilisis lectus, vitae luctus justo dolor sed augue. Praesent efficitur magna at neque mollis, at mattis risus porttitor.",
            "Sed euismod, erat quis tempor sollicitudin, sem tortor luctus lectus, sed dignissim arcu massa vitae erat. Nam lacinia felis ac lacus fermentum, vel eleifend nibh fermentum. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae.",
            "Mauris pellentesque, massa quis facilisis dictum, mi arcu viverra erat, nec cursus lorem metus at arcu. Cras tristique magna vitae ex volutpat, in gravida dui dignissim. Suspendisse sed finibus purus.",
            "Donec blandit magna ac elit mattis, a luctus justo placerat. Aenean interdum finibus libero, vitae feugiat est rhoncus id. In at luctus mi. Nulla facilisi. Curabitur vitae ex vitae ipsum ullamcorper laoreet.",
            "Aliquam vitae interdum urna. Integer hendrerit, sapien sed venenatis porta, urna neque semper tortor, sed pretium odio erat nec urna. Phasellus porta ullamcorper eros, non varius justo sagittis sed.",
            "Fusce gravida velit ut massa rhoncus, vitae sagittis dolor consequat. Vivamus vehicula orci vitae diam iaculis posuere. Suspendisse potenti. Donec id nibh a justo eleifend efficitur non sed nisi.",
            "Nunc sed magna faucibus, hendrerit massa non, cursus turpis. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Ut euismod velit sit amet quam vulputate, ac cursus nibh dictum.",
            "Etiam bibendum tortor at enim volutpat, vel finibus sem laoreet. Morbi luctus tristique arcu, ac pretium sem convallis sit amet. Duis facilisis ligula lorem, vitae pulvinar enim pulvinar non.",
            "Proin pulvinar luctus sapien, id egestas nulla bibendum nec. Sed vestibulum, urna vel suscipit consequat, nibh tellus ultrices augue, a elementum risus libero at nulla. Integer non sem at elit interdum gravida.",
            "Ut accumsan gravida mauris, sit amet ultricies lorem eleifend nec. Integer a neque ut massa congue tincidunt. Suspendisse gravida velit vel sem facilisis, id posuere turpis sagittis."
        ]

        for (index, paragraph) in paragraphs.enumerated() {
            let mutable = NSMutableAttributedString(string: paragraph + "\n",
                                                    attributes: [
                                                        .font: bodyFont,
                                                        .foregroundColor: NSColor.labelColor,
                                                        .paragraphStyle: bodyParagraph
                                                    ])
            if index % 3 == 1 {
                mutable.addAttribute(.foregroundColor,
                                     value: NSColor.controlAccentColor,
                                     range: NSRange(location: 0, length: min(18, mutable.length)))
            }
            result.append(mutable)
        }

        return result
    }
}

extension TextRegionContentController: ScrollbarControllerDelegate {
    func scrollbarDidChangeScrollOffset(_ offset: CGFloat) {
        setScrollOffset(offset)
    }
}
