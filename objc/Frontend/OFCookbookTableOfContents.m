#import "OFCookbookController.h"

static void OFCookbookTableOfContentsMouseMoved(OFCookbookPageContext *context, CGPoint point);
static void OFCookbookTableOfContentsMouseDown(OFCookbookPageContext *context, CGPoint point, uint32_t click_count);
static void OFCookbookTableOfContentsScroll(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point);
static void OFCookbookTableOfContentsEnterRoute(void *runtime);
static void OFCookbookTableOfContentsLeaveRoute(void *runtime);
static void OFCookbookTableOfContentsHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime);

@interface OFCookbookTableOfContentsState : NSObject
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSValue *> *hitFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *hitRoutes;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@end

@implementation OFCookbookTableOfContentsState
- (instancetype)init {
    self = [super init];
    if (self) {
        _hitFrames = [NSMutableArray array];
        _hitRoutes = [NSMutableArray array];
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookTableOfContentsState *> *OFCookbookTableOfContentsStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookTableOfContentsState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookTableOfContentsState *OFCookbookTableOfContentsStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStates()[key];
    if (!state) {
        state = [OFCookbookTableOfContentsState new];
        OFCookbookTableOfContentsStates()[key] = state;
    }
    return state;
}

static OFCookbookTableOfContentsState *OFCookbookTableOfContentsStateForContext(OFCookbookPageContext *context) {
    return (__bridge OFCookbookTableOfContentsState *)context->page_state;
}

static void OFCookbookTableOfContentsApplyStateToContext(OFCookbookPageContext *context, OFCookbookTableOfContentsState *state) {
    context->page_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

void OFCookbookRenderTableOfContents(OFCookbookPageContext *context) {
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStateForContext(context);
    [state.hitFrames removeAllObjects];
    [state.hitRoutes removeAllObjects];

    CGFloat contentWidth = MIN(MAX(context->current_size.width - 48, 280), 760);
    CGFloat contentX = MAX((context->current_size.width - contentWidth) * 0.5, 24);
    CGFloat top = 56;
    CGFloat rowHeight = 78;
    CGFloat rowGap = 12;
    CGFloat bottomPadding = 56;
    CGFloat contentHeight = top + 46 + 24 + 28 + OFCookbookPageCount * rowHeight + (OFCookbookPageCount - 1) * rowGap + bottomPadding;
    state.scrollOffset = OFClamp(state.scrollOffset, 0, MAX(0, contentHeight - context->current_size.height));

    OFCookbookAddText(context,
                      @"Outerframe Cookbook",
                      30,
                      NSFontWeightSemibold,
                      NSColor.labelColor,
                      CGRectMake(contentX, top - state.scrollOffset, contentWidth, 38));
    OFCookbookAddText(context,
                      @"Pick a page:",
                      15,
                      NSFontWeightRegular,
                      NSColor.secondaryLabelColor,
                      CGRectMake(contentX, top + 46 - state.scrollOffset, contentWidth, 24));

    CGFloat y = top + 46 + 24 + 28 - state.scrollOffset;
    for (NSInteger i = 0; i < OFCookbookPageCount; i++) {
        OFCookbookRoute route = OFCookbookRouteAtIndex(i);
        CGRect rowFrame = CGRectMake(contentX, y, contentWidth, rowHeight);
        CALayer *row = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 8);
        row.frame = rowFrame;
        [context->page_layer addSublayer:row];

        CATextLayer *title = OFTextLayer(OFCookbookRouteTitle(route), [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold], NSColor.labelColor, 17);
        title.frame = CGRectMake(18, 13, MAX(contentWidth - 72, 120), 24);
        [row addSublayer:title];

        CATextLayer *description = OFTextLayer(OFCookbookRouteDescription(route), [NSFont systemFontOfSize:13 weight:NSFontWeightRegular], NSColor.secondaryLabelColor, 13);
        description.frame = CGRectMake(18, 39, MAX(contentWidth - 72, 120), 34);
        [row addSublayer:description];

        CATextLayer *arrow = OFTextLayer(@">", [NSFont systemFontOfSize:20 weight:NSFontWeightMedium], NSColor.tertiaryLabelColor, 20);
        arrow.alignmentMode = kCAAlignmentRight;
        arrow.frame = CGRectMake(contentWidth - 46, 25, 24, 28);
        [row addSublayer:arrow];

        [state.hitFrames addObject:[NSValue valueWithRect:rowFrame]];
        [state.hitRoutes addObject:@(route)];
        OFCookbookAddAccessibilityLabel(context, OFCookbookRouteTitle(route), rowFrame, OFAccessibilityRoleButton);
        y += rowHeight + rowGap;
    }

    OFCookbookAddScrollbarForContentHeight(context, MAX(contentHeight, context->current_size.height), context->current_size.height, state.scrollOffset);
}

static void OFCookbookTableOfContentsMouseMoved(OFCookbookPageContext *context, CGPoint point) {
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStateForContext(context);
    OFCursorType cursor = OFCursorTypeArrow;
    for (NSValue *frameValue in state.hitFrames) {
        if (CGRectContainsPoint(frameValue.rectValue, point)) {
            cursor = OFCursorTypePointingHand;
            break;
        }
    }
    OFHostSetCursor(context->host, cursor);
}

static void OFCookbookTableOfContentsMouseDown(OFCookbookPageContext *context, CGPoint point, uint32_t click_count) {
    (void)click_count;
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStateForContext(context);
    for (NSUInteger i = 0; i < state.hitFrames.count; i++) {
        if (CGRectContainsPoint(state.hitFrames[i].rectValue, point)) {
            OFHostSetCursor(context->host, OFCursorTypeArrow);
            OFCookbookNavigateToRoute(context, state.hitRoutes[i].integerValue);
            return;
        }
    }
}

static void OFCookbookTableOfContentsRenderFrame(OFCookbookPageContext *context) {
    OFCookbookRenderPageFrame(context, OFCookbookRenderTableOfContents);
    OFCookbookTableOfContentsStateForContext(context).pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, nil);
}

