#import "OFCookbookController.h"

static const CGFloat OFTimelineChartHeight = 240;
static const CGFloat OFTimelineChartTopOffset = 210;
static const CGFloat OFTimelineChartHorizontalInset = 40;
static const CGFloat OFTimelineChartBottomInset = 64;
static const CGFloat OFTimelineHandleHitWidth = 16;
static const CGFloat OFTimelineDomainEnd = 12;

static CGRect OFTimelineCardFrame(CGSize currentSize) {
    CGFloat cardWidth = MAX(currentSize.width - 64, 420);
    CGFloat cardHeight = MAX(currentSize.height - 64, OFTimelineChartHeight + OFTimelineChartTopOffset + OFTimelineChartBottomInset);
    return CGRectMake(MAX(32, (currentSize.width - cardWidth) / 2), 32, cardWidth, cardHeight);
}

static CGRect OFTimelineChartFrame(CGSize currentSize) {
    CGRect cardFrame = OFTimelineCardFrame(currentSize);
    return CGRectMake(cardFrame.origin.x + OFTimelineChartHorizontalInset,
                      cardFrame.origin.y + OFTimelineChartTopOffset,
                      cardFrame.size.width - OFTimelineChartHorizontalInset * 2,
                      OFTimelineChartHeight);
}

static void OFCookbookTimelineRangeSelectorMouseMoved(OFCookbookRecipeContext *context, CGPoint point);
static void OFCookbookTimelineRangeSelectorMouseDown(OFCookbookRecipeContext *context, CGPoint point, uint32_t click_count);
static void OFCookbookTimelineRangeSelectorMouseDragged(OFCookbookRecipeContext *context, CGPoint point);
static void OFCookbookTimelineRangeSelectorMouseUp(OFCookbookRecipeContext *context, CGPoint point);
static void OFCookbookTimelineRangeSelectorRenderFrame(OFCookbookRecipeContext *context);
static void OFCookbookTimelineRangeSelectorEnterRoute(void *runtime);
static void OFCookbookTimelineRangeSelectorLeaveRoute(void *runtime);
static void OFCookbookTimelineRangeSelectorHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime);

@interface OFCookbookTimelineRangeSelectorState : NSObject
@property(nonatomic, assign) CGFloat start;
@property(nonatomic, assign) CGFloat end;
@property(nonatomic, assign) NSInteger dragOperation;
@property(nonatomic, assign) CGFloat dragAnchor;
@property(nonatomic, assign) BOOL creationDidMove;
@property(nonatomic, assign) BOOL hasSelection;
@property(nonatomic, assign) BOOL hasHover;
@property(nonatomic, assign) CGFloat hoverFraction;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@end

