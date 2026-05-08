#import "OFCookbookController.h"

static void OFCookbookManualScrollViewScroll(OFCookbookRecipeContext *context, CGFloat adjusted_delta, CGPoint point);
static void OFCookbookManualScrollViewRenderFrame(OFCookbookRecipeContext *context);
static void OFCookbookManualScrollViewEnterRoute(void *runtime);
static void OFCookbookManualScrollViewLeaveRoute(void *runtime);
static void OFCookbookManualScrollViewHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime);

@interface OFCookbookManualScrollViewState : NSObject
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@end

@implementation OFCookbookManualScrollViewState
- (instancetype)init {
    self = [super init];
    if (self) {
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookManualScrollViewState *> *OFCookbookManualScrollViewStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookManualScrollViewState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookManualScrollViewState *OFCookbookManualScrollViewStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookManualScrollViewState *state = OFCookbookManualScrollViewStates()[key];
    if (!state) {
        state = [OFCookbookManualScrollViewState new];
        OFCookbookManualScrollViewStates()[key] = state;
    }
    return state;
}

static OFCookbookManualScrollViewState *OFCookbookManualScrollViewStateForContext(OFCookbookRecipeContext *context) {
    return (__bridge OFCookbookManualScrollViewState *)context->recipe_state;
}

static void OFCookbookManualScrollViewApplyStateToContext(OFCookbookRecipeContext *context, OFCookbookManualScrollViewState *state) {
    context->recipe_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

void OFCookbookRenderManualScrollView(OFCookbookRecipeContext *context) {
    OFCookbookManualScrollViewState *state = OFCookbookManualScrollViewStateForContext(context);
    CGFloat rowHeight = 44;
    CGFloat topPadding = 72;
    CGFloat bottomPadding = 48;
    CGFloat horizontalPadding = 24;
    CGFloat backgroundInset = 16;
    CGFloat contentHeight = topPadding + 60 * rowHeight + bottomPadding;
    state.scrollOffset = OFClamp(state.scrollOffset, 0, MAX(0, contentHeight - context->current_size.height));

    CGFloat rowWidth = MAX(context->current_size.width - horizontalPadding * 2, 120);
    CGFloat backgroundWidth = MAX(context->current_size.width - backgroundInset * 2, 120);
    CALayer *background = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 12);
    background.frame = CGRectMake(backgroundInset, topPadding - 16 - state.scrollOffset, backgroundWidth, contentHeight - topPadding + 32);
    background.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.08].CGColor;
    background.shadowOpacity = 1;
    background.shadowRadius = 6;
    [context->page_layer addSublayer:background];

    OFCookbookAddText(context,
                      @"Manual Scroll View",
                      20,
                      NSFontWeightSemibold,
                      NSColor.labelColor,
                      CGRectMake(horizontalPadding, topPadding - 48 - state.scrollOffset, rowWidth, 28));
    OFCookbookAddText(context,
                      @"This view scrolls entirely inside the outerframe layer tree.",
                      14,
                      NSFontWeightRegular,
                      NSColor.secondaryLabelColor,
                      CGRectMake(horizontalPadding, topPadding - 22 - state.scrollOffset, rowWidth, 40));

    CGFloat y = topPadding - state.scrollOffset;
    for (NSInteger i = 0; i < 60; i++) {
        NSString *title = [NSString stringWithFormat:@"Manual scroll row %ld", (long)i + 1];
        NSColor *color = i % 2 == 1 ? [NSColor.labelColor colorWithAlphaComponent:0.8] : NSColor.labelColor;
        CATextLayer *label = OFTextLayer(title, [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], color, 16);
        label.frame = CGRectMake(horizontalPadding, y, rowWidth, rowHeight);
        [context->page_layer addSublayer:label];
        OFCookbookAddAccessibilityLabel(context, title, label.frame, OFAccessibilityRoleStaticText);
        y += rowHeight;
    }
    OFCookbookAddScrollbarForContentHeight(context, contentHeight, context->current_size.height, state.scrollOffset);
}

static void OFCookbookManualScrollViewScroll(OFCookbookRecipeContext *context, CGFloat adjusted_delta, CGPoint point) {
    (void)point;
    OFCookbookManualScrollViewState *state = OFCookbookManualScrollViewStateForContext(context);
    state.scrollOffset = MAX(0, state.scrollOffset + adjusted_delta);
    OFCookbookRenderRecipeFrame(context, OFCookbookRenderManualScrollView);
    state.pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, nil);
}

static void OFCookbookManualScrollViewRenderFrame(OFCookbookRecipeContext *context) {
    OFCookbookRenderRecipeFrame(context, OFCookbookRenderManualScrollView);
    OFCookbookManualScrollViewStateForContext(context).pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, nil);
}

static bool OFCookbookManualScrollViewHandleBrowserMessage(OFCookbookRecipeContext *context, const OFBrowserMessage *message) {
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
            OFCookbookManualScrollViewRenderFrame(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = message->as.resize;
            OFCookbookManualScrollViewRenderFrame(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.appearance.appearance_archive.bytes
                                                 length:message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookManualScrollViewRenderFrame(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookManualScrollViewRenderFrame(context);
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
        case OFBrowserMessageScrollWheelEvent:
            OFCookbookManualScrollViewScroll(context,
                                             -message->as.scroll.delta_y,
                                             OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.scroll.x, message->as.scroll.y)));
            return true;
        default:
            return false;
    }
}

const OFCookbookRecipeHandler OFCookbookManualScrollViewHandler = {
    .handle_message = OFCookbookManualScrollViewHandleMessage,
    .enter_route = OFCookbookManualScrollViewEnterRoute,
    .leave_route = OFCookbookManualScrollViewLeaveRoute,
};

static void OFCookbookManualScrollViewEnterRoute(void *runtime) {
    OFCookbookManualScrollViewStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookManualScrollViewState new];
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    OFCookbookManualScrollViewState *state = OFCookbookManualScrollViewStateForRuntime(runtime);
    OFCookbookManualScrollViewApplyStateToContext(context, state);
    OFCookbookManualScrollViewRenderFrame(context);
}

static void OFCookbookManualScrollViewLeaveRoute(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookManualScrollViewState *state = OFCookbookManualScrollViewStates()[key];
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    context->page_layer = nil;
    context->recipe_state = NULL;
    [OFCookbookManualScrollViewStates() removeObjectForKey:key];
}

static void OFCookbookManualScrollViewHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    OFCookbookManualScrollViewState *state = OFCookbookManualScrollViewStateForRuntime(runtime);
    OFCookbookManualScrollViewApplyStateToContext(context, state);
    OFCookbookManualScrollViewHandleBrowserMessage(context, message);
}
