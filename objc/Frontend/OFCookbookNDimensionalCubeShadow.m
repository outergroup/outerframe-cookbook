#import "OFCookbookController.h"

#import <Metal/Metal.h>

static void OFCookbookSetupMetalIfNeeded(OFCookbookPageContext *context);
static OFNCubeUniforms OFCookbookMakeNCubeUniformsAtTime(float time, CGSize drawable_size);
static void OFCookbookRotateNCubeVector(const float *vector, float time, float *output);
static void OFCookbookNCubeRenderFrame(OFCookbookPageContext *context);
static void OFCookbookNCubeEnterRoute(void *runtime);
static void OFCookbookNCubeLeaveRoute(void *runtime);
static void OFCookbookNCubeHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime);
static void OFCookbookNCubeDisplayLink(OFHost *host, double target_timestamp, void *context);
static void OFCookbookNCubeStartDisplayLink(OFCookbookPageContext *context);
static void OFCookbookNCubeStopDisplayLink(OFCookbookPageContext *context);

@interface OFCookbookNCubeState : NSObject
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property(nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property(nonatomic, strong) CAMetalLayer *metalLayer;
@property(nonatomic, strong) NSString *setupError;
@property(nonatomic, assign) CFTimeInterval animationStartTime;
@property(nonatomic, assign) OFUUID displayLinkID;
@property(nonatomic, assign) BOOL hasDisplayLink;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@end

@implementation OFCookbookNCubeState
- (instancetype)init {
    self = [super init];
    if (self) {
        _animationStartTime = CACurrentMediaTime();
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookNCubeState *> *OFCookbookNCubeStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookNCubeState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookNCubeState *OFCookbookNCubeStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookNCubeState *state = OFCookbookNCubeStates()[key];
    if (!state) {
        state = [OFCookbookNCubeState new];
        OFCookbookNCubeStates()[key] = state;
    }
    return state;
}

static OFCookbookNCubeState *OFCookbookNCubeStateForContext(OFCookbookPageContext *context) {
    return (__bridge OFCookbookNCubeState *)context->page_state;
}

static void OFCookbookNCubeApplyStateToContext(OFCookbookPageContext *context, OFCookbookNCubeState *state) {
    context->page_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

void OFCookbookRenderNCube(OFCookbookPageContext *context) {
    OFCookbookNCubeState *state = OFCookbookNCubeStateForContext(context);
    state.metalLayer = nil;
    OFCookbookSetupMetalIfNeeded(context);

    CGFloat contentInset = 24;
    CGFloat contentWidth = MIN(MAX(context->current_size.width - contentInset * 2, 280), 920);
    CGFloat contentX = MAX((context->current_size.width - contentWidth) * 0.5, contentInset);
    CGFloat availableHeight = MAX(context->current_size.height - 190, 260);
    CGFloat metalHeight = MIN(MAX(availableHeight, 260), 520);
    CGFloat metalY = 132;
    CALayer *panel = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 8);
    panel.frame = CGRectMake(contentX - 18, 34, contentWidth + 36, metalY + metalHeight + 32);
    [context->page_layer addSublayer:panel];
    OFCookbookAddText(context, @"N-Dimensional Cube Shadow", 22, NSFontWeightSemibold, NSColor.labelColor, CGRectMake(contentX, 56, contentWidth, 28));
    OFCookbookAddText(context, @"A 5D cube rotating in N-space, projected as translucent square faces.", 14, NSFontWeightRegular, NSColor.secondaryLabelColor, CGRectMake(contentX, 88, contentWidth, 36));

    CGRect canvas = CGRectMake(contentX, metalY, contentWidth, metalHeight);
    CALayer *metalContainer = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 6);
    metalContainer.frame = canvas;
    metalContainer.masksToBounds = YES;
    [context->page_layer addSublayer:metalContainer];

    if (state.device && state.commandQueue && state.pipelineState) {
        CAMetalLayer *metalLayer = [CAMetalLayer layer];
        metalLayer.device = state.device;
        metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        metalLayer.framebufferOnly = YES;
        metalLayer.contentsScale = NSScreen.mainScreen.backingScaleFactor ?: 2.0;
        metalLayer.presentsWithTransaction = NO;
        metalLayer.frame = metalContainer.bounds;
        CGFloat scale = metalLayer.contentsScale;
        metalLayer.drawableSize = CGSizeMake(MAX(metalLayer.bounds.size.width * scale, 1),
                                             MAX(metalLayer.bounds.size.height * scale, 1));
        [metalContainer addSublayer:metalLayer];
        state.metalLayer = metalLayer;
        OFCookbookRenderNCubeFrameAtTimestamp(context, CACurrentMediaTime());
    }

    if (state.setupError.length > 0) {
        CATextLayer *error = OFTextLayer(state.setupError, [NSFont systemFontOfSize:13 weight:NSFontWeightRegular], NSColor.systemRedColor, 13);
        error.frame = CGRectMake(contentX, CGRectGetMaxY(canvas) + 10, contentWidth, 36);
        [context->page_layer addSublayer:error];
    }
    OFCookbookAddAccessibilityLabel(context, @"Rotating 5D cube face projection", canvas, OFAccessibilityRoleImage);
}

static void OFCookbookSetupMetalIfNeeded(OFCookbookPageContext *context) {
    OFCookbookNCubeState *state = OFCookbookNCubeStateForContext(context);
    if (state.device || state.setupError.length > 0) {
        return;
    }

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        state.setupError = @"Metal is not available on this Mac.";
        return;
    }

    id<MTLCommandQueue> commandQueue = [device newCommandQueue];
    if (!commandQueue) {
        state.setupError = @"Could not create a Metal command queue.";
        return;
    }

    NSError *error = nil;
    id<MTLLibrary> library = [device newDefaultLibraryWithBundle:context->bundle error:&error];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"nDimensionalCubeShadowVertex"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"nDimensionalCubeShadowFragment"];
    if (!library || !vertexFunction || !fragmentFunction) {
        state.setupError = error.localizedDescription.length > 0 ? [NSString stringWithFormat:@"Could not build the Metal library: %@", error.localizedDescription] : @"Could not find the N-cube Metal shaders.";
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
        state.setupError = error.localizedDescription.length > 0 ? [NSString stringWithFormat:@"Could not build the Metal pipeline: %@", error.localizedDescription] : @"Could not build the Metal pipeline.";
        return;
    }

    state.device = device;
    state.commandQueue = commandQueue;
    state.pipelineState = pipelineState;
    state.setupError = nil;
}

