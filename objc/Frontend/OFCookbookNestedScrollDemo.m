#import "OFCookbookController.h"

static void OFCookbookNestedScrollDemoScrollEvent(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point);
static void OFCookbookNestedScrollDemoRenderFrame(OFCookbookPageContext *context);
static void OFCookbookNestedScrollDemoEnterRoute(void *runtime);
static void OFCookbookNestedScrollDemoLeaveRoute(void *runtime);
static void OFCookbookNestedScrollDemoHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime);

@interface OFCookbookNestedScrollDemoState : NSObject
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, assign) CGFloat innerScrollOffset;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSValue *> *hitFrames;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@end

@implementation OFCookbookNestedScrollDemoState
- (instancetype)init {
    self = [super init];
    if (self) {
        _hitFrames = [NSMutableArray array];
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookNestedScrollDemoState *> *OFCookbookNestedScrollDemoStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookNestedScrollDemoState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookNestedScrollDemoState *OFCookbookNestedScrollDemoStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookNestedScrollDemoState *state = OFCookbookNestedScrollDemoStates()[key];
    if (!state) {
        state = [OFCookbookNestedScrollDemoState new];
        OFCookbookNestedScrollDemoStates()[key] = state;
    }
    return state;
}

static OFCookbookNestedScrollDemoState *OFCookbookNestedScrollDemoStateForContext(OFCookbookPageContext *context) {
    return (__bridge OFCookbookNestedScrollDemoState *)context->page_state;
}

static void OFCookbookNestedScrollDemoApplyStateToContext(OFCookbookPageContext *context, OFCookbookNestedScrollDemoState *state) {
    context->page_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

void OFCookbookRenderNestedScrollDemo(OFCookbookPageContext *context) {
    OFCookbookNestedScrollDemoState *state = OFCookbookNestedScrollDemoStateForContext(context);
    [state.hitFrames removeAllObjects];

    CGFloat outerRowHeight = 44;
    CGFloat innerRowHeight = 26;
    CGFloat outerTopPadding = 56;
    CGFloat outerBottomPadding = 40;
    CGFloat innerSpacingAbove = 24;
    CGFloat innerSpacingBelow = 24;
    CGFloat innerViewportHeight = 200;
    NSInteger innerInsertionIndex = 6;
    CGFloat outerContentHeight = outerTopPadding + 24 * outerRowHeight + innerSpacingAbove + innerViewportHeight + innerSpacingBelow + outerBottomPadding;
    state.scrollOffset = OFClamp(state.scrollOffset, 0, MAX(0, outerContentHeight - context->current_size.height + 40));
    OFCookbookAddText(context,
                      @"Nested Scroll Demo (outer surface)",
                      20,
                      NSFontWeightSemibold,
                      NSColor.labelColor,
                      CGRectMake(24, outerTopPadding - 36 - state.scrollOffset, MAX(context->current_size.width - 48, 120), 28));

    CALayer *outerBackground = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 12);
    outerBackground.frame = CGRectMake(16, outerTopPadding - 12 - state.scrollOffset, MAX(context->current_size.width - 32, 120), outerContentHeight - outerTopPadding + 24);
    outerBackground.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.1].CGColor;
    outerBackground.shadowOpacity = 1;
    outerBackground.shadowRadius = 6;
    outerBackground.zPosition = -1;
    [context->page_layer addSublayer:outerBackground];

    CGFloat y = outerTopPadding - state.scrollOffset;
    for (NSInteger i = 0; i < 24; i++) {
        if (i == innerInsertionIndex) {
            y += innerSpacingAbove;
            CGRect innerFrame = CGRectMake(24, y, MAX(context->current_size.width - 48, 120), innerViewportHeight);
            CALayer *inner = OFRoundedLayer([NSColor.controlBackgroundColor colorWithAlphaComponent:0.9], [NSColor.systemBlueColor colorWithAlphaComponent:0.6], 10);
            inner.geometryFlipped = NO;
            inner.borderWidth = 2;
            inner.frame = innerFrame;
            inner.masksToBounds = YES;
            [context->page_layer addSublayer:inner];
            [state.hitFrames addObject:[NSValue valueWithRect:innerFrame]];

            CATextLayer *innerTitle = OFTextLayer(@"Nested inner surface", [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold], NSColor.systemBlueColor, 14);
            innerTitle.frame = CGRectMake(12, 12, MAX(innerFrame.size.width - 24, 60), 20);
            [inner addSublayer:innerTitle];

            CGFloat innerContentHeight = 36 * innerRowHeight + 12;
            state.innerScrollOffset = OFClamp(state.innerScrollOffset, 0, MAX(0, innerContentHeight - (innerViewportHeight - 32)));
            for (NSInteger innerIndex = 0; innerIndex < 36; innerIndex++) {
                CGFloat visualY = 32 + innerIndex * innerRowHeight - state.innerScrollOffset;
                NSString *text = [NSString stringWithFormat:@"Inner row %ld", (long)innerIndex + 1];
                CATextLayer *label = OFTextLayer(text, [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular], [NSColor.labelColor colorWithAlphaComponent:0.8], 13);
                label.frame = CGRectMake(12, visualY, MAX(innerFrame.size.width - 24, 60), innerRowHeight);
                [inner addSublayer:label];
            }
            OFCookbookAddAccessibilityLabel(context, @"Nested inner surface", innerFrame, OFAccessibilityRoleContainer);
            y += innerViewportHeight + innerSpacingBelow;
        }

        NSString *text = [NSString stringWithFormat:@"Outer row %ld", (long)i + 1];
        CATextLayer *label = OFTextLayer(text, [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], NSColor.labelColor, 16);
        label.frame = CGRectMake(24, y, MAX(context->current_size.width - 48, 120), outerRowHeight);
        [context->page_layer addSublayer:label];
        OFCookbookAddAccessibilityLabel(context, text, label.frame, OFAccessibilityRoleStaticText);
        y += outerRowHeight;
    }
    OFCookbookAddScrollbarForContentHeight(context, outerContentHeight, context->current_size.height, state.scrollOffset);
}

