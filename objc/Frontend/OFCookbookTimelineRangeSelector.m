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

@implementation OFCookbookController (TimelineRangeSelector)

- (void)renderTimelineRange {
    CGRect cardFrame = OFTimelineCardFrame(self.currentSize);
    CALayer *card = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 14);
    card.frame = cardFrame;
    card.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.08].CGColor;
    card.shadowOpacity = 1;
    card.shadowRadius = 8;
    [self.pageLayer addSublayer:card];

    [self addText:@"Timeline Range Selector" fontSize:22 weight:NSFontWeightSemibold color:NSColor.labelColor frame:CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 32, cardFrame.size.width - 64, 28)];
    [self addText:@"Click and drag to choose a range. Adjust a handle to refine." fontSize:14 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor frame:CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 64, cardFrame.size.width - 64, 42)];
    [self addText:@"Integral of f(x) over selection" fontSize:12 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor frame:CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 110, cardFrame.size.width - 64, 18)];

    NSString *valueText = @"Select a range";
    NSString *rangeText = @"Click and drag over the curve";
    if (self.timelineHasSelection) {
        CGFloat start = OFTimelineDomainEnd * self.timelineStart;
        CGFloat end = OFTimelineDomainEnd * self.timelineEnd;
        CGFloat integral = [self timelineIntegralFrom:start to:end];
        valueText = [NSString stringWithFormat:@"∫ = %.2f", integral];
        rangeText = [NSString stringWithFormat:@"Range: %.2f → %.2f", start, end];
    }

    CATextLayer *valueLayer = OFTextLayer(valueText, [NSFont monospacedDigitSystemFontOfSize:28 weight:NSFontWeightSemibold], NSColor.labelColor, 28);
    valueLayer.frame = CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 130, cardFrame.size.width - 64, 36);
    [self.pageLayer addSublayer:valueLayer];
    [self addAccessibilityLabel:valueText frame:valueLayer.frame role:OFAccessibilityRoleStaticText];
    [self addText:rangeText fontSize:13 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor frame:CGRectMake(cardFrame.origin.x + 32, cardFrame.origin.y + 172, cardFrame.size.width - 64, 20)];

    CGRect chart = OFTimelineChartFrame(self.currentSize);
    CALayer *chartLayer = [CALayer layer];
    chartLayer.geometryFlipped = YES;
    chartLayer.frame = chart;
    chartLayer.masksToBounds = NO;
    [self.pageLayer addSublayer:chartLayer];

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
        CGFloat value = [self timelineFunctionValueAt:OFTimelineDomainEnd * f];
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

    if (self.timelineHasSelection) {
        CGFloat left = self.timelineStart * chart.size.width;
        CGFloat right = self.timelineEnd * chart.size.width;
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

    if (self.timelineHasHover) {
        CGFloat fraction = OFClamp(self.timelineHoverFraction, 0, 1);
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
        CGFloat valueY = [self timelineFunctionValueAt:domainX];
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

    [self.hitFrames addObject:[NSValue valueWithRect:chart]];
    [self.hitRoutes addObject:@(OFCookbookRouteTimelineRange)];
    [self addAccessibilityLabel:rangeText frame:chart role:OFAccessibilityRoleImage];
}

- (CGFloat)timelineFunctionValueAt:(CGFloat)x {
    return sin(x * 0.9) + 0.35 * sin(x * 2.1 + 0.7) + 0.2 * cos(x * 3.7) + 2.0;
}

- (CGFloat)timelineIntegralFrom:(CGFloat)start to:(CGFloat)end {
    if (end <= start) return 0;
    NSInteger steps = 512;
    CGFloat delta = (end - start) / (CGFloat)steps;
    CGFloat sum = 0;
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat x = start + (CGFloat)i * delta;
        CGFloat weight = (i == 0 || i == steps) ? 0.5 : 1;
        sum += weight * [self timelineFunctionValueAt:x];
    }
    return sum * delta;
}