void OFCookbookRenderNCubeFrameAtTimestamp(OFCookbookPageContext *context, CFTimeInterval targetTimestamp) {
    OFCookbookNCubeState *state = OFCookbookNCubeStateForContext(context);
    CAMetalLayer *metalLayer = state.metalLayer;
    if (!metalLayer || !state.commandQueue || !state.pipelineState ||
        metalLayer.drawableSize.width < 1 || metalLayer.drawableSize.height < 1) {
        return;
    }

    id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
    id<MTLCommandBuffer> commandBuffer = [state.commandQueue commandBuffer];
    if (!drawable || !commandBuffer) {
        return;
    }

    CFTimeInterval elapsed = MAX(targetTimestamp - state.animationStartTime, 0);
    OFNCubeUniforms uniforms = OFCookbookMakeNCubeUniformsAtTime((float)elapsed, metalLayer.drawableSize);

    MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    descriptor.colorAttachments[0].texture = drawable.texture;
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.96, 0.96, 0.94, 1.0);

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    if (!encoder) {
        return;
    }

    [encoder setRenderPipelineState:state.pipelineState];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

static OFNCubeUniforms OFCookbookMakeNCubeUniformsAtTime(float time, CGSize drawableSize) {
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
        OFCookbookRotateNCubeVector(basis, time, rotated);
        axes[axis] = (vector_float2){ rotated[0] * scaleX, rotated[1] * scaleY };
    }

    OFNCubeUniforms uniforms = {
        .axis01 = (vector_float4){ axes[0].x, axes[0].y, axes[1].x, axes[1].y },
        .axis23 = (vector_float4){ axes[2].x, axes[2].y, axes[3].x, axes[3].y },
        .axis4 = (vector_float4){ axes[4].x, axes[4].y, 0, 0 },
    };
    return uniforms;
}

static void OFCookbookRotateNCubeVector(const float *vector, float time, float *output) {
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

static void OFCookbookNCubeRenderFrame(OFCookbookPageContext *context) {
    OFCookbookRenderPageFrame(context, OFCookbookRenderNCube);
    OFCookbookNCubeStateForContext(context).pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, nil);
}

