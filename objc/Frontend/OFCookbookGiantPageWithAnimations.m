#import "OFCookbookController.h"

static void OFCookbookGiantPageWithAnimationsScroll(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point);
static void OFCookbookGiantPageWithAnimationsRenderFrame(OFCookbookPageContext *context);
static void OFCookbookGiantPageWithAnimationsEnterRoute(void *runtime);
static void OFCookbookGiantPageWithAnimationsLeaveRoute(void *runtime);
static void OFCookbookGiantPageWithAnimationsHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime);

@interface OFCookbookGiantPageWithAnimationsState : NSObject
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, assign) CFTimeInterval animationBaseTime;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@end

@implementation OFCookbookGiantPageWithAnimationsState
- (instancetype)init {
    self = [super init];
    if (self) {
        _animationBaseTime = CACurrentMediaTime();
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookGiantPageWithAnimationsState *> *OFCookbookGiantPageWithAnimationsStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookGiantPageWithAnimationsState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookGiantPageWithAnimationsState *OFCookbookGiantPageWithAnimationsStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookGiantPageWithAnimationsState *state = OFCookbookGiantPageWithAnimationsStates()[key];
    if (!state) {
        state = [OFCookbookGiantPageWithAnimationsState new];
        OFCookbookGiantPageWithAnimationsStates()[key] = state;
    }
    return state;
}

static OFCookbookGiantPageWithAnimationsState *OFCookbookGiantPageWithAnimationsStateForContext(OFCookbookPageContext *context) {
    return (__bridge OFCookbookGiantPageWithAnimationsState *)context->page_state;
}

static void OFCookbookGiantPageWithAnimationsApplyStateToContext(OFCookbookPageContext *context, OFCookbookGiantPageWithAnimationsState *state) {
    context->page_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

void OFCookbookRenderGiantPageWithAnimations(OFCookbookPageContext *context) {
    OFCookbookGiantPageWithAnimationsState *state = OFCookbookGiantPageWithAnimationsStateForContext(context);
    NSInteger itemCount = 420;
    CGFloat rowHeight = 80;
    CGFloat topPadding = 96;
    CGFloat bottomPadding = 96;
    CGFloat horizontalPadding = 24;
    CGFloat backgroundInset = 14;
    CGFloat rowWidth = MAX(MIN(context->current_size.width * 0.55, MAX(context->current_size.width - horizontalPadding * 2, 200)), 220);
    CGFloat containerX = MAX((context->current_size.width - rowWidth) * 0.5, backgroundInset);
    CGFloat titleY = topPadding - 28;
    CGFloat subtitleY = titleY + 28 + 12;
    CGFloat rowsStartY = subtitleY + 72 + 24;
    CGFloat contentHeight = rowsStartY + itemCount * rowHeight + bottomPadding;
    state.scrollOffset = OFClamp(state.scrollOffset, 0, MAX(0, contentHeight - context->current_size.height));

    CALayer *background = OFRoundedLayer([NSColor.textBackgroundColor colorWithAlphaComponent:0.9], NSColor.separatorColor, 12);
    background.frame = CGRectMake(MAX(containerX - backgroundInset, 0),
                                  MIN(titleY, subtitleY) - 24 - state.scrollOffset,
                                  MAX(rowWidth + backgroundInset * 2, 120),
                                  contentHeight - (MIN(titleY, subtitleY) - 24) + 24);
    background.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.1].CGColor;
    background.shadowOpacity = 1;
    background.shadowRadius = 7;
    [context->page_layer addSublayer:background];

    OFCookbookAddText(context,
                      @"Giant page with animations",
                      20,
                      NSFontWeightSemibold,
                      NSColor.labelColor,
                      CGRectMake(containerX, titleY - state.scrollOffset, rowWidth, 28));
    OFCookbookAddText(context,
                      @"Layers only exist while visible. Animations continue in sync even when created mid-scroll. The animation runs inside WindowServer, not this OuterContent process.",
                      14,
                      NSFontWeightRegular,
                      NSColor.secondaryLabelColor,
                      CGRectMake(containerX, subtitleY - state.scrollOffset, rowWidth, 72));

    CGFloat visibleStart = MAX(state.scrollOffset - 220, 0);
    CGFloat visibleEnd = MIN(state.scrollOffset + context->current_size.height + 220, contentHeight);
    NSInteger firstIndex = MAX((NSInteger)floor((visibleStart - rowsStartY) / rowHeight), 0);
    NSInteger lastIndex = MIN((NSInteger)ceil((visibleEnd - rowsStartY) / rowHeight), itemCount - 1);
    for (NSInteger i = firstIndex; i <= lastIndex; i++) {
        CGFloat y = rowsStartY + i * rowHeight - state.scrollOffset;
        CGRect frame = CGRectMake(containerX, y, rowWidth, rowHeight);
        CALayer *cell = OFRoundedLayer([NSColor.textBackgroundColor colorWithAlphaComponent:0.92], NSColor.separatorColor, 14);
        cell.frame = frame;
        cell.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.08].CGColor;
        cell.shadowOpacity = 1;
        cell.shadowRadius = 6;
        [context->page_layer addSublayer:cell];

        CGFloat shapeWidth = 28;
        CGFloat shapeHeight = 48;
        CGFloat minCenter = 20 + shapeWidth * 0.5;
        CGFloat maxCenter = rowWidth - 20 - shapeWidth * 0.5;
        CGFloat center = OFClamp(rowWidth * 0.5, minCenter, maxCenter);
        CGFloat amplitude = MIN(MIN(240 * 0.5, rowWidth * 0.25), MAX(MIN(center - minCenter, maxCenter - center), 0));
        CALayer *dot = [CALayer layer];
        dot.bounds = CGRectMake(0, 0, shapeWidth, shapeHeight);
        dot.position = CGPointMake(center - amplitude, rowHeight * 0.5);
        dot.cornerRadius = MIN(shapeWidth, shapeHeight) * 0.35;
        NSColor *color = [NSColor colorWithCalibratedHue:(CGFloat)(i % 48) / 48.0 saturation:0.6 brightness:0.9 alpha:1];
        dot.backgroundColor = color.CGColor;
        dot.shadowColor = [color colorWithAlphaComponent:0.85].CGColor;
        dot.shadowOpacity = 1;
        dot.shadowRadius = 5;
        [cell addSublayer:dot];

        CABasicAnimation *travel = [CABasicAnimation animationWithKeyPath:@"position.x"];
        travel.fromValue = @(center - amplitude);
        travel.toValue = @(center + amplitude);
        travel.autoreverses = YES;
        travel.duration = 1.0;
        travel.repeatCount = HUGE_VALF;
        travel.beginTime = [dot convertTime:state.animationBaseTime fromLayer:nil];
        travel.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        travel.removedOnCompletion = NO;
        travel.fillMode = kCAFillModeBoth;
        [dot addAnimation:travel forKey:@"dot-travel"];

        NSString *labelText = [NSString stringWithFormat:@"Moving dot %ld", (long)i + 1];
        if (CGRectIntersectsRect(frame, context->page_layer.bounds)) {
            OFCookbookAddAccessibilityLabel(context, labelText, frame, OFAccessibilityRoleStaticText);
        }
    }
    OFCookbookAddScrollbarForContentHeight(context, contentHeight, context->current_size.height, state.scrollOffset);
}