- (void)timelineMouseDownAtPoint:(CGPoint)point {
    CGRect chart = OFTimelineChartFrame(self.currentSize);
    if (!CGRectContainsPoint(chart, point)) {
        self.timelineDragOperation = 0;
        return;
    }

    CGFloat localX = point.x - CGRectGetMinX(chart);
    CGFloat fraction = OFClamp(localX / MAX(chart.size.width, 1), 0, 1);

    if (self.timelineHasSelection) {
        CGFloat startX = self.timelineStart * chart.size.width;
        CGFloat endX = self.timelineEnd * chart.size.width;
        if (fabs(localX - startX) <= OFTimelineHandleHitWidth) {
            self.timelineDragOperation = 2;
            return;
        }
        if (fabs(localX - endX) <= OFTimelineHandleHitWidth) {
            self.timelineDragOperation = 3;
            return;
        }
        if (localX >= startX && localX <= endX) {
            self.timelineHasSelection = NO;
            self.timelineCreationDidMove = NO;
            self.timelineDragAnchor = fraction;
            self.timelineDragOperation = 1;
            [self renderCurrentRoute];
            return;
        }
    }

    self.timelineHasSelection = NO;
    self.timelineCreationDidMove = NO;
    self.timelineDragAnchor = fraction;
    self.timelineDragOperation = 1;
    [self renderCurrentRoute];
}

- (void)timelineMouseDraggedToPoint:(CGPoint)point {
    if (self.timelineDragOperation == 0) {
        return;
    }
    CGRect chart = OFTimelineChartFrame(self.currentSize);
    CGFloat localX = OFClamp(point.x - CGRectGetMinX(chart), 0, chart.size.width);
    CGFloat fraction = OFClamp(localX / MAX(chart.size.width, 1), 0, 1);

    if (self.timelineDragOperation == 1) {
        if (!self.timelineCreationDidMove && fabs(fraction - self.timelineDragAnchor) > 0.001) {
            self.timelineCreationDidMove = YES;
        }
        if (!self.timelineCreationDidMove) {
            return;
        }
        self.timelineStart = MIN(self.timelineDragAnchor, fraction);
        self.timelineEnd = MAX(self.timelineDragAnchor, fraction);
        self.timelineHasSelection = YES;
    } else if (self.timelineDragOperation == 2 && self.timelineHasSelection) {
        self.timelineStart = MIN(MAX(fraction, 0), self.timelineEnd);
    } else if (self.timelineDragOperation == 3 && self.timelineHasSelection) {
        self.timelineEnd = MAX(MIN(fraction, 1), self.timelineStart);
    }
    [self timelineMouseMovedAtPoint:point];
}

- (void)timelineMouseUpAtPoint:(CGPoint)point {
    if (self.timelineDragOperation == 1 && !self.timelineCreationDidMove) {
        self.timelineHasSelection = NO;
        [self renderCurrentRoute];
    }
    self.timelineDragOperation = 0;
    self.timelineCreationDidMove = NO;
    [self timelineMouseMovedAtPoint:point];
}

- (void)timelineMouseMovedAtPoint:(CGPoint)point {
    CGRect chart = OFTimelineChartFrame(self.currentSize);
    CGFloat clampedX = OFClamp(point.x - CGRectGetMinX(chart), 0, chart.size.width);
    self.timelineHoverFraction = OFClamp(clampedX / MAX(chart.size.width, 1), 0, 1);
    self.timelineHasHover = YES;

    OFCursorType cursor = OFCursorTypeArrow;
    if (self.timelineHasSelection && CGRectContainsPoint(chart, point)) {
        CGFloat localX = point.x - CGRectGetMinX(chart);
        CGFloat startX = self.timelineStart * chart.size.width;
        CGFloat endX = self.timelineEnd * chart.size.width;
        if (fabs(localX - startX) <= OFTimelineHandleHitWidth || fabs(localX - endX) <= OFTimelineHandleHitWidth) {
            cursor = OFCursorTypeResizeLeftRight;
        }
    }
    OFHostSetCursor(self.host, cursor);
    [self renderCurrentRoute];
}

@end
