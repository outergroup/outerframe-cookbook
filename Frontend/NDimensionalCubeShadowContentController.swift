import AppKit
import Metal
import QuartzCore

@MainActor
@objc final class NDimensionalCubeShadowContentController: NSObject, CookbookPageController {
    private struct Layers {
        let rootLayer: CALayer
        let viewportLayer: CALayer
        let panelLayer: CALayer
        let titleLayer: CATextLayer
        let subtitleLayer: CATextLayer
        let metalContainerLayer: CALayer
        let metalLayer: CAMetalLayer
        let errorLayer: CATextLayer
    }

    private struct Uniforms {
        var axis01: SIMD4<Float>
        var axis23: SIMD4<Float>
        var axis4: SIMD4<Float>
    }

    private let appConnection: OuterframeHost

    private var layers: Layers?
    private var currentSize = CGSize(width: 800, height: 600)
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var displayLinkCallbackId: UUID?
    private var animationStartTime: CFTimeInterval = 0
    private var setupError: String?

    private let dimension = 5
    private let contentInset: CGFloat = 24
    private let panelCornerRadius: CGFloat = 8
    private let metalCornerRadius: CGFloat = 6
    private let minimumMetalHeight: CGFloat = 260
    private let maximumMetalHeight: CGFloat = 520

    init(appConnection: OuterframeHost) {
        self.appConnection = appConnection
        super.init()
    }

    func initialize(with _: Data, size: CGSize) -> CALayer? {
        currentSize = size
        animationStartTime = CACurrentMediaTime()
        setupMetalIfNeeded()

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let viewport = CALayer()
        viewport.frame = root.bounds
        viewport.isGeometryFlipped = true
        viewport.masksToBounds = true
        root.addSublayer(viewport)

        let panel = CALayer()
        panel.backgroundColor = NSColor.textBackgroundColor.cgColor
        panel.borderColor = NSColor.separatorColor.cgColor
        panel.borderWidth = 1
        panel.cornerRadius = panelCornerRadius
        viewport.addSublayer(panel)

        let title = makeTextLayer(font: .systemFont(ofSize: 22, weight: .semibold),
                                  fontSize: 22,
                                  color: .labelColor)
        title.string = "N-Dimensional Cube Shadow"
        viewport.addSublayer(title)

        let subtitle = makeTextLayer(font: .systemFont(ofSize: 14, weight: .regular),
                                     fontSize: 14,
                                     color: .secondaryLabelColor)
        subtitle.string = "A 5D cube rotating in N-space, projected as translucent square faces."
        subtitle.isWrapped = true
        viewport.addSublayer(subtitle)

        let metalContainer = CALayer()
        metalContainer.backgroundColor = NSColor.textBackgroundColor.cgColor
        metalContainer.borderColor = NSColor.separatorColor.cgColor
        metalContainer.borderWidth = 1
        metalContainer.cornerRadius = metalCornerRadius
        metalContainer.masksToBounds = true
        viewport.addSublayer(metalContainer)

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.presentsWithTransaction = false
        metalContainer.addSublayer(metalLayer)

        let error = makeTextLayer(font: .systemFont(ofSize: 13, weight: .regular),
                                  fontSize: 13,
                                  color: .systemRed)
        error.isWrapped = true
        error.string = setupError ?? ""
        viewport.addSublayer(error)

        layers = Layers(rootLayer: root,
                        viewportLayer: viewport,
                        panelLayer: panel,
                        titleLayer: title,
                        subtitleLayer: subtitle,
                        metalContainerLayer: metalContainer,
                        metalLayer: metalLayer,
                        errorLayer: error)

        layout()
        startDisplayLinkIfNeeded()
        renderFrame(targetTimestamp: animationStartTime)
        return root
    }

    func resize(width: Int, height: Int) {
        currentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        layout()
        renderFrame(targetTimestamp: CACurrentMediaTime())
    }

    func cleanup() {
        stopDisplayLinkIfNeeded()
        layers?.metalLayer.removeFromSuperlayer()
        layers = nil
    }

    func accessibilitySnapshotData() -> Data? {
        guard let layers else {
            return OuterframeAccessibilitySnapshot.notImplementedSnapshot().serializedData()
        }

        let child = OuterframeAccessibilityNode(identifier: 1,
                                                role: .image,
                                                frame: layers.viewportLayer.convert(layers.metalContainerLayer.frame, to: layers.rootLayer),
                                                label: "Rotating 5D cube face projection")
        let rootNode = OuterframeAccessibilityNode(identifier: 0,
                                                   role: .container,
                                                   frame: layers.rootLayer.bounds,
                                                   label: "N-Dimensional Cube Shadow",
                                                   children: [child])
        return OuterframeAccessibilitySnapshot(rootNodes: [rootNode]).serializedData()
    }