static void OFCookbookGiantPageWithAnimationsScroll(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point) {
    (void)point;
    OFCookbookGiantPageWithAnimationsState *state = OFCookbookGiantPageWithAnimationsStateForContext(context);
    state.scrollOffset = MAX(0, state.scrollOffset + adjusted_delta);
    OFCookbookGiantPageWithAnimationsRenderFrame(context);
}

static void OFCookbookGiantPageWithAnimationsRenderFrame(OFCookbookPageContext *context) {
    OFCookbookRenderPageFrame(context, OFCookbookRenderGiantPageWithAnimations);
    OFCookbookGiantPageWithAnimationsStateForContext(context).pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, nil);
}

static bool OFCookbookGiantPageWithAnimationsHandleBrowserMessage(OFCookbookPageContext *context, const OFBrowserMessage *message) {
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
            OFCookbookGiantPageWithAnimationsRenderFrame(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = message->as.resize;
            OFCookbookGiantPageWithAnimationsRenderFrame(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.appearance.appearance_archive.bytes
                                                 length:message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookGiantPageWithAnimationsRenderFrame(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookGiantPageWithAnimationsRenderFrame(context);
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
            OFCookbookGiantPageWithAnimationsScroll(context,
                                                    -message->as.scroll.delta_y,
                                                    OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.scroll.x, message->as.scroll.y)));
            return true;
        default:
            return false;
    }
}

const OFCookbookPageHandler OFCookbookGiantPageWithAnimationsHandler = {
    .handle_message = OFCookbookGiantPageWithAnimationsHandleMessage,
    .enter_route = OFCookbookGiantPageWithAnimationsEnterRoute,
    .leave_route = OFCookbookGiantPageWithAnimationsLeaveRoute,
};

static void OFCookbookGiantPageWithAnimationsEnterRoute(void *runtime) {
    OFCookbookGiantPageWithAnimationsStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookGiantPageWithAnimationsState new];
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookGiantPageWithAnimationsState *state = OFCookbookGiantPageWithAnimationsStateForRuntime(runtime);
    OFCookbookGiantPageWithAnimationsApplyStateToContext(context, state);
    OFCookbookGiantPageWithAnimationsRenderFrame(context);
}

static void OFCookbookGiantPageWithAnimationsLeaveRoute(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookGiantPageWithAnimationsState *state = OFCookbookGiantPageWithAnimationsStates()[key];
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    context->page_layer = nil;
    context->page_state = NULL;
    [OFCookbookGiantPageWithAnimationsStates() removeObjectForKey:key];
}

static void OFCookbookGiantPageWithAnimationsHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookGiantPageWithAnimationsState *state = OFCookbookGiantPageWithAnimationsStateForRuntime(runtime);
    OFCookbookGiantPageWithAnimationsApplyStateToContext(context, state);
    OFCookbookGiantPageWithAnimationsHandleBrowserMessage(context, message);
}
