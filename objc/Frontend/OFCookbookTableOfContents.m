#import "OFCookbookController.h"

@implementation OFCookbookController (TableOfContents)

- (void)renderTableOfContents {
    CGFloat contentWidth = MIN(MAX(self.currentSize.width - 48, 280), 760);
    CGFloat contentX = MAX((self.currentSize.width - contentWidth) * 0.5, 24);
    CGFloat top = 56;
    CGFloat rowHeight = 78;
    CGFloat rowGap = 12;
    CGFloat bottomPadding = 56;
    CGFloat contentHeight = top + 46 + 24 + 28 + OFCookbookRecipeCount * rowHeight + (OFCookbookRecipeCount - 1) * rowGap + bottomPadding;
    self.scrollOffset = OFClamp(self.scrollOffset, 0, MAX(0, contentHeight - self.currentSize.height));

    [self addText:@"Outerframe Cookbook"
         fontSize:30
            weight:NSFontWeightSemibold
             color:NSColor.labelColor
            frame:CGRectMake(contentX, top - self.scrollOffset, contentWidth, 38)];
    [self addText:@"Pick a recipe:"
         fontSize:15
            weight:NSFontWeightRegular
             color:NSColor.secondaryLabelColor
            frame:CGRectMake(contentX, top + 46 - self.scrollOffset, contentWidth, 24)];

    CGFloat y = top + 46 + 24 + 28 - self.scrollOffset;
    for (NSInteger i = 0; i < OFCookbookRecipeCount; i++) {
        OFCookbookRoute route = OFCookbookRouteAtIndex(i);
        CGRect rowFrame = CGRectMake(contentX, y, contentWidth, rowHeight);
        CALayer *row = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 8);
        row.frame = rowFrame;
        [self.pageLayer addSublayer:row];

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

        [self.hitFrames addObject:[NSValue valueWithRect:rowFrame]];
        [self.hitRoutes addObject:@(route)];
        [self addAccessibilityLabel:OFCookbookRouteTitle(route) frame:rowFrame role:OFAccessibilityRoleButton];
        y += rowHeight + rowGap;
    }

    [self addScrollbarForContentHeight:MAX(contentHeight, self.currentSize.height) viewportHeight:self.currentSize.height offset:self.scrollOffset outer:YES];
}


@end
