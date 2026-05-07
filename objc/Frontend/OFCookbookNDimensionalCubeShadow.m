#import "OFCookbookController.h"

@implementation OFCookbookController (NDimensionalCubeShadow)

- (void)renderNCube {
    [self setupMetalIfNeeded];

    CGFloat contentInset = 24;
    CGFloat contentWidth = MIN(MAX(self.currentSize.width - contentInset * 2, 280), 920);
    CGFloat contentX = MAX((self.currentSize.width - contentWidth) * 0.5, contentInset);
    CGFloat availableHeight = MAX(self.currentSize.height - 190, 260);
    CGFloat metalHeight = MIN(MAX(availableHeight, 260), 520);
    CGFloat metalY = 132;
    CALayer *panel = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 8);
    panel.frame = CGRectMake(contentX - 18, 34, contentWidth + 36, metalY + metalHeight + 32);
    [self.pageLayer addSublayer:panel];
    [self addText:@"N-Dimensional Cube Shadow" fontSize:22 weight:NSFontWeightSemibold color:NSColor.labelColor frame:CGRectMake(contentX, 56, contentWidth, 28)];
    [self addText:@"A 5D cube rotating in N-space, projected as translucent square faces." fontSize:14 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor frame:CGRectMake(contentX, 88, contentWidth, 36)];

    CGRect canvas = CGRectMake(contentX, metalY, contentWidth, metalHeight);
    CALayer *metalContainer = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 6);
    metalContainer.frame = canvas;
    metalContainer.masksToBounds = YES;
    [self.pageLayer addSublayer:metalContainer];

    if (self.metalDevice && self.metalCommandQueue && self.metalPipelineState) {
        CAMetalLayer *metalLayer = [CAMetalLayer layer];
        metalLayer.device = self.metalDevice;
        metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        metalLayer.framebufferOnly = YES;
        metalLayer.contentsScale = NSScreen.mainScreen.backingScaleFactor ?: 2.0;
        metalLayer.presentsWithTransaction = NO;
        metalLayer.frame = metalContainer.bounds;
        CGFloat scale = metalLayer.contentsScale;
        metalLayer.drawableSize = CGSizeMake(MAX(metalLayer.bounds.size.width * scale, 1),
                                             MAX(metalLayer.bounds.size.height * scale, 1));
        [metalContainer addSublayer:metalLayer];
        self.metalLayer = metalLayer;
        [self renderNCubeFrameAtTimestamp:CACurrentMediaTime()];
    }

    if (self.metalSetupError.length > 0) {
        CATextLayer *error = OFTextLayer(self.metalSetupError, [NSFont systemFontOfSize:13 weight:NSFontWeightRegular], NSColor.systemRedColor, 13);
        error.frame = CGRectMake(contentX, CGRectGetMaxY(canvas) + 10, contentWidth, 36);
        [self.pageLayer addSublayer:error];
    }
    [self addAccessibilityLabel:@"Rotating 5D cube face projection" frame:canvas role:OFAccessibilityRoleImage];
}

- (void)setupMetalIfNeeded {
    if (self.metalDevice || self.metalSetupError.length > 0) {
        return;
    }

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        self.metalSetupError = @"Metal is not available on this Mac.";
        return;
    }

    id<MTLCommandQueue> commandQueue = [device newCommandQueue];
    if (!commandQueue) {
        self.metalSetupError = @"Could not create a Metal command queue.";
        return;
    }

    NSError *error = nil;
    id<MTLLibrary> library = [device newDefaultLibraryWithBundle:[NSBundle bundleForClass:self.class] error:&error];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"nDimensionalCubeShadowVertex"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"nDimensionalCubeShadowFragment"];
    if (!library || !vertexFunction || !fragmentFunction) {
        self.metalSetupError = error.localizedDescription.length > 0 ? [NSString stringWithFormat:@"Could not build the Metal library: %@", error.localizedDescription] : @"Could not find the N-cube Metal shaders.";
        return;
    }

    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!pipelineState) {
        self.metalSetupError = error.localizedDescription.length > 0 ? [NSString stringWithFormat:@"Could not build the Metal pipeline: %@", error.localizedDescription] : @"Could not build the Metal pipeline.";
        return;
    }

    self.metalDevice = device;
    self.metalCommandQueue = commandQueue;
    self.metalPipelineState = pipelineState;
    self.metalSetupError = nil;
}

- (void)renderNCubeFrameAtTimestamp:(CFTimeInterval)targetTimestamp {
    CAMetalLayer *metalLayer = self.metalLayer;
    if (!metalLayer || !self.metalCommandQueue || !self.metalPipelineState ||
        metalLayer.drawableSize.width < 1 || metalLayer.drawableSize.height < 1) {
        return;
    }

    id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
    id<MTLCommandBuffer> commandBuffer = [self.metalCommandQueue commandBuffer];
    if (!drawable || !commandBuffer) {
        return;
    }

    CFTimeInterval elapsed = MAX(targetTimestamp - self.cubeAnimationStartTime, 0);
    OFNCubeUniforms uniforms = [self makeNCubeUniformsAtTime:(float)elapsed drawableSize:metalLayer.drawableSize];

    MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    descriptor.colorAttachments[0].texture = drawable.texture;
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.96, 0.96, 0.94, 1.0);

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    if (!encoder) {
        return;
    }

    [encoder setRenderPipelineState:self.metalPipelineState];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

- (OFNCubeUniforms)makeNCubeUniformsAtTime:(float)time drawableSize:(CGSize)drawableSize {
    float scale = (float)(0.78 / sqrt((double)OFNCubeDimension));
    float width = MAX((float)drawableSize.width, 1.0f);
    float height = MAX((float)drawableSize.height, 1.0f);
    float side = MIN(width, height);
    float scaleX = scale * side / width;
    float scaleY = scale * side / height;
    vector_float2 axes[OFNCubeDimension];

    for (int axis = 0; axis < OFNCubeDimension; axis++) {
        float basis[OFNCubeDimension] = {0};
        float rotated[OFNCubeDimension] = {0};
        basis[axis] = 1.0f;
        [self rotateNCubeVector:basis time:time output:rotated];
        axes[axis] = (vector_float2){ rotated[0] * scaleX, rotated[1] * scaleY };
    }

    OFNCubeUniforms uniforms = {
        .axis01 = (vector_float4){ axes[0].x, axes[0].y, axes[1].x, axes[1].y },
        .axis23 = (vector_float4){ axes[2].x, axes[2].y, axes[3].x, axes[3].y },
        .axis4 = (vector_float4){ axes[4].x, axes[4].y, 0, 0 },
    };
    return uniforms;
}

- (void)rotateNCubeVector:(const float *)vector time:(float)time output:(float *)output {
    memcpy(output, vector, sizeof(float) * OFNCubeDimension);

    for (int firstAxis = 0; firstAxis < OFNCubeDimension - 1; firstAxis++) {
        for (int secondAxis = firstAxis + 1; secondAxis < OFNCubeDimension; secondAxis++) {
            float speed = 0.16f + (float)((firstAxis * OFNCubeDimension + secondAxis) % 7) * 0.031f;
            float angle = time * speed + (float)(firstAxis + secondAxis) * 0.23f;
            float cosine = cosf(angle);
            float sine = sinf(angle);
            float firstValue = output[firstAxis];
            float secondValue = output[secondAxis];
            output[firstAxis] = firstValue * cosine - secondValue * sine;
            output[secondAxis] = firstValue * sine + secondValue * cosine;
        }
    }
}

@end
