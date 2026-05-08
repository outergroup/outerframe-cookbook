#import "OFCookbookController.h"

const NSInteger OFCookbookPageCount = 5;

NSString *OFCookbookRouteTitle(OFCookbookRoute route) {
    switch (route) {
        case OFCookbookRouteTableOfContents: return @"Outerframe Cookbook";
        case OFCookbookRouteTextRegion: return @"Text Region";
        case OFCookbookRouteNestedScroll: return @"Nested Scroll Demo";
        case OFCookbookRouteTimelineRange: return @"Timeline Range Selector";
        case OFCookbookRouteGiantPage: return @"Giant Page With Animations";
        case OFCookbookRouteNCube: return @"N-Dimensional Cube Shadow";
    }
}

NSString *OFCookbookRouteDescription(OFCookbookRoute route) {
    switch (route) {
        case OFCookbookRouteTableOfContents:
            return @"Choose a page.";
        case OFCookbookRouteTextRegion:
            return @"A scrollable text region with selection, copy, and accessibility.";
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
        case 0: return OFCookbookRouteTextRegion;
        case 1: return OFCookbookRouteNestedScroll;
        case 2: return OFCookbookRouteTimelineRange;
        case 3: return OFCookbookRouteGiantPage;
        default: return OFCookbookRouteNCube;
    }
}

const OFCookbookPageHandler *OFCookbookPageHandlerForRoute(OFCookbookRoute route) {
    switch (route) {
        case OFCookbookRouteTableOfContents: return &OFCookbookTableOfContentsHandler;
        case OFCookbookRouteTextRegion: return &OFCookbookTextRegionHandler;
        case OFCookbookRouteNestedScroll: return &OFCookbookNestedScrollDemoHandler;
        case OFCookbookRouteTimelineRange: return &OFCookbookTimelineRangeSelectorHandler;
        case OFCookbookRouteGiantPage: return &OFCookbookGiantPageWithAnimationsHandler;
        case OFCookbookRouteNCube: return &OFCookbookNCubeHandler;
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

void OFCookbookAddAccessibilityLabel(OFCookbookPageContext *context, NSString *label, CGRect frame, OFAccessibilityRole role) {
    [context->accessibility_labels addObject:label ?: @""];
    [context->accessibility_frames addObject:[NSValue valueWithRect:frame]];
    [context->accessibility_roles addObject:@(role)];
}

CATextLayer *OFCookbookAddText(OFCookbookPageContext *context, NSString *text, CGFloat font_size, NSFontWeight weight, NSColor *color, CGRect frame) {
    CATextLayer *layer = OFTextLayer(text, [NSFont systemFontOfSize:font_size weight:weight], color, font_size);
    layer.frame = frame;
    [context->page_layer addSublayer:layer];
    OFCookbookAddAccessibilityLabel(context, text, frame, OFAccessibilityRoleStaticText);
    return layer;
}

static NSColor *OFCookbookScrollbarTrackColor(NSAppearance *appearance) {
    __block NSColor *track = [NSColor.unemphasizedSelectedTextBackgroundColor colorWithAlphaComponent:0.35];
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor *control_background = NSColor.controlBackgroundColor;
        NSColor *label = NSColor.labelColor;
        CGFloat control_red = 0;
        CGFloat control_green = 0;
        CGFloat control_blue = 0;
        CGFloat label_red = 0;
        CGFloat label_green = 0;
        CGFloat label_blue = 0;
        [[control_background colorUsingColorSpace:NSColorSpace.genericRGBColorSpace] getRed:&control_red green:&control_green blue:&control_blue alpha:NULL];
        [[label colorUsingColorSpace:NSColorSpace.genericRGBColorSpace] getRed:&label_red green:&label_green blue:&label_blue alpha:NULL];
        CGFloat brightness = (control_red + control_green + control_blue) / 3.0;
        CGFloat blend = brightness > 0.6 ? 0.25 : 0.45;
        NSColor *fallback = [NSColor colorWithCalibratedRed:control_red + (label_red - control_red) * blend
                                                      green:control_green + (label_green - control_green) * blend
                                                       blue:control_blue + (label_blue - control_blue) * blend
                                                      alpha:brightness > 0.6 ? 0.35 : 0.6];
        track = [NSColor.unemphasizedSelectedTextBackgroundColor isEqual:control_background] ? fallback : [NSColor.unemphasizedSelectedTextBackgroundColor colorWithAlphaComponent:(brightness > 0.6 ? 0.35 : 0.6)];
    }];
    return track;
}

void OFCookbookAddScrollbarForContentHeight(OFCookbookPageContext *context, CGFloat content_height, CGFloat viewport_height, CGFloat offset) {
    CGSize viewport_size = context->current_size;
    viewport_size.height = viewport_height;
    OFCookbookAddScrollbarInLayer(context, context->page_layer, viewport_size, content_height, offset, false);
}