@implementation OFCookbookTimelineRangeSelectorState
- (instancetype)init {
    self = [super init];
    if (self) {
        _start = 0.24;
        _end = 0.72;
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookTimelineRangeSelectorState *> *OFCookbookTimelineRangeSelectorStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookTimelineRangeSelectorState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookTimelineRangeSelectorState *OFCookbookTimelineRangeSelectorStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStates()[key];
    if (!state) {
        state = [OFCookbookTimelineRangeSelectorState new];
        OFCookbookTimelineRangeSelectorStates()[key] = state;
    }
    return state;
}

static OFCookbookTimelineRangeSelectorState *OFCookbookTimelineRangeSelectorStateForContext(OFCookbookRecipeContext *context) {
    return (__bridge OFCookbookTimelineRangeSelectorState *)context->recipe_state;
}

static void OFCookbookTimelineRangeSelectorApplyStateToContext(OFCookbookRecipeContext *context, OFCookbookTimelineRangeSelectorState *state) {
    context->recipe_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

static CGFloat OFTimelineFunctionValueAt(CGFloat x) {
    return sin(x * 0.9) + 0.35 * sin(x * 2.1 + 0.7) + 0.2 * cos(x * 3.7) + 2.0;
}

static CGFloat OFTimelineIntegralFrom(CGFloat start, CGFloat end) {
    if (end <= start) return 0;
    NSInteger steps = 512;
    CGFloat delta = (end - start) / (CGFloat)steps;
    CGFloat sum = 0;
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat x = start + (CGFloat)i * delta;
        CGFloat weight = (i == 0 || i == steps) ? 0.5 : 1;
        sum += weight * OFTimelineFunctionValueAt(x);
    }
    return sum * delta;
}

void OFCookbookRenderTimelineRangeSelector(OFCookbookRecipeContext *context) {
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStateForContext(context);
    CGRect cardFrame = OFTimelineCardFrame(context->current_size);
    CALayer *card = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 14);
    card.frame = cardFrame;
    card.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.08].CGColor;
    card.shadowOpacity = 1;
    card.shadowRadius = 8;
    [context->page_layer addSublayer:card];

    OFCookbookAddText(context, @"Timeline Range Selector", 22, NSFontWeightSemibold, NSColor.labelColor, CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 32, cardFrame.size.width - 64, 28));
    OFCookbookAddText(context, @"Click and drag to choose a range. Adjust a handle to refine.", 14, NSFontWeightRegular, NSColor.secondaryLabelColor, CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 64, cardFrame.size.width - 64, 42));
    OFCookbookAddText(context, @"Integral of f(x) over selection", 12, NSFontWeightRegular, NSColor.tertiaryLabelColor, CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 110, cardFrame.size.width - 64, 18));

    NSString *valueText = @"Select a range";
    NSString *rangeText = @"Click and drag over the curve";
    if (state.hasSelection) {
        CGFloat start = OFTimelineDomainEnd * state.start;
        CGFloat end = OFTimelineDomainEnd * state.end;
        CGFloat integral = OFTimelineIntegralFrom(start, end);
        valueText = [NSString stringWithFormat:@"∫ = %.2f", integral];
        rangeText = [NSString stringWithFormat:@"Range: %.2f → %.2f", start, end];
    }

    CATextLayer *valueLayer = OFTextLayer(valueText, [NSFont monospacedDigitSystemFontOfSize:28 weight:NSFontWeightSemibold], NSColor.labelColor, 28);
    valueLayer.frame = CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 130, cardFrame.size.width - 64, 36);
    [context->page_layer addSublayer:valueLayer];
    OFCookbookAddAccessibilityLabel(context, valueText, valueLayer.frame, OFAccessibilityRoleStaticText);
    OFCookbookAddText(context, rangeText, 13, NSFontWeightMedium, NSColor.secondaryLabelColor, CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 172, cardFrame.size.width - 64, 20));

    CGRect chart = OFTimelineChartFrame(context->current_size);
    CALayer *chartLayer = [CALayer layer];
    chartLayer.geometryFlipped = YES;
    chartLayer.frame = chart;
    chartLayer.masksToBounds = NO;
    [context->page_layer addSublayer:chartLayer];

    CALayer *baseline = [CALayer layer];
    baseline.frame = CGRectMake(0, chart.size.height - 1, chart.size.width, 1);
    baseline.backgroundColor = [NSColor.separatorColor colorWithAlphaComponent:0.6].CGColor;
    [chartLayer addSublayer:baseline];

    CAShapeLayer *path = [CAShapeLayer layer];
    CGMutablePathRef graph = CGPathCreateMutable();
    NSInteger sampleCount = 400;
    CGFloat minValue = CGFLOAT_MAX;
    CGFloat maxValue = -CGFLOAT_MAX;
    CGFloat values[400];
    for (NSInteger i = 0; i < sampleCount; i++) {
        CGFloat f = (CGFloat)i / (CGFloat)(sampleCount - 1);
        CGFloat value = OFTimelineFunctionValueAt(OFTimelineDomainEnd * f);
        values[i] = value;
        minValue = MIN(minValue, value);
        maxValue = MAX(maxValue, value);
    }
    for (NSInteger i = 0; i < sampleCount; i++) {
        CGFloat f = (CGFloat)i / (CGFloat)(sampleCount - 1);
        CGFloat x = f * chart.size.width;
        CGFloat normalized = (values[i] - minValue) / MAX(maxValue - minValue, 0.01);
        CGFloat y = normalized * chart.size.height;
        if (i == 0) {
            CGPathMoveToPoint(graph, NULL, x, y);
        } else {
            CGPathAddLineToPoint(graph, NULL, x, y);
        }
    }
    path.path = graph;
    path.strokeColor = NSColor.controlAccentColor.CGColor;
    path.fillColor = NSColor.clearColor.CGColor;
    path.lineWidth = 2.0;
    path.lineJoin = kCALineJoinRound;
    path.lineCap = kCALineCapRound;
    [chartLayer addSublayer:path];
    CGPathRelease(graph);

    if (state.hasSelection) {
        CGFloat left = state.start * chart.size.width;
        CGFloat right = state.end * chart.size.width;
        CALayer *dimming = [CALayer layer];
        dimming.frame = chartLayer.bounds;
        dimming.backgroundColor = [NSColor colorWithCalibratedWhite:0.85 alpha:0.85].CGColor;
        CAShapeLayer *mask = [CAShapeLayer layer];
        CGMutablePathRef maskPath = CGPathCreateMutable();
        CGPathAddRect(maskPath, NULL, chartLayer.bounds);
        CGPathAddRect(maskPath, NULL, CGRectMake(left, 0, MAX(right - left, 0), chart.size.height));
        mask.path = maskPath;
        mask.fillRule = kCAFillRuleEvenOdd;
        dimming.mask = mask;
        [chartLayer addSublayer:dimming];
        CGPathRelease(maskPath);

        for (NSNumber *xValue in @[@(left), @(right)]) {
            CALayer *handle = [CALayer layer];
            handle.frame = CGRectMake(xValue.doubleValue - 1, 0, 2, chart.size.height);
            handle.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.9].CGColor;
            [chartLayer addSublayer:handle];
        }
    }

    if (state.hasHover) {
        CGFloat fraction = OFClamp(state.hoverFraction, 0, 1);
        CGFloat x = fraction * chart.size.width;
        CAShapeLayer *hoverLine = [CAShapeLayer layer];
        CGMutablePathRef linePath = CGPathCreateMutable();
        CGPathMoveToPoint(linePath, NULL, x, 0);
        CGPathAddLineToPoint(linePath, NULL, x, chart.size.height);
        hoverLine.path = linePath;
        hoverLine.strokeColor = NSColor.secondaryLabelColor.CGColor;
        hoverLine.lineDashPattern = @[ @4, @3 ];
        hoverLine.lineWidth = 1;
        hoverLine.fillColor = NSColor.clearColor.CGColor;
        [chartLayer addSublayer:hoverLine];
        CGPathRelease(linePath);

        CGFloat domainX = OFTimelineDomainEnd * fraction;
        CGFloat valueY = OFTimelineFunctionValueAt(domainX);
        CGFloat normalized = (valueY - minValue) / MAX(maxValue - minValue, 0.0001);
        CGFloat textY = normalized * chart.size.height;
        NSString *hoverText = [NSString stringWithFormat:@"x=%.2f  f(x)=%.2f", domainX, valueY];
        CATextLayer *hoverTextLayer = OFTextLayer(hoverText, [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium], NSColor.labelColor, 12);
        hoverTextLayer.alignmentMode = kCAAlignmentCenter;
        CGFloat textWidth = 140;
        CGFloat textHeight = 18;
        CGFloat textOriginX = OFClamp(x - textWidth / 2, 0, chart.size.width - textWidth);
        CGFloat textOriginY = OFClamp(textY - textHeight - 6, 0, chart.size.height - textHeight);
        hoverTextLayer.frame = CGRectMake(textOriginX, textOriginY, textWidth, textHeight);
        [chartLayer addSublayer:hoverTextLayer];
    }

    OFCookbookAddAccessibilityLabel(context, rangeText, chart, OFAccessibilityRoleImage);
}

