import Foundation
import AppKit
import QuartzCore

@MainActor
@objc final class TimelineRangeSelectorContentController: NSObject, CookbookPageController {
    private struct Layers {
        let rootLayer: CALayer
        let viewportLayer: CALayer
        let contentLayer: CALayer
        let cardLayer: CALayer
        let titleLayer: CATextLayer
        let subtitleLayer: CATextLayer
        let integralLabelLayer: CATextLayer
        let integralValueLayer: CATextLayer
        let rangeLabelLayer: CATextLayer
        let chartContainerLayer: CALayer
        let plotLayer: CAShapeLayer
        let baselineLayer: CALayer
        let selectionLayer: CALayer
        let startHandleLayer: CALayer
        let endHandleLayer: CALayer
        let hoverLineLayer: CAShapeLayer
        let hoverTextLayer: CATextLayer
    }

    private enum DragOperation {
        case creating(anchor: CGFloat)
        case adjustingStart
        case adjustingEnd
    }

    private let appConnection: OuterframeHost

    private var layers: Layers?
    private var currentSize: CGSize = CGSize(width: 800, height: 500)
    private var selectionRange: ClosedRange<CGFloat>? {
        didSet {
            updateSelectionPresentation()
            updateIntegralPresentation()
        }
    }

    private var dragOperation: DragOperation?
    private var creationDidMove = false
    private var cachedValueRange: (min: CGFloat, max: CGFloat) = (min: 0.0, max: 1.0)
    private var currentCursor: PluginCursorType = .arrow
    private var hoveringHandle = false

    private let cardCornerRadius: CGFloat = 14
    private let chartHeight: CGFloat = 240
    private let chartTopOffset: CGFloat = 210
    private let chartHorizontalInset: CGFloat = 40
    private let chartBottomInset: CGFloat = 64
    private let handleRadius: CGFloat = 6
    private let handleHitWidth: CGFloat = 16
    private let selectionStrokeColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
    private let unselectedFillColor = NSColor(calibratedWhite: 0.85, alpha: 0.85).cgColor

    private let domainStart: CGFloat = 0
    private let domainEnd: CGFloat = 12

    init(appConnection: OuterframeHost) {
        self.appConnection = appConnection
        super.init()
    }