void OFCookbookAddScrollbarInLayer(OFCookbookPageContext *context, CALayer *layer, CGSize viewport_size, CGFloat content_height, CGFloat offset, bool bottom_origin) {
    CGFloat width = 8;
    CGFloat inset = 4;
    CGFloat track_height = MAX(0, viewport_size.height - inset * 2);
    CGFloat max_offset = MAX(0, content_height - viewport_size.height);
    if (max_offset <= 0.5 || track_height <= 0) {
        return;
    }
    CGFloat knob_proportion = MIN(MAX(viewport_size.height / content_height, 0.05), 1.0);
    CGFloat knob_height = MIN(MAX(track_height * knob_proportion, 12), track_height);
    CGFloat knob_range = MAX(track_height - knob_height, 0);
    CGFloat ratio = OFClamp(offset / max_offset, 0, 1);
    CGFloat knob_y = knob_range * (bottom_origin ? (1.0 - ratio) : ratio);

    CALayer *track = [CALayer layer];
    track.frame = CGRectMake(viewport_size.width - inset - width, inset, width, track_height);
    track.cornerRadius = width * 0.5;
    track.backgroundColor = OFCookbookScrollbarTrackColor(context->appearance).CGColor;
    track.opacity = 0.9;
    track.zPosition = 200;
    [layer addSublayer:track];

    CALayer *knob = [CALayer layer];
    knob.frame = CGRectMake(0, knob_y, width, knob_height);
    knob.cornerRadius = width * 0.5;
    knob.masksToBounds = YES;
    __block CGFloat knob_alpha = 0.75;
    [context->appearance performAsCurrentDrawingAppearance:^{
        NSColor *control_background = [NSColor.controlBackgroundColor colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
        CGFloat red = 0;
        CGFloat green = 0;
        CGFloat blue = 0;
        [control_background getRed:&red green:&green blue:&blue alpha:NULL];
        CGFloat brightness = (red + green + blue) / 3.0;
        knob_alpha = brightness > 0.6 ? 0.75 : 0.85;
    }];
    knob.backgroundColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:knob_alpha].CGColor;
    [track addSublayer:knob];
}

CGPoint OFCookbookViewportPointFromRootPoint(OFCookbookPageContext *context, CGPoint root_point) {
    if (!context->root_layer || !context->page_layer) {
        return root_point;
    }
    return [context->root_layer convertPoint:root_point toLayer:context->page_layer];
}

void OFCookbookRenderPageFrame(OFCookbookPageContext *context, void (*render)(OFCookbookPageContext *context)) {
    if (!context->root_layer || !render) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [context->accessibility_labels removeAllObjects];
    [context->accessibility_frames removeAllObjects];
    [context->accessibility_roles removeAllObjects];

    [context->appearance performAsCurrentDrawingAppearance:^{
        context->root_layer.frame = CGRectMake(0, 0, context->current_size.width, context->current_size.height);
        context->root_layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

        [context->page_layer removeFromSuperlayer];

        CALayer *page = [CALayer layer];
        page.geometryFlipped = YES;
        page.frame = context->root_layer.bounds;
        page.masksToBounds = YES;
        [context->root_layer addSublayer:page];
        context->page_layer = page;

        render(context);
    }];

    [CATransaction commit];
}

void OFCookbookUpdateRoutePageMetadata(OFCookbookPageContext *context) {
    if (!context->host) {
        return;
    }
    OFHostUpdatePageMetadata(context->host, OFCookbookRouteTitle(context->route).UTF8String, NULL, 0, 0, 0);
}

void OFCookbookUpdatePasteboardCapabilities(OFCookbookPageContext *context, NSString *selected_text) {
    const char *types[] = { "public.utf8-plain-text" };
    BOOL can_copy = selected_text.length > 0;
    OFHostSetPasteboardCapabilities(context->host, can_copy, false, can_copy ? types : NULL, can_copy ? 1 : 0);
}

void OFCookbookSendCopySelectedPasteboardResponse(OFCookbookPageContext *context, OFUUID request_id, NSString *selected_text) {
    if (selected_text.length == 0) {
        OFHostSendCopySelectedPasteboardResponse(context->host, request_id, NULL, 0);
        return;
    }

    NSData *data = [selected_text dataUsingEncoding:NSUTF8StringEncoding];
    const char *type = "public.utf8-plain-text";
    OFPasteboardItemView item = {
        .type_identifier = { .bytes = type, .length = strlen(type) },
        .data = { .bytes = data.bytes, .length = data.length },
    };
    OFHostSendCopySelectedPasteboardResponse(context->host, request_id, &item, 1);
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