void OFCookbookTimelineRangeMouseDown(OFCookbookRecipeContext *context, CGPoint point, bool *needs_render) {
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStateForContext(context);
    CGRect chart = OFTimelineChartFrame(context->current_size);
    if (!CGRectContainsPoint(chart, point)) {
        state.dragOperation = 0;
        return;
    }

    CGFloat localX = point.x - CGRectGetMinX(chart);
    CGFloat fraction = OFClamp(localX / MAX(chart.size.width, 1), 0, 1);

    if (state.hasSelection) {
        CGFloat startX = state.start * chart.size.width;
        CGFloat endX = state.end * chart.size.width;
        if (fabs(localX - startX) <= OFTimelineHandleHitWidth) {
            state.dragOperation = 2;
            return;
        }
        if (fabs(localX - endX) <= OFTimelineHandleHitWidth) {
            state.dragOperation = 3;
            return;
        }
        if (localX >= startX && localX <= endX) {
            state.hasSelection = false;
            state.creationDidMove = false;
            state.dragAnchor = fraction;
            state.dragOperation = 1;
            *needs_render = true;
            return;
        }
    }

    state.hasSelection = false;
    state.creationDidMove = false;
    state.dragAnchor = fraction;
    state.dragOperation = 1;
    *needs_render = true;
}