    @objc func initialize(with data: Data, size: CGSize) -> CALayer? {
        currentSize = size
        selectionRange = nil

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let viewport = CALayer()
        viewport.frame = root.bounds
        viewport.isGeometryFlipped = true
        root.addSublayer(viewport)

        let content = CALayer()
        content.frame = viewport.bounds
        content.isGeometryFlipped = true
        viewport.addSublayer(content)

        let card = CALayer()
        card.backgroundColor = NSColor.textBackgroundColor.cgColor
        card.cornerRadius = cardCornerRadius
        card.shadowOpacity = 1
        card.shadowRadius = 8
        card.shadowColor = NSColor.black.withAlphaComponent(0.08).cgColor
        card.borderColor = NSColor.separatorColor.cgColor
        card.borderWidth = 1
        content.addSublayer(card)

        let title = makeTextLayer(font: .systemFont(ofSize: 22, weight: .semibold),
                                  color: .labelColor)
        title.string = "Timeline Range Selector"
        content.addSublayer(title)

        let subtitle = makeTextLayer(font: .systemFont(ofSize: 14, weight: .regular),
                                     color: .secondaryLabelColor)
        subtitle.string = "Click and drag to choose a range. Adjust a handle to refine."
        subtitle.isWrapped = true
        content.addSublayer(subtitle)

        let integralLabel = makeTextLayer(font: .systemFont(ofSize: 12, weight: .regular),
                                          color: .tertiaryLabelColor)
        integralLabel.string = "Integral of f(x) over selection"
        content.addSublayer(integralLabel)

        let integralValue = makeTextLayer(font: .monospacedDigitSystemFont(ofSize: 28, weight: .semibold),
                                          color: .labelColor)
        integralValue.string = "Select a range"
        content.addSublayer(integralValue)

        let rangeLabel = makeTextLayer(font: .systemFont(ofSize: 13, weight: .medium),
                                       color: .secondaryLabelColor)
        rangeLabel.string = "No selection"
        content.addSublayer(rangeLabel)

        let chartContainer = CALayer()
        chartContainer.masksToBounds = false
        chartContainer.isGeometryFlipped = true
        chartContainer.backgroundColor = NSColor.clear.cgColor
        chartContainer.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        chartContainer.borderWidth = 0
        content.addSublayer(chartContainer)

        let leftBoundaryLayer = CALayer()
        leftBoundaryLayer.backgroundColor = selectionStrokeColor
        leftBoundaryLayer.isHidden = true
        chartContainer.addSublayer(leftBoundaryLayer)

        let rightBoundaryLayer = CALayer()
        rightBoundaryLayer.backgroundColor = selectionStrokeColor
        rightBoundaryLayer.isHidden = true
        chartContainer.addSublayer(rightBoundaryLayer)

        let baseline = CALayer()
        baseline.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        chartContainer.addSublayer(baseline)

        let plotLayer = CAShapeLayer()
        plotLayer.strokeColor = NSColor.controlAccentColor.cgColor
        plotLayer.fillColor = NSColor.clear.cgColor
        plotLayer.lineWidth = 2
        plotLayer.lineJoin = .round
        plotLayer.lineCap = .round
        chartContainer.addSublayer(plotLayer)

        let dimmingLayer = CALayer()
        dimmingLayer.backgroundColor = unselectedFillColor
        dimmingLayer.isHidden = true
        chartContainer.addSublayer(dimmingLayer)

        let hoverLineLayer = CAShapeLayer()
        hoverLineLayer.strokeColor = NSColor.secondaryLabelColor.cgColor
        hoverLineLayer.lineDashPattern = [4, 3]
        hoverLineLayer.lineWidth = 1
        hoverLineLayer.isHidden = true
        chartContainer.addSublayer(hoverLineLayer)

        let hoverText = makeTextLayer(font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                      color: .labelColor)
        hoverText.alignmentMode = .center
        hoverText.isHidden = true
        chartContainer.addSublayer(hoverText)

        layers = Layers(rootLayer: root,
                        viewportLayer: viewport,
                        contentLayer: content,
                        cardLayer: card,
                        titleLayer: title,
                        subtitleLayer: subtitle,
                        integralLabelLayer: integralLabel,
                        integralValueLayer: integralValue,
                        rangeLabelLayer: rangeLabel,
                        chartContainerLayer: chartContainer,
                        plotLayer: plotLayer,
                        baselineLayer: baseline,
                        selectionLayer: dimmingLayer,
                        startHandleLayer: leftBoundaryLayer,
                        endHandleLayer: rightBoundaryLayer,
                        hoverLineLayer: hoverLineLayer,
                        hoverTextLayer: hoverText)

        layoutContent()
        return root
    }

    @objc func resize(width: Int, height: Int) {
        currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        layoutContent()
    }

    @objc func updateLayer(timestamp _: CFTimeInterval) {}

    @objc func cleanup() {
        appConnection.setCursor(.arrow)
        currentCursor = .arrow
        hoveringHandle = false
        layers = nil
    }

    @objc func mouseDown(at point: CGPoint, modifierFlags _: NSEvent.ModifierFlags, clickCount _: Int) {
        guard let layers else {
            dragOperation = nil
            return
        }
        let viewportPoint = layers.rootLayer.convert(point, to: layers.viewportLayer)
        guard let location = chartLocation(forViewportPoint: viewportPoint, allowClamped: false) else {
            dragOperation = nil
            return
        }
        let fraction = fraction(forChartLocation: location)

        if let currentRange = selectionRange {
            let width = layers.chartContainerLayer.bounds.width
            let startX = currentRange.lowerBound * width
            let endX = currentRange.upperBound * width
            if abs(location.x - startX) <= handleHitWidth {
                dragOperation = .adjustingStart
                return
            }
            if abs(location.x - endX) <= handleHitWidth {
                dragOperation = .adjustingEnd
                return
            }
            if location.x >= startX && location.x <= endX {
                selectionRange = nil
                creationDidMove = false
                dragOperation = .creating(anchor: fraction)
                return
            }
        }

        selectionRange = nil
        creationDidMove = false
        dragOperation = .creating(anchor: fraction)
    }

