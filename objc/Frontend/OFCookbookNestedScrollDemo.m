#import "OFCookbookController.h"

@implementation OFCookbookController (NestedScrollDemo)

- (void)renderNestedScroll {
    CGFloat outerRowHeight = 44;
    CGFloat innerRowHeight = 26;
    CGFloat outerTopPadding = 56;
    CGFloat outerBottomPadding = 40;
    CGFloat innerSpacingAbove = 24;
    CGFloat innerSpacingBelow = 24;
    CGFloat innerViewportHeight = 200;
    NSInteger innerInsertionIndex = 6;
    CGFloat outerContentHeight = outerTopPadding + 24 * outerRowHeight + innerSpacingAbove + innerViewportHeight + innerSpacingBelow + outerBottomPadding;
    self.scrollOffset = OFClamp(self.scrollOffset, 0, MAX(0, outerContentHeight - self.currentSize.height + 40));
    [self addText:@"Nested Scroll Demo (outer surface)"
         fontSize:20
           weight:NSFontWeightSemibold
            color:NSColor.labelColor
            frame:CGRectMake(24, outerTopPadding - 36 - self.scrollOffset, MAX(self.currentSize.width - 48, 120), 28)];

    CALayer *outerBackground = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 12);
    outerBackground.frame = CGRectMake(16, outerTopPadding - 12 - self.scrollOffset, MAX(self.currentSize.width - 32, 120), outerContentHeight - outerTopPadding + 24);
    outerBackground.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.1].CGColor;
    outerBackground.shadowOpacity = 1;
    outerBackground.shadowRadius = 6;
    outerBackground.zPosition = -1;
    [self.pageLayer addSublayer:outerBackground];

    CGFloat y = outerTopPadding - self.scrollOffset;
    for (NSInteger i = 0; i < 24; i++) {
        if (i == innerInsertionIndex) {
            y += innerSpacingAbove;
            CGRect innerFrame = CGRectMake(24, y, MAX(self.currentSize.width - 48, 120), innerViewportHeight);
            CALayer *inner = OFRoundedLayer([NSColor.controlBackgroundColor colorWithAlphaComponent:0.9], [NSColor.systemBlueColor colorWithAlphaComponent:0.6], 10);
            inner.geometryFlipped = NO;
            inner.borderWidth = 2;
            inner.frame = innerFrame;
            inner.masksToBounds = YES;
            [self.pageLayer addSublayer:inner];
            [self.hitFrames addObject:[NSValue valueWithRect:innerFrame]];
            [self.hitRoutes addObject:@(OFCookbookRouteNestedScroll)];

            CATextLayer *innerTitle = OFTextLayer(@"Nested inner surface", [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold], NSColor.systemBlueColor, 14);
            innerTitle.frame = CGRectMake(12, 12, MAX(innerFrame.size.width - 24, 60), 20);
            [inner addSublayer:innerTitle];

            CGFloat innerContentHeight = 36 * innerRowHeight + 12;
            self.innerScrollOffset = OFClamp(self.innerScrollOffset, 0, MAX(0, innerContentHeight - (innerViewportHeight - 32)));
            for (NSInteger innerIndex = 0; innerIndex < 36; innerIndex++) {
                CGFloat visualY = 32 + innerIndex * innerRowHeight - self.innerScrollOffset;
                NSString *text = [NSString stringWithFormat:@"Inner row %ld", (long)innerIndex + 1];
                CATextLayer *label = OFTextLayer(text, [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular], [NSColor.labelColor colorWithAlphaComponent:0.8], 13);
                label.frame = CGRectMake(12, visualY, MAX(innerFrame.size.width - 24, 60), innerRowHeight);
                [inner addSublayer:label];
            }
            [self addAccessibilityLabel:@"Nested inner surface" frame:innerFrame role:OFAccessibilityRoleContainer];
            y += innerViewportHeight + innerSpacingBelow;
        }

        NSString *text = [NSString stringWithFormat:@"Outer row %ld", (long)i + 1];
        CATextLayer *label = OFTextLayer(text, [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], NSColor.labelColor, 16);
        label.frame = CGRectMake(24, y, MAX(self.currentSize.width - 48, 120), outerRowHeight);
        [self.pageLayer addSublayer:label];
        [self addAccessibilityLabel:text frame:label.frame role:OFAccessibilityRoleStaticText];
        y += outerRowHeight;
    }
    [self addScrollbarForContentHeight:outerContentHeight viewportHeight:self.currentSize.height offset:self.scrollOffset outer:YES];
}

- (BOOL)nestedScrollByAdjustedDelta:(CGFloat)adjusted atPoint:(CGPoint)point {
    for (NSValue *frameValue in self.hitFrames) {
        if (CGRectContainsPoint(frameValue.rectValue, point)) {
            self.innerScrollOffset = OFClamp(self.innerScrollOffset + adjusted, 0, 900);
            [self renderCurrentRoute];
            return YES;
        }
    }
    return NO;
}

@end