static void OFCookbookNCubeStartDisplayLink(OFCookbookPageContext *context) {
    if (!context->host || !context->runtime) {
        return;
    }
    OFCookbookNCubeState *state = OFCookbookNCubeStateForContext(context);
    if (state.hasDisplayLink) {
        return;
    }
    state.displayLinkID = OFHostRegisterDisplayLinkCallback(context->host, OFCookbookNCubeDisplayLink, context->runtime);
    state.hasDisplayLink = YES;
}

static void OFCookbookNCubeStopDisplayLink(OFCookbookPageContext *context) {
    if (!context->host || !context->runtime) {
        return;
    }
    OFCookbookNCubeState *state = OFCookbookNCubeStateForContext(context);
    if (!state.hasDisplayLink) {
        return;
    }
    OFHostStopDisplayLinkCallback(context->host, state.displayLinkID);
    state.hasDisplayLink = NO;
    state.displayLinkID = (OFUUID){0};
}

static bool OFCookbookNCubeHandleBrowserMessage(OFCookbookPageContext *context, const OFBrowserMessage *message) {
    switch (message->kind) {
        case OFBrowserMessageInitializeContent: {
            OFHostConfigureFromInitialize(context->host, &message->as.initialize);
            context->current_size = message->as.initialize.has_content_size ? message->as.initialize.content_size : CGSizeMake(800, 600);
            if (message->as.initialize.has_appearance_archive) {
                NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.initialize.appearance_archive.bytes
                                                     length:message->as.initialize.appearance_archive.length
                                               freeWhenDone:NO];
                NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
                context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            }
            OFCookbookNCubeRenderFrame(context);
            OFCookbookNCubeStartDisplayLink(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = message->as.resize;
            OFCookbookNCubeRenderFrame(context);
            OFCookbookNCubeStartDisplayLink(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.appearance.appearance_archive.bytes
                                                 length:message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookNCubeRenderFrame(context);
            OFCookbookNCubeStartDisplayLink(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookNCubeRenderFrame(context);
            OFCookbookNCubeStartDisplayLink(context);
            return true;
        }
        case OFBrowserMessageShutdown:
            OFCookbookRequestShutdown(context->runtime);
            return true;
        case OFBrowserMessageAccessibilitySnapshotRequest:
            OFCookbookSendDefaultAccessibilitySnapshotResponse(context, message->as.request.request_id);
            return true;
        case OFBrowserMessageCopySelectedPasteboardRequest:
            OFCookbookSendCopySelectedPasteboardResponse(context, message->as.request.request_id, nil);
            return true;
        default:
            return false;
    }
}

const OFCookbookPageHandler OFCookbookNCubeHandler = {
    .handle_message = OFCookbookNCubeHandleMessage,
    .enter_route = OFCookbookNCubeEnterRoute,
    .leave_route = OFCookbookNCubeLeaveRoute,
};

static void OFCookbookNCubeEnterRoute(void *runtime) {
    OFCookbookNCubeStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookNCubeState new];
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookNCubeState *state = OFCookbookNCubeStateForRuntime(runtime);
    OFCookbookNCubeApplyStateToContext(context, state);
    OFCookbookNCubeRenderFrame(context);
    OFCookbookNCubeStartDisplayLink(context);
}

static void OFCookbookNCubeLeaveRoute(void *runtime) {
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookNCubeState *state = OFCookbookNCubeStates()[key];
    OFCookbookNCubeApplyStateToContext(context, state);
    OFCookbookNCubeStopDisplayLink(context);
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    context->page_layer = nil;
    context->page_state = NULL;
    [OFCookbookNCubeStates() removeObjectForKey:key];
}

static void OFCookbookNCubeHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookNCubeState *state = OFCookbookNCubeStateForRuntime(runtime);
    OFCookbookNCubeApplyStateToContext(context, state);
    OFCookbookNCubeHandleBrowserMessage(context, message);
}


static void OFCookbookNCubeDisplayLink(OFHost *host, double target_timestamp, void *context) {
    (void)host;
    OFCookbookPageContext *page_context = OFCookbookGetPageContext(context);
    OFCookbookNCubeState *state = OFCookbookNCubeStateForRuntime(context);
    OFCookbookNCubeApplyStateToContext(page_context, state);
    OFCookbookRenderNCubeFrameAtTimestamp(page_context, target_timestamp);
}