    @objc func mouseDragged(to point: CGPoint, modifierFlags _: NSEvent.ModifierFlags) {
        guard let layers else { return }
        let viewportPoint = layers.rootLayer.convert(point, to: layers.viewportLayer)
        guard let operation = dragOperation else { return }

        switch operation {
        case .creating(let anchor):
            guard let location = chartLocation(forViewportPoint: viewportPoint, allowClamped: true) else { return }
            let fraction = fraction(forChartLocation: location)
            if creationDidMove == false && abs(fraction - anchor) > 0.001 {
                creationDidMove = true
            }
            guard creationDidMove else { return }
            let lower = min(anchor, fraction)
            let upper = max(anchor, fraction)
            selectionRange = lower...upper
        case .adjustingStart:
            guard var range = selectionRange else { return }
            guard let location = chartLocation(forViewportPoint: viewportPoint, allowClamped: true) else { return }
            let fraction = fraction(forChartLocation: location)
            range = min(max(fraction, 0), range.upperBound)...range.upperBound
            selectionRange = normalized(range)
        case .adjustingEnd:
            guard var range = selectionRange else { return }
            guard let location = chartLocation(forViewportPoint: viewportPoint, allowClamped: true) else { return }
            let fraction = fraction(forChartLocation: location)
            range = range.lowerBound...max(min(fraction, 1), range.lowerBound)
            selectionRange = normalized(range)
        }

        updateHoverCursor(forViewportPoint: viewportPoint)
    }

    @objc func mouseUp(at point: CGPoint, modifierFlags _: NSEvent.ModifierFlags) {
        if case .creating = dragOperation, creationDidMove == false {
            selectionRange = nil
        }
        dragOperation = nil
        creationDidMove = false
        if let layers {
            let viewportPoint = layers.rootLayer.convert(point, to: layers.viewportLayer)
            updateHoverCursor(forViewportPoint: viewportPoint)
            updateHoverIndicator(withViewportPoint: viewportPoint, isTracking: false)
        } else {
            updateCursor(.arrow)
        }
    }

    @objc func mouseMoved(to point: CGPoint, modifierFlags _: NSEvent.ModifierFlags) {
        guard let layers else {
            updateCursor(.arrow)
            return
        }
        let viewportPoint = layers.rootLayer.convert(point, to: layers.viewportLayer)
        updateHoverCursor(forViewportPoint: viewportPoint)
        updateHoverIndicator(withViewportPoint: viewportPoint, isTracking: true)
    }