void OFCookbookTimelineRangeMouseDragged(OFCookbookRecipeContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render) {
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStateForContext(context);
    if (state.dragOperation == 0) {
        return;
    }
    CGRect chart = OFTimelineChartFrame(context->current_size);
    CGFloat localX = OFClamp(point.x - CGRectGetMinX(chart), 0, chart.size.width);
    CGFloat fraction = OFClamp(localX / MAX(chart.size.width, 1), 0, 1);

    if (state.dragOperation == 1) {
        if (!state.creationDidMove && fabs(fraction - state.dragAnchor) > 0.001) {
            state.creationDidMove = true;
        }
        if (!state.creationDidMove) {
            return;
        }
        state.start = MIN(state.dragAnchor, fraction);
        state.end = MAX(state.dragAnchor, fraction);
        state.hasSelection = true;
    } else if (state.dragOperation == 2 && state.hasSelection) {
        state.start = MIN(MAX(fraction, 0), state.end);
    } else if (state.dragOperation == 3 && state.hasSelection) {
        state.end = MAX(MIN(fraction, 1), state.start);
    }
    OFCookbookTimelineRangeMouseMoved(context, point, cursor, needs_render);
}

void OFCookbookTimelineRangeMouseUp(OFCookbookRecipeContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render) {
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStateForContext(context);
    if (state.dragOperation == 1 && !state.creationDidMove) {
        state.hasSelection = false;
        *needs_render = true;
    }
    state.dragOperation = 0;
    state.creationDidMove = false;
    OFCookbookTimelineRangeMouseMoved(context, point, cursor, needs_render);
}

void OFCookbookTimelineRangeMouseMoved(OFCookbookRecipeContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render) {
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStateForContext(context);
    CGRect chart = OFTimelineChartFrame(context->current_size);
    CGFloat clampedX = OFClamp(point.x - CGRectGetMinX(chart), 0, chart.size.width);
    state.hoverFraction = OFClamp(clampedX / MAX(chart.size.width, 1), 0, 1);
    state.hasHover = true;

    *cursor = OFCursorTypeArrow;
    if (state.hasSelection && CGRectContainsPoint(chart, point)) {
        CGFloat localX = point.x - CGRectGetMinX(chart);
        CGFloat startX = state.start * chart.size.width;
        CGFloat endX = state.end * chart.size.width;
        if (fabs(localX - startX) <= OFTimelineHandleHitWidth || fabs(localX - endX) <= OFTimelineHandleHitWidth) {
            *cursor = OFCursorTypeResizeLeftRight;
        }
    }
    *needs_render = true;
}

static void OFCookbookTimelineRangeSelectorMouseMoved(OFCookbookRecipeContext *context, CGPoint point) {
    OFCursorType cursor = OFCursorTypeArrow;
    bool needs_render = false;
    OFCookbookTimelineRangeMouseMoved(context, point, &cursor, &needs_render);
    OFHostSetCursor(context->host, cursor);
    if (needs_render) {
        OFCookbookTimelineRangeSelectorRenderFrame(context);
    }
}

