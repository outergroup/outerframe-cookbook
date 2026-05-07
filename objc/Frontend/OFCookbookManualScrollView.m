#import "OFCookbookController.h"

@implementation OFCookbookController (ManualScrollView)

- (void)renderManualScroll {
    CGFloat rowHeight = 44;
    CGFloat topPadding = 72;
    CGFloat bottomPadding = 48;
    CGFloat horizontalPadding = 24;
    CGFloat backgroundInset = 16;
    CGFloat contentHeight = topPadding + 60 * rowHeight + bottomPadding;
    self.scrollOffset = OFClamp(self.scrollOffset, 0, MAX(0, contentHeight - self.currentSize.height));

    CGFloat rowWidth = MAX(self.currentSize.width - horizontalPadding * 2, 120);
    CGFloat backgroundWidth = MAX(self.currentSize.width - backgroundInset * 2, 120);
    CALayer *background = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 12);
    background.frame = CGRectMake(backgroundInset, topPadding - 16 - self.scrollOffset, backgroundWidth, contentHeight - topPadding + 32);
    background.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.08].CGColor;
    background.shadowOpacity = 1;
    background.shadowRadius = 6;
    [self.pageLayer addSublayer:background];

    [self addText:@"Manual Scroll View"
         fontSize:20
           weight:NSFontWeightSemibold
            color:NSColor.labelColor
            frame:CGRectMake(horizontalPadding, topPadding - 48 - self.scrollOffset, rowWidth, 28)];
    [self addText:@"This view scrolls entirely inside the outerframe layer tree."
         fontSize:14
           weight:NSFontWeightRegular
            color:NSColor.secondaryLabelColor
            frame:CGRectMake(horizontalPadding, topPadding - 22 - self.scrollOffset, rowWidth, 40)];

    CGFloat y = topPadding - self.scrollOffset;
    for (NSInteger i = 0; i < 60; i++) {
        NSString *title = [NSString stringWithFormat:@"Manual scroll row %ld", (long)i + 1];
        NSColor *color = i % 2 == 1 ? [NSColor.labelColor colorWithAlphaComponent:0.8] : NSColor.labelColor;
        CATextLayer *label = OFTextLayer(title, [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], color, 16);
        label.frame = CGRectMake(horizontalPadding, y, rowWidth, rowHeight);
        [self.pageLayer addSublayer:label];
        [self addAccessibilityLabel:title frame:label.frame role:OFAccessibilityRoleStaticText];
        y += rowHeight;
    }
    [self addScrollbarForContentHeight:contentHeight viewportHeight:self.currentSize.height offset:self.scrollOffset outer:YES];
}


@end