    private func setupMetalIfNeeded() {
        guard device == nil else { return }

        guard let device = MTLCreateSystemDefaultDevice() else {
            setupError = "Metal is not available on this Mac."
            return
        }

        guard let commandQueue = device.makeCommandQueue() else {
            setupError = "Could not create a Metal command queue."
            return
        }

        do {
            let bundle = Bundle(for: type(of: self))
            let library = try device.makeDefaultLibrary(bundle: bundle)
            guard let vertexFunction = library.makeFunction(name: "nDimensionalCubeShadowVertex"),
                  let fragmentFunction = library.makeFunction(name: "nDimensionalCubeShadowFragment") else {
                setupError = "Could not find the N-cube Metal shaders."
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            setupError = "Could not build the Metal pipeline: \(error.localizedDescription)"
            return
        }

        self.device = device
        self.commandQueue = commandQueue
        setupError = nil
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLinkCallbackId == nil else { return }
        displayLinkCallbackId = appConnection.registerDisplayLinkCallback { [weak self] timestamp in
            self?.renderFrame(targetTimestamp: timestamp)
        }
    }

    private func stopDisplayLinkIfNeeded() {
        guard let callbackId = displayLinkCallbackId else { return }
        appConnection.stopDisplayLinkCallback(callbackId)
        displayLinkCallbackId = nil
    }

    private func renderFrame(targetTimestamp: CFTimeInterval) {
        guard let layers,
              let commandQueue,
              let pipelineState,
              layers.metalLayer.drawableSize.width >= 1,
              layers.metalLayer.drawableSize.height >= 1,
              let drawable = layers.metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let elapsed = max(targetTimestamp - animationStartTime, 0)
        var uniforms = makeProjectionUniforms(time: Float(elapsed),
                                              drawableSize: layers.metalLayer.drawableSize)

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeProjectionUniforms(time: Float, drawableSize: CGSize) -> Uniforms {
        let scale = Float(0.78 / sqrt(Double(dimension)))
        let width = max(Float(drawableSize.width), 1)
        let height = max(Float(drawableSize.height), 1)
        let side = min(width, height)
        let scaleX = scale * side / width
        let scaleY = scale * side / height

        var axes: [SIMD2<Float>] = []
        axes.reserveCapacity(dimension)
        for axis in 0..<dimension {
            var basis = Array(repeating: Float(0), count: dimension)
            basis[axis] = 1
            let rotated = rotate(vector: basis, time: time)
            axes.append(SIMD2<Float>(rotated[0] * scaleX, rotated[1] * scaleY))
        }

        return Uniforms(axis01: SIMD4<Float>(axes[0].x, axes[0].y, axes[1].x, axes[1].y),
                        axis23: SIMD4<Float>(axes[2].x, axes[2].y, axes[3].x, axes[3].y),
                        axis4: SIMD4<Float>(axes[4].x, axes[4].y, 0, 0))
    }

    private func rotate(vector: [Float], time: Float) -> [Float] {
        var result = vector

        for firstAxis in 0..<(dimension - 1) {
            for secondAxis in (firstAxis + 1)..<dimension {
                let speed = 0.16 + Float((firstAxis * dimension + secondAxis) % 7) * 0.031
                let angle = time * speed + Float(firstAxis + secondAxis) * 0.23
                let cosine = cos(angle)
                let sine = sin(angle)
                let firstValue = result[firstAxis]
                let secondValue = result[secondAxis]
                result[firstAxis] = firstValue * cosine - secondValue * sine
                result[secondAxis] = firstValue * sine + secondValue * cosine
            }
        }

        return result
    }

    private func layout() {
        guard let layers else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layers.rootLayer.frame = CGRect(origin: .zero, size: currentSize)
        layers.viewportLayer.frame = layers.rootLayer.bounds

        let contentWidth = min(max(currentSize.width - contentInset * 2, 280), 920)
        let contentX = max((currentSize.width - contentWidth) * 0.5, contentInset)
        let availableHeight = max(currentSize.height - 190, minimumMetalHeight)
        let metalHeight = min(max(availableHeight, minimumMetalHeight), maximumMetalHeight)
        let metalY: CGFloat = 132
        let panelHeight = metalY + metalHeight + 32

        layers.panelLayer.frame = CGRect(x: contentX - 18,
                                         y: 34,
                                         width: contentWidth + 36,
                                         height: panelHeight)
        layers.titleLayer.frame = CGRect(x: contentX,
                                         y: 56,
                                         width: contentWidth,
                                         height: 28)
        layers.subtitleLayer.frame = CGRect(x: contentX,
                                            y: 88,
                                            width: contentWidth,
                                            height: 36)
        layers.metalContainerLayer.frame = CGRect(x: contentX,
                                                  y: metalY,
                                                  width: contentWidth,
                                                  height: metalHeight)
        layers.metalLayer.frame = layers.metalContainerLayer.bounds

        let scale = layers.metalLayer.contentsScale
        layers.metalLayer.drawableSize = CGSize(width: max(layers.metalLayer.bounds.width * scale, 1),
                                                height: max(layers.metalLayer.bounds.height * scale, 1))

        layers.errorLayer.frame = CGRect(x: contentX,
                                         y: layers.metalContainerLayer.frame.maxY + 10,
                                         width: contentWidth,
                                         height: 36)
        layers.errorLayer.isHidden = setupError == nil

        CATransaction.commit()
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
}