static void OFCookbookTimelineRangeSelectorMouseDown(OFCookbookRecipeContext *context, CGPoint point, uint32_t click_count) {
    (void)click_count;
    bool needs_render = false;
    OFCookbookTimelineRangeMouseDown(context, point, &needs_render);
    if (needs_render) {
        OFCookbookTimelineRangeSelectorRenderFrame(context);
    }
}

static void OFCookbookTimelineRangeSelectorMouseDragged(OFCookbookRecipeContext *context, CGPoint point) {
    OFCursorType cursor = OFCursorTypeArrow;
    bool needs_render = false;
    OFCookbookTimelineRangeMouseDragged(context, point, &cursor, &needs_render);
    OFHostSetCursor(context->host, cursor);
    if (needs_render) {
        OFCookbookTimelineRangeSelectorRenderFrame(context);
    }
}

static void OFCookbookTimelineRangeSelectorMouseUp(OFCookbookRecipeContext *context, CGPoint point) {
    OFCursorType cursor = OFCursorTypeArrow;
    bool needs_render = false;
    OFCookbookTimelineRangeMouseUp(context, point, &cursor, &needs_render);
    OFHostSetCursor(context->host, cursor);
    if (needs_render) {
        OFCookbookTimelineRangeSelectorRenderFrame(context);
    }
}

static void OFCookbookTimelineRangeSelectorRenderFrame(OFCookbookRecipeContext *context) {
    OFCookbookRenderRecipeFrame(context, OFCookbookRenderTimelineRangeSelector);
    OFCookbookTimelineRangeSelectorStateForContext(context).pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, nil);
}

static bool OFCookbookTimelineRangeSelectorHandleBrowserMessage(OFCookbookRecipeContext *context, const OFBrowserMessage *message) {
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
            OFCookbookTimelineRangeSelectorRenderFrame(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = message->as.resize;
            OFCookbookTimelineRangeSelectorRenderFrame(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.appearance.appearance_archive.bytes
                                                 length:message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookTimelineRangeSelectorRenderFrame(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookTimelineRangeSelectorRenderFrame(context);
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
        case OFBrowserMessageMouseMoved:
            OFCookbookTimelineRangeSelectorMouseMoved(context,
                                                      OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.mouse.x, message->as.mouse.y)));
            return true;
        case OFBrowserMessageMouseDown:
            OFCookbookTimelineRangeSelectorMouseDown(context,
                                                     OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.mouse.x, message->as.mouse.y)),
                                                     message->as.mouse.click_count);
            return true;
        case OFBrowserMessageMouseDragged:
            OFCookbookTimelineRangeSelectorMouseDragged(context,
                                                        OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.mouse.x, message->as.mouse.y)));
            return true;
        case OFBrowserMessageMouseUp:
            OFCookbookTimelineRangeSelectorMouseUp(context,
                                                   OFCookbookViewportPointFromRootPoint(context, CGPointMake(message->as.mouse.x, message->as.mouse.y)));
            return true;
        default:
            return false;
    }
}

const OFCookbookRecipeHandler OFCookbookTimelineRangeSelectorHandler = {
    .handle_message = OFCookbookTimelineRangeSelectorHandleMessage,
    .enter_route = OFCookbookTimelineRangeSelectorEnterRoute,
    .leave_route = OFCookbookTimelineRangeSelectorLeaveRoute,
};

static void OFCookbookTimelineRangeSelectorEnterRoute(void *runtime) {
    OFCookbookTimelineRangeSelectorStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookTimelineRangeSelectorState new];
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStateForRuntime(runtime);
    OFCookbookTimelineRangeSelectorApplyStateToContext(context, state);
    OFCookbookTimelineRangeSelectorRenderFrame(context);
}

static void OFCookbookTimelineRangeSelectorLeaveRoute(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStates()[key];
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    context->page_layer = nil;
    context->recipe_state = NULL;
    [OFCookbookTimelineRangeSelectorStates() removeObjectForKey:key];
}

static void OFCookbookTimelineRangeSelectorHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    OFCookbookTimelineRangeSelectorState *state = OFCookbookTimelineRangeSelectorStateForRuntime(runtime);
    OFCookbookTimelineRangeSelectorApplyStateToContext(context, state);
    OFCookbookTimelineRangeSelectorHandleBrowserMessage(context, message);
}