    private func layoutContent() {
        guard let layers else { return }

        let bounds = CGRect(origin: .zero, size: currentSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layers.rootLayer.frame = bounds
        layers.viewportLayer.frame = bounds
        layers.contentLayer.frame = bounds

        let cardWidth = max(currentSize.width - 64, 420)
        let cardHeight = max(currentSize.height - 64, chartHeight + chartTopOffset + chartBottomInset)
        let cardFrame = CGRect(x: max(32, (currentSize.width - cardWidth) / 2),
                               y: 32,
                               width: cardWidth,
                               height: cardHeight)
        layers.cardLayer.frame = cardFrame

        layers.titleLayer.frame = CGRect(x: cardFrame.minX + 32,
                                         y: cardFrame.minY + 32,
                                         width: cardFrame.width - 64,
                                         height: 28)

        layers.subtitleLayer.frame = CGRect(x: cardFrame.minX + 32,
                                            y: cardFrame.minY + 64,
                                            width: cardFrame.width - 64,
                                            height: 42)

        layers.integralLabelLayer.frame = CGRect(x: cardFrame.minX + 32,
                                                 y: cardFrame.minY + 110,
                                                 width: cardFrame.width - 64,
                                                 height: 18)

        layers.integralValueLayer.frame = CGRect(x: cardFrame.minX + 32,
                                                 y: cardFrame.minY + 130,
                                                 width: cardFrame.width - 64,
                                                 height: 36)

        layers.rangeLabelLayer.frame = CGRect(x: cardFrame.minX + 32,
                                              y: cardFrame.minY + 172,
                                              width: cardFrame.width - 64,
                                              height: 20)

        let chartWidth = cardFrame.width - (chartHorizontalInset * 2)
        let chartFrame = CGRect(x: cardFrame.minX + chartHorizontalInset,
                                y: cardFrame.minY + chartTopOffset,
                                width: chartWidth,
                                height: chartHeight)
        layers.chartContainerLayer.frame = chartFrame

        layers.baselineLayer.frame = CGRect(x: 0,
                                            y: chartContainerBaselineY(),
                                            width: chartWidth,
                                            height: 1)

        layers.plotLayer.frame = layers.chartContainerLayer.bounds
        updatePlotPath()
        updateSelectionPresentation()
        updateIntegralPresentation()

        CATransaction.commit()
    }

    private func updatePlotPath() {
        guard let layers else { return }
        let bounds = layers.chartContainerLayer.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let sampleCount = 400
        var minValue: CGFloat = .greatestFiniteMagnitude
        var maxValue: CGFloat = -.greatestFiniteMagnitude
        var values: [CGFloat] = []
        values.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let fraction = CGFloat(i) / CGFloat(sampleCount - 1)
            let domainValue = domainStart + (domainEnd - domainStart) * fraction
            let value = functionValue(at: domainValue)
            values.append(value)
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }

        if maxValue - minValue < 0.01 {
            maxValue = minValue + 0.01
        }
        cachedValueRange = (min: minValue, max: maxValue)

        let path = CGMutablePath()
        for (index, value) in values.enumerated() {
            let fraction = CGFloat(index) / CGFloat(sampleCount - 1)
            let x = bounds.minX + fraction * bounds.width
            let normalized = (value - minValue) / (maxValue - minValue)
            let y = bounds.minY + (1 - normalized) * bounds.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        layers.plotLayer.path = path
    }

    private func updateSelectionPresentation() {
        guard let layers else { return }
        let bounds = layers.chartContainerLayer.bounds
        guard bounds.width > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard let range = selectionRange else {
            layers.selectionLayer.isHidden = true
            layers.selectionLayer.mask = nil
            layers.startHandleLayer.isHidden = true
            layers.endHandleLayer.isHidden = true
            CATransaction.commit()
            return
        }

        let startX = bounds.minX + range.lowerBound * bounds.width
        let endX = bounds.minX + range.upperBound * bounds.width

        layers.selectionLayer.isHidden = false
        layers.selectionLayer.frame = bounds
        layers.selectionLayer.backgroundColor = unselectedFillColor
        layers.selectionLayer.mask = makeDimmingMaskLayer(bounds: bounds,
                                                          selectionStartX: startX,
                                                          selectionEndX: endX)

        let boundaryWidth: CGFloat = 2
        layers.startHandleLayer.isHidden = false
        layers.startHandleLayer.frame = CGRect(x: startX - boundaryWidth / 2,
                                               y: bounds.minY,
                                               width: boundaryWidth,
                                               height: bounds.height)

        layers.endHandleLayer.isHidden = false
        layers.endHandleLayer.frame = CGRect(x: endX - boundaryWidth / 2,
                                             y: bounds.minY,
                                             width: boundaryWidth,
                                             height: bounds.height)
        CATransaction.commit()
    }

    private func makeDimmingMaskLayer(bounds: CGRect, selectionStartX: CGFloat, selectionEndX: CGFloat) -> CALayer? {
        let mask = CAShapeLayer()
        mask.frame = bounds

        let path = CGMutablePath()
        path.addRect(bounds)
        let selectionRect = CGRect(x: min(selectionStartX, selectionEndX),
                                   y: bounds.minY,
                                   width: max(selectionEndX - selectionStartX, 0),
                                   height: bounds.height)
        path.addRect(selectionRect)
        mask.path = path
        mask.fillRule = .evenOdd
        return mask
    }

    private func updateIntegralPresentation() {
        guard let layers else { return }
        guard let range = selectionRange else {
            layers.integralValueLayer.string = "Select a range"
            layers.rangeLabelLayer.string = "Click and drag over the curve"
            return
        }

        let start = domainValue(forFraction: range.lowerBound)
        let end = domainValue(forFraction: range.upperBound)
        let integral = computeIntegral(from: start, to: end)

        layers.integralValueLayer.string = String(format: "∫ = %.2f", integral)
        layers.rangeLabelLayer.string = String(format: "Range: %.2f → %.2f", start, end)
    }

    private func chartLocation(forViewportPoint point: CGPoint, allowClamped: Bool) -> CGPoint? {
        guard let layers else { return nil }
        var location = layers.chartContainerLayer.convert(point, from: layers.viewportLayer)
        let bounds = layers.chartContainerLayer.bounds

        if allowClamped {
            location.x = min(max(location.x, bounds.minX), bounds.maxX)
            location.y = min(max(location.y, bounds.minY), bounds.maxY)
            return location
        }

        guard bounds.contains(location) else { return nil }
        return location
    }

    private func fraction(forChartLocation location: CGPoint) -> CGFloat {
        guard let layers else { return 0 }
        let width = layers.chartContainerLayer.bounds.width
        guard width > 0 else { return 0 }
        return min(max(location.x / width, 0), 1)
    }

    private func normalized(_ range: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        let lower = min(max(range.lowerBound, 0), 1)
        let upper = min(max(range.upperBound, 0), 1)
        if upper < lower {
            return upper...upper
        }
        return lower...upper
    }

    private func functionValue(at x: CGFloat) -> CGFloat {
        let waveA = sin(x * 0.9)
        let waveB = 0.35 * sin(x * 2.1 + 0.7)
        let waveC = 0.2 * cos(x * 3.7)
        return waveA + waveB + waveC + 2.0
    }

    private func computeIntegral(from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return 0 }
        let steps = 512
        let delta = (end - start) / CGFloat(steps)
        var sum: CGFloat = 0
        for i in 0...steps {
            let x = start + CGFloat(i) * delta
            let weight: CGFloat = (i == 0 || i == steps) ? 0.5 : 1
            sum += weight * functionValue(at: x)
        }
        return sum * delta
    }