bool OFCookbookNestedScrollDemoScroll(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point) {
    OFCookbookNestedScrollDemoState *state = OFCookbookNestedScrollDemoStateForContext(context);
    for (NSValue *frameValue in state.hitFrames) {
        if (CGRectContainsPoint(frameValue.rectValue, point)) {
            state.innerScrollOffset = OFClamp(state.innerScrollOffset + adjusted_delta, 0, 900);
            return true;
        }
    }
    return false;
}

static void OFCookbookNestedScrollDemoScrollEvent(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point) {
    if (OFCookbookNestedScrollDemoScroll(context, adjusted_delta, point)) {
        OFCookbookNestedScrollDemoRenderFrame(context);
        return;
    }
    OFCookbookNestedScrollDemoState *state = OFCookbookNestedScrollDemoStateForContext(context);
    state.scrollOffset = MAX(0, state.scrollOffset + adjusted_delta);
    OFCookbookNestedScrollDemoRenderFrame(context);
}

static void OFCookbookNestedScrollDemoRenderFrame(OFCookbookPageContext *context) {
    OFCookbookRenderPageFrame(context, OFCookbookRenderNestedScrollDemo);
    OFCookbookNestedScrollDemoStateForContext(context).pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, nil);
}

static bool OFCookbookNestedScrollDemoHandleBrowserMessage(OFCookbookPageContext *context, const OFBrowserMessage *message) {
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
            OFCookbookNestedScrollDemoRenderFrame(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = message->as.resize;
            OFCookbookNestedScrollDemoRenderFrame(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.appearance.appearance_archive.bytes
                                                 length:message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookNestedScrollDemoRenderFrame(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookNestedScrollDemoRenderFrame(context);
            return true;
        }
        case OFBrowserMessageShutdown:
            OFCookbookRequestShutdown(context->runtime);
            return true;
        case OFBrowserMessageAccessibilitySnapshotRequest:
            OFCookbookSendDefaultAccessibilitySnapshotResponse(context, message->as.request.request_id);
            return true;
        case OFBrowserMessageSelectionToPasteboardCopyRequest:
            OFCookbookSendCopySelectedPasteboardResponse(context, message->as.request.request_id, nil);
            return true;
        case OFBrowserMessageSelectionToPasteboardCutRequest:
            OFCookbookSendCopySelectedPasteboardResponse(context, message->as.request.request_id, nil);
            return true;
        case OFBrowserMessageEditCommandValidationRequest:
            OFCookbookSendEditCommandValidationResponse(context, message->as.edit_validation.request_id, message->as.edit_validation.commands, nil);
            return true;
        case OFBrowserMessageScrollWheelEvent:
            OFCookbookNestedScrollDemoScrollEvent(context,
                                                  -message->as.scroll.delta_y,
                                                  OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.scroll.x, message->as.scroll.y)));
            return true;
        default:
            return false;
    }
}

const OFCookbookPageHandler OFCookbookNestedScrollDemoHandler = {
    .handle_message = OFCookbookNestedScrollDemoHandleMessage,
    .enter_route = OFCookbookNestedScrollDemoEnterRoute,
    .leave_route = OFCookbookNestedScrollDemoLeaveRoute,
};

static void OFCookbookNestedScrollDemoEnterRoute(void *runtime) {
    OFCookbookNestedScrollDemoStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookNestedScrollDemoState new];
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookNestedScrollDemoState *state = OFCookbookNestedScrollDemoStateForRuntime(runtime);
    OFCookbookNestedScrollDemoApplyStateToContext(context, state);
    OFCookbookNestedScrollDemoRenderFrame(context);
}

static void OFCookbookNestedScrollDemoLeaveRoute(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookNestedScrollDemoState *state = OFCookbookNestedScrollDemoStates()[key];
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    context->page_layer = nil;
    context->page_state = NULL;
    [OFCookbookNestedScrollDemoStates() removeObjectForKey:key];
}

static void OFCookbookNestedScrollDemoHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookNestedScrollDemoState *state = OFCookbookNestedScrollDemoStateForRuntime(runtime);
    OFCookbookNestedScrollDemoApplyStateToContext(context, state);
    OFCookbookNestedScrollDemoHandleBrowserMessage(context, message);
}
