#import "OFCookbookController.h"

@implementation OFCookbookController (GiantPageWithAnimations)

- (void)renderGiantPage {
    NSInteger itemCount = 420;
    CGFloat rowHeight = 80;
    CGFloat topPadding = 96;
    CGFloat bottomPadding = 96;
    CGFloat horizontalPadding = 24;
    CGFloat backgroundInset = 14;
    CGFloat rowWidth = MAX(MIN(self.currentSize.width * 0.55, MAX(self.currentSize.width - horizontalPadding * 2, 200)), 220);
    CGFloat containerX = MAX((self.currentSize.width - rowWidth) * 0.5, backgroundInset);
    CGFloat titleY = topPadding - 28;
    CGFloat subtitleY = titleY + 28 + 12;
    CGFloat rowsStartY = subtitleY + 72 + 24;
    CGFloat contentHeight = rowsStartY + itemCount * rowHeight + bottomPadding;
    self.scrollOffset = OFClamp(self.scrollOffset, 0, MAX(0, contentHeight - self.currentSize.height));

    CALayer *background = OFRoundedLayer([NSColor.textBackgroundColor colorWithAlphaComponent:0.9], NSColor.separatorColor, 12);
    background.frame = CGRectMake(MAX(containerX - backgroundInset, 0),
                                  MIN(titleY, subtitleY) - 24 - self.scrollOffset,
                                  MAX(rowWidth + backgroundInset * 2, 120),
                                  contentHeight - (MIN(titleY, subtitleY) - 24) + 24);
    background.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.1].CGColor;
    background.shadowOpacity = 1;
    background.shadowRadius = 7;
    [self.pageLayer addSublayer:background];

    [self addText:@"Giant page with animations" fontSize:20 weight:NSFontWeightSemibold color:NSColor.labelColor frame:CGRectMake(containerX, titleY - self.scrollOffset, rowWidth, 28)];
    [self addText:@"Layers only exist while visible. Animations continue in sync even when created mid-scroll. The animation runs inside WindowServer, not this OuterContent process." fontSize:14 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor frame:CGRectMake(containerX, subtitleY - self.scrollOffset, rowWidth, 72)];

    CGFloat visibleStart = MAX(self.scrollOffset - 220, 0);
    CGFloat visibleEnd = MIN(self.scrollOffset + self.currentSize.height + 220, contentHeight);
    NSInteger firstIndex = MAX((NSInteger)floor((visibleStart - rowsStartY) / rowHeight), 0);
    NSInteger lastIndex = MIN((NSInteger)ceil((visibleEnd - rowsStartY) / rowHeight), itemCount - 1);
    for (NSInteger i = firstIndex; i <= lastIndex; i++) {
        CGFloat y = rowsStartY + i * rowHeight - self.scrollOffset;
        CGRect frame = CGRectMake(containerX, y, rowWidth, rowHeight);
        CALayer *cell = OFRoundedLayer([NSColor.textBackgroundColor colorWithAlphaComponent:0.92], NSColor.separatorColor, 14);
        cell.frame = frame;
        cell.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.08].CGColor;
        cell.shadowOpacity = 1;
        cell.shadowRadius = 6;
        [self.pageLayer addSublayer:cell];

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
        travel.beginTime = [dot convertTime:self.giantAnimationBaseTime fromLayer:nil];
        travel.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        travel.removedOnCompletion = NO;
        travel.fillMode = kCAFillModeBoth;
        [dot addAnimation:travel forKey:@"dot-travel"];

        NSString *labelText = [NSString stringWithFormat:@"Moving dot %ld", (long)i + 1];
        if (CGRectIntersectsRect(frame, self.pageLayer.bounds)) {
            [self addAccessibilityLabel:labelText frame:frame role:OFAccessibilityRoleStaticText];
        }
    }
    [self addScrollbarForContentHeight:contentHeight viewportHeight:self.currentSize.height offset:self.scrollOffset outer:YES];
}

@end