    private func domainValue(forFraction fraction: CGFloat) -> CGFloat {
        return domainStart + (domainEnd - domainStart) * fraction
    }

    private func chartContainerBaselineY() -> CGFloat {
        guard let layers else { return chartHeight - 1 }
        return max(layers.chartContainerLayer.bounds.height - 1, 0)
    }

    private func makeTextLayer(font: NSFont, color: NSColor) -> CATextLayer {
        let layer = CATextLayer()
        layer.font = font
        layer.fontSize = font.pointSize
        layer.contentsScale = 2.0
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = .left
        layer.isWrapped = false
        return layer
    }

    private func updateHoverCursor(forViewportPoint point: CGPoint) {
        guard let layers else {
            updateCursor(.arrow)
            setHoveringHandle(false)
            return
        }
        guard let range = selectionRange else {
            updateCursor(.arrow)
            setHoveringHandle(false)
            return
        }
        guard let location = chartLocation(forViewportPoint: point, allowClamped: false) else {
            updateCursor(.arrow)
            setHoveringHandle(false)
            return
        }

        let width = layers.chartContainerLayer.bounds.width
        guard width > 0 else {
            updateCursor(.arrow)
            setHoveringHandle(false)
            return
        }

        let startX = range.lowerBound * width
        let endX = range.upperBound * width
        if abs(location.x - startX) <= handleHitWidth || abs(location.x - endX) <= handleHitWidth {
            setHoveringHandle(true)
            updateCursor(.resizeLeftRight)
        } else {
            setHoveringHandle(false)
            updateCursor(.arrow)
        }
    }

    private func updateCursor(_ cursor: PluginCursorType) {
        guard cursor != currentCursor else { return }
        currentCursor = cursor
        appConnection.setCursor(cursor)
    }

    private func setHoveringHandle(_ newValue: Bool) {
        if newValue && !hoveringHandle {
            appConnection.performHapticFeedback(.alignment)
        }
        hoveringHandle = newValue
    }

    private func updateHoverIndicator(withViewportPoint point: CGPoint, isTracking: Bool) {
        guard let layers else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard let location = chartLocation(forViewportPoint: point, allowClamped: true) else {
            layers.hoverLineLayer.isHidden = true
            layers.hoverTextLayer.isHidden = true
            CATransaction.commit()
            return
        }

        let bounds = layers.chartContainerLayer.bounds
        let fraction = fraction(forChartLocation: location)
        let x = bounds.minX + fraction * bounds.width

        layers.hoverLineLayer.isHidden = false
        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: x, y: bounds.minY))
        linePath.addLine(to: CGPoint(x: x, y: bounds.maxY))
        layers.hoverLineLayer.path = linePath

        let domainX = domainValue(forFraction: fraction)
        let valueY = functionValue(at: domainX)
        let valueRange = cachedValueRange
        let normalized = (valueY - valueRange.min) / max(valueRange.max - valueRange.min, 0.0001)
        let textY = bounds.minY + (1 - normalized) * bounds.height
        let valueString = String(format: "x=%.2f  f(x)=%.2f", domainX, valueY)

        layers.hoverTextLayer.isHidden = false
        layers.hoverTextLayer.string = valueString
        let textWidth: CGFloat = 140
        let textHeight: CGFloat = 18
        let textOriginX = min(max(x - textWidth / 2, bounds.minX), bounds.maxX - textWidth)
        let textOriginY = min(max(textY - textHeight - 6, bounds.minY), bounds.maxY - textHeight)
        layers.hoverTextLayer.frame = CGRect(x: textOriginX,
                                             y: textOriginY,
                                             width: textWidth,
                                             height: textHeight)
        CATransaction.commit()
    }
}