static void OFCookbookTableOfContentsScroll(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point) {
    (void)point;
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStateForContext(context);
    state.scrollOffset = MAX(0, state.scrollOffset + adjusted_delta);
    OFCookbookTableOfContentsRenderFrame(context);
}

static bool OFCookbookTableOfContentsHandleBrowserMessage(OFCookbookPageContext *context, const OFBrowserMessage *message) {
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
            OFCookbookTableOfContentsRenderFrame(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = message->as.resize;
            OFCookbookTableOfContentsRenderFrame(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.appearance.appearance_archive.bytes
                                                 length:message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookTableOfContentsRenderFrame(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookTableOfContentsRenderFrame(context);
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
        case OFBrowserMessageMouseMoved:
            OFCookbookTableOfContentsMouseMoved(context,
                                                OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.mouse.x, message->as.mouse.y)));
            return true;
        case OFBrowserMessageMouseDown:
            OFCookbookTableOfContentsMouseDown(context,
                                               OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.mouse.x, message->as.mouse.y)),
                                               message->as.mouse.click_count);
            return true;
        case OFBrowserMessageScrollWheelEvent:
            OFCookbookTableOfContentsScroll(context,
                                            -message->as.scroll.delta_y,
                                            OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.scroll.x, message->as.scroll.y)));
            return true;
        default:
            return false;
    }
}

const OFCookbookPageHandler OFCookbookTableOfContentsHandler = {
    .handle_message = OFCookbookTableOfContentsHandleMessage,
    .enter_route = OFCookbookTableOfContentsEnterRoute,
    .leave_route = OFCookbookTableOfContentsLeaveRoute,
};

static void OFCookbookTableOfContentsEnterRoute(void *runtime) {
    OFCookbookTableOfContentsStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookTableOfContentsState new];
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStateForRuntime(runtime);
    OFCookbookTableOfContentsApplyStateToContext(context, state);
    OFCookbookTableOfContentsRenderFrame(context);
}

static void OFCookbookTableOfContentsLeaveRoute(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStates()[key];
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    context->page_layer = nil;
    context->page_state = NULL;
    [OFCookbookTableOfContentsStates() removeObjectForKey:key];
}

static void OFCookbookTableOfContentsHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookTableOfContentsState *state = OFCookbookTableOfContentsStateForRuntime(runtime);
    OFCookbookTableOfContentsApplyStateToContext(context, state);
    OFCookbookTableOfContentsHandleBrowserMessage(context, message);
}
