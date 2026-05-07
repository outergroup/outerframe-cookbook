#import "OFCookbookController.h"

const NSInteger OFCookbookRecipeCount = 6;

NSString *OFCookbookRouteTitle(OFCookbookRoute route) {
    switch (route) {
        case OFCookbookRouteTableOfContents: return @"Outerframe Cookbook";
        case OFCookbookRouteAccessibleText: return @"Accessible Text Region";
        case OFCookbookRouteManualScroll: return @"Manual Scroll View";
        case OFCookbookRouteNestedScroll: return @"Nested Scroll Demo";
        case OFCookbookRouteTimelineRange: return @"Timeline Range Selector";
        case OFCookbookRouteGiantPage: return @"Giant Page With Animations";
        case OFCookbookRouteNCube: return @"N-Dimensional Cube Shadow";
    }
}

NSString *OFCookbookRouteDescription(OFCookbookRoute route) {
    switch (route) {
        case OFCookbookRouteTableOfContents:
            return @"Choose a cookbook entry.";
        case OFCookbookRouteAccessibleText:
            return @"A scrollable text region with selection, copy, and accessibility.";
        case OFCookbookRouteManualScroll:
            return @"A manual layer-backed scroll view with a custom scrollbar.";
        case OFCookbookRouteNestedScroll:
            return @"Nested scroll regions with independent hit testing.";
        case OFCookbookRouteTimelineRange:
            return @"A draggable chart selection surface with hover feedback.";
        case OFCookbookRouteGiantPage:
            return @"A virtualized page with many synchronized animations.";
        case OFCookbookRouteNCube:
            return @"Translucent face projections from a rotating N-dimensional cube.";
    }
}

OFCookbookRoute OFCookbookRouteAtIndex(NSInteger index) {
    switch (index) {
        case 0: return OFCookbookRouteAccessibleText;
        case 1: return OFCookbookRouteManualScroll;
        case 2: return OFCookbookRouteNestedScroll;
        case 3: return OFCookbookRouteTimelineRange;
        case 4: return OFCookbookRouteGiantPage;
        default: return OFCookbookRouteNCube;
    }
}

CGFloat OFClamp(CGFloat value, CGFloat lower, CGFloat upper) {
    return MIN(MAX(value, lower), upper);
}

CATextLayer *OFTextLayer(NSString *text, NSFont *font, NSColor *color, CGFloat fontSize) {
    CATextLayer *layer = [CATextLayer layer];
    layer.string = text;
    layer.font = (__bridge CFTypeRef)font;
    layer.fontSize = fontSize;
    layer.foregroundColor = color.CGColor;
    layer.contentsScale = NSScreen.mainScreen.backingScaleFactor ?: 2.0;
    layer.wrapped = YES;
    layer.truncationMode = kCATruncationEnd;
    return layer;
}

CALayer *OFRoundedLayer(NSColor *fill, NSColor *stroke, CGFloat radius) {
    CALayer *layer = [CALayer layer];
    layer.backgroundColor = fill.CGColor;
    layer.borderColor = stroke.CGColor;
    layer.borderWidth = 1.0;
    layer.cornerRadius = radius;
    layer.masksToBounds = YES;
    layer.geometryFlipped = YES;
    return layer;
}

@implementation OFTextKitDisplayLayer

- (instancetype)init {
    self = [super init];
    if (self) {
        self.contentsScale = NSScreen.mainScreen.backingScaleFactor ?: 2.0;
        self.needsDisplayOnBoundsChange = YES;
    }
    return self;
}

- (void)drawInContext:(CGContextRef)ctx {
    NSTextLayoutManager *textLayoutManager = self.textLayoutManager;
    if (!textLayoutManager) {
        return;
    }

    NSAppearance *appearance = self.appearance ?: NSAppearance.currentDrawingAppearance;
    [appearance performAsCurrentDrawingAppearance:^{
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, self.textInset.x, self.textInset.y - self.scrollOffset);

        CGRect visibleTextRect = CGRectOffset(self.visibleBounds, -self.textInset.x, self.scrollOffset - self.textInset.y);
        [textLayoutManager enumerateTextLayoutFragmentsFromLocation:textLayoutManager.documentRange.location
                                                            options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout
                                                         usingBlock:^BOOL(NSTextLayoutFragment * _Nonnull fragment) {
            CGRect frame = fragment.layoutFragmentFrame;
            if (CGRectGetMinY(frame) > CGRectGetMaxY(visibleTextRect)) {
                return NO;
            }
            if (CGRectGetMaxY(frame) >= CGRectGetMinY(visibleTextRect)) {
                [fragment drawAtPoint:frame.origin inContext:ctx];
            }
            return YES;
        }];

        CGContextRestoreGState(ctx);
    }];
}

@end
