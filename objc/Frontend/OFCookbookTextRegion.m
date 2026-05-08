#import "OFCookbookController.h"

static void OFCookbookAddTextRegionSelectionLayersInViewport(OFCookbookPageContext *context, CALayer *viewport, CGPoint textInset);
static CGRect OFCookbookTextRegionViewportFrame(OFCookbookPageContext *context);
static CGRect OFCookbookTextRegionPanelFrame(OFCookbookPageContext *context);
static CGRect OFCookbookTextRegionAccessibilityFrameFromVisualRootFrame(OFCookbookPageContext *context, CGRect frame);
static NSString *OFCookbookTextRegionStringForRange(OFCookbookPageContext *context, NSTextRange *range);
static NSInteger OFCookbookTextRegionOffsetFromDocumentStartToLocation(OFCookbookPageContext *context, id<NSTextLocation> location);
static CGFloat OFCookbookTextRegionContentHeightForViewportHeight(OFCookbookPageContext *context, CGFloat viewportHeight);
static void OFCookbookConfigureTextRegionContainerForViewportSize(OFCookbookPageContext *context, CGSize viewportSize);
static CGPoint OFCookbookTextRegionContainerPointFromPagePoint(OFCookbookPageContext *context, CGPoint point);
static CGRect OFCookbookTextRegionContainerInteractionBounds(OFCookbookPageContext *context);
static bool OFCookbookIsPointInTextRegionViewport(OFCookbookPageContext *context, CGPoint point);
static void OFCookbookSetTextRegionSelection(OFCookbookPageContext *context, NSTextSelection *selection);
static NSRange OFCookbookTextRegionRangeForTextSelection(OFCookbookPageContext *context, NSTextSelection *selection);
static NSTextRange *OFCookbookTextRegionTextRangeForRange(OFCookbookPageContext *context, NSRange range);
static NSTextSelection *OFCookbookTextRegionSelectionAtPoint(OFCookbookPageContext *context, CGPoint point);
static NSAttributedString *OFCookbookAttributedTextForTextRegionSelection(OFCookbookPageContext *context, NSTextSelection *selection);
static NSAttributedString *OFCookbookSelectedTextRegionAttributedText(OFCookbookPageContext *context);
static NSInteger OFCookbookTextRegionLocationOffsetAtPoint(OFCookbookPageContext *context, CGPoint point);
static void OFCookbookShowContextMenuForTextRegionAttributedText(OFCookbookPageContext *context, NSAttributedString *text, CGPoint point);
static NSTextSelection *OFCookbookTextRegionLayoutFragmentSelectionAtTextPoint(OFCookbookPageContext *context, CGPoint textPoint);
static void OFCookbookTextRegionRenderFrame(OFCookbookPageContext *context);
static bool OFCookbookTextRegionHandleBrowserMessage(OFCookbookPageContext *context, const OFBrowserMessage *browser_message);

@interface OFCookbookTextRegionState : NSObject
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, assign) NSRange selectionRange;
@property(nonatomic, assign) BOOL hasSelectionRange;
@property(nonatomic, strong) NSString *selectedCopyText;
@property(nonatomic, strong) NSTextContentStorage *contentStorage;
@property(nonatomic, strong) NSTextLayoutManager *textLayoutManager;
@property(nonatomic, strong) NSTextContainer *textContainer;
@property(nonatomic, strong) NSAttributedString *documentText;
@property(nonatomic, strong) NSArray<NSTextSelection *> *dragAnchorSelections;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@end

@implementation OFCookbookTextRegionState
- (instancetype)init {
    self = [super init];
    if (self) {
        _contentStorage = [NSTextContentStorage new];
        _textLayoutManager = [NSTextLayoutManager new];
        _textContainer = [[NSTextContainer alloc] initWithSize:CGSizeMake(640, 1000000)];
        _textContainer.lineFragmentPadding = 0;
        _textLayoutManager.textContainer = _textContainer;
        _textLayoutManager.usesFontLeading = YES;
        [_contentStorage addTextLayoutManager:_textLayoutManager];
        _documentText = OFCookbookMakeTextRegionDocumentText();
        _contentStorage.attributedString = _documentText;
        _dragAnchorSelections = @[];
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookTextRegionState *> *OFCookbookTextRegionStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookTextRegionState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookTextRegionState *OFCookbookTextRegionStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookTextRegionState *state = OFCookbookTextRegionStates()[key];
    if (!state) {
        state = [OFCookbookTextRegionState new];
        OFCookbookTextRegionStates()[key] = state;
    }
    return state;
}

static OFCookbookTextRegionState *OFCookbookTextRegionStateForContext(OFCookbookPageContext *context) {
    return (__bridge OFCookbookTextRegionState *)context->page_state;
}

static void OFCookbookTextRegionApplyStateToContext(OFCookbookPageContext *context, OFCookbookTextRegionState *state) {
    context->page_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

void OFCookbookRenderTextRegion(OFCookbookPageContext *context) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat textInsetX = 28;
    CGFloat textInsetY = 24;
    CGFloat scrollbarWidth = 8;
    CGFloat scrollbarInset = 4;
    CGFloat contentWidth = MAX(context->current_size.width - pageInset * 2, 240);
    OFCookbookAddText(context, @"Text Region", 22, NSFontWeightSemibold, NSColor.labelColor, CGRectMake(pageInset, 18, contentWidth, 28));
    OFCookbookAddText(context, @"TextKit 2 layout with scroll, selection, copy, and accessibility.", 14, NSFontWeightRegular, NSColor.secondaryLabelColor, CGRectMake(pageInset, 47, contentWidth, 34));

    CGRect panelFrame = CGRectMake(pageInset, headerHeight, contentWidth, MAX(context->current_size.height - headerHeight - pageInset, 180));
    CALayer *background = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 8);
    background.frame = panelFrame;
    [context->page_layer addSublayer:background];

    CALayer *viewport = [CALayer layer];
    viewport.geometryFlipped = YES;
    viewport.masksToBounds = YES;
    viewport.frame = CGRectInset(panelFrame, 1, 1);
    [context->page_layer addSublayer:viewport];

    CGFloat textWidth = MAX(viewport.bounds.size.width - textInsetX * 2 - scrollbarWidth - scrollbarInset, 80);
    state.textContainer.size = CGSizeMake(textWidth, 1000000);
    [state.textLayoutManager ensureLayoutForRange:state.textLayoutManager.documentRange];
    CGFloat contentHeight = MAX(CGRectGetMaxY(state.textLayoutManager.usageBoundsForTextContainer) + textInsetY * 2,
                                viewport.bounds.size.height);
    state.scrollOffset = OFClamp(state.scrollOffset, 0, MAX(0, contentHeight - viewport.bounds.size.height));

    CALayer *selectionLayer = [CALayer layer];
    selectionLayer.geometryFlipped = YES;
    selectionLayer.frame = viewport.bounds;
    [viewport addSublayer:selectionLayer];
    OFCookbookAddTextRegionSelectionLayersInViewport(context, selectionLayer, CGPointMake(textInsetX, textInsetY));

    OFTextKitDisplayLayer *textLayer = [OFTextKitDisplayLayer layer];
    textLayer.geometryFlipped = YES;
    textLayer.frame = viewport.bounds;
    textLayer.visibleBounds = viewport.bounds;
    textLayer.textInset = CGPointMake(textInsetX, textInsetY);
    textLayer.scrollOffset = state.scrollOffset;
    textLayer.appearance = context->appearance;
    textLayer.textLayoutManager = state.textLayoutManager;
    [viewport addSublayer:textLayer];
    [textLayer setNeedsDisplay];

    OFCookbookAddScrollbarInLayer(context, viewport, viewport.bounds.size, contentHeight, state.scrollOffset, true);
}

NSAttributedString *OFCookbookMakeTextRegionDocumentText(void) {
    NSFont *titleFont = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    NSFont *bodyFont = [NSFont systemFontOfSize:16 weight:NSFontWeightRegular];
    NSFont *captionFont = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];

    NSMutableParagraphStyle *bodyParagraph = [NSMutableParagraphStyle new];
    bodyParagraph.lineSpacing = 3;
    bodyParagraph.paragraphSpacing = 14;

    NSMutableParagraphStyle *titleParagraph = [NSMutableParagraphStyle new];
    titleParagraph.paragraphSpacing = 12;

    NSMutableParagraphStyle *captionParagraph = [NSMutableParagraphStyle new];
    captionParagraph.paragraphSpacing = 18;

    NSMutableAttributedString *result = [NSMutableAttributedString new];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"Lorem Ipsum, Selectable and Copyable\n"
                                                                   attributes:@{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: NSColor.labelColor,
        NSParagraphStyleAttributeName: titleParagraph,
    }]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"This page keeps text layout in TextKit 2 while the surrounding surface stays layer-backed. Drag through the paragraphs to highlight text, then copy it with the browser or system copy command.\n"
                                                                   attributes:@{
        NSFontAttributeName: captionFont,
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
        NSParagraphStyleAttributeName: captionParagraph,
    }]];

    NSArray<NSString *> *paragraphs = @[
        @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer posuere, lacus at congue faucibus, lectus tortor facilisis lectus, vitae luctus justo dolor sed augue. Praesent efficitur magna at neque mollis, at mattis risus porttitor.",
        @"Sed euismod, erat quis tempor sollicitudin, sem tortor luctus lectus, sed dignissim arcu massa vitae erat. Nam lacinia felis ac lacus fermentum, vel eleifend nibh fermentum. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae.",
        @"Mauris pellentesque, massa quis facilisis dictum, mi arcu viverra erat, nec cursus lorem metus at arcu. Cras tristique magna vitae ex volutpat, in gravida dui dignissim. Suspendisse sed finibus purus.",
        @"Donec blandit magna ac elit mattis, a luctus justo placerat. Aenean interdum finibus libero, vitae feugiat est rhoncus id. In at luctus mi. Nulla facilisi. Curabitur vitae ex vitae ipsum ullamcorper laoreet.",
        @"Aliquam vitae interdum urna. Integer hendrerit, sapien sed venenatis porta, urna neque semper tortor, sed pretium odio erat nec urna. Phasellus porta ullamcorper eros, non varius justo sagittis sed.",
        @"Fusce gravida velit ut massa rhoncus, vitae sagittis dolor consequat. Vivamus vehicula orci vitae diam iaculis posuere. Suspendisse potenti. Donec id nibh a justo eleifend efficitur non sed nisi.",
        @"Nunc sed magna faucibus, hendrerit massa non, cursus turpis. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Ut euismod velit sit amet quam vulputate, ac cursus nibh dictum.",
        @"Etiam bibendum tortor at enim volutpat, vel finibus sem laoreet. Morbi luctus tristique arcu, ac pretium sem convallis sit amet. Duis facilisis ligula lorem, vitae pulvinar enim pulvinar non.",
        @"Proin pulvinar luctus sapien, id egestas nulla bibendum nec. Sed vestibulum, urna vel suscipit consequat, nibh tellus ultrices augue, a elementum risus libero at nulla. Integer non sem at elit interdum gravida.",
        @"Ut accumsan gravida mauris, sit amet ultricies lorem eleifend nec. Integer a neque ut massa congue tincidunt. Suspendisse gravida velit vel sem facilisis, id posuere turpis sagittis.",
    ];

    for (NSUInteger index = 0; index < paragraphs.count; index++) {
        NSMutableAttributedString *paragraph = [[NSMutableAttributedString alloc] initWithString:[paragraphs[index] stringByAppendingString:@"\n"]
                                                                                      attributes:@{
            NSFontAttributeName: bodyFont,
            NSForegroundColorAttributeName: NSColor.labelColor,
            NSParagraphStyleAttributeName: bodyParagraph,
        }];
        if (index % 3 == 1) {
            [paragraph addAttribute:NSForegroundColorAttributeName
                              value:NSColor.controlAccentColor
                              range:NSMakeRange(0, MIN((NSUInteger)18, paragraph.length))];
        }
        [result appendAttributedString:paragraph];
    }

    return result;
}

static void OFCookbookAddTextRegionSelectionLayersInViewport(OFCookbookPageContext *context, CALayer *viewport, CGPoint textInset) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    if (!state.hasSelectionRange || state.selectionRange.length == 0) {
        return;
    }
    NSTextRange *textRange = OFCookbookTextRegionTextRangeForRange(context, state.selectionRange);
    if (!textRange) {
        return;
    }

    CGColorRef selectionColor = [[NSColor selectedTextBackgroundColor] colorWithAlphaComponent:0.75].CGColor;
    [state.textLayoutManager enumerateTextSegmentsInRange:textRange
                                                              type:NSTextLayoutManagerSegmentTypeSelection
                                                           options:NSTextLayoutManagerSegmentOptionsNone
                                                        usingBlock:^BOOL(NSTextRange * _Nullable textSegmentRange, CGRect rect, CGFloat baselinePosition, NSTextContainer * _Nonnull textContainer) {
        (void)textSegmentRange;
        (void)baselinePosition;
        (void)textContainer;
        CGRect visibleFrame = CGRectMake(textInset.x + rect.origin.x,
                                         textInset.y + rect.origin.y - state.scrollOffset,
                                         rect.size.width,
                                         rect.size.height);
        if (!CGRectIntersectsRect(visibleFrame, viewport.bounds)) {
            return YES;
        }
        CALayer *highlight = [CALayer layer];
        highlight.frame = visibleFrame;
        highlight.backgroundColor = selectionColor;
        highlight.cornerRadius = 2;
        [viewport addSublayer:highlight];
        return YES;
    }];
}

static CGRect OFCookbookTextRegionViewportFrame(OFCookbookPageContext *context) {
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat contentWidth = MAX(context->current_size.width - pageInset * 2, 240);
    CGRect panelFrame = CGRectMake(pageInset, headerHeight, contentWidth, MAX(context->current_size.height - headerHeight - pageInset, 180));
    return CGRectInset(panelFrame, 1, 1);
}

static CGRect OFCookbookTextRegionPanelFrame(OFCookbookPageContext *context) {
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat contentWidth = MAX(context->current_size.width - pageInset * 2, 240);
    return CGRectMake(pageInset, headerHeight, contentWidth, MAX(context->current_size.height - headerHeight - pageInset, 180));
}

static CGRect OFCookbookTextRegionAccessibilityFrameFromVisualRootFrame(OFCookbookPageContext *context, CGRect frame) {
    return CGRectMake(CGRectGetMinX(frame),
                      context->current_size.height - CGRectGetMaxY(frame),
                      frame.size.width,
                      frame.size.height);
}

static NSString *OFCookbookTextRegionStringForRange(OFCookbookPageContext *context, NSTextRange *range) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    if (!range) {
        return nil;
    }
    id<NSTextLocation> documentStart = state.textLayoutManager.documentRange.location;
    NSInteger start = [state.contentStorage offsetFromLocation:documentStart toLocation:range.location];
    NSInteger end = [state.contentStorage offsetFromLocation:documentStart toLocation:range.endLocation];
    if (start == NSNotFound || end == NSNotFound) {
        return nil;
    }
    NSInteger location = MAX(0, MIN(start, end));
    NSInteger length = MIN((NSInteger)state.documentText.length - location, labs(end - start));
    if (length <= 0) {
        return nil;
    }
    return [state.documentText attributedSubstringFromRange:NSMakeRange((NSUInteger)location, (NSUInteger)length)].string;
}

static NSInteger OFCookbookTextRegionOffsetFromDocumentStartToLocation(OFCookbookPageContext *context, id<NSTextLocation> location) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    NSInteger offset = [state.contentStorage offsetFromLocation:state.textLayoutManager.documentRange.location
                                                              toLocation:location];
    return offset == NSNotFound ? 0 : offset;
}

bool OFCookbookWriteTextRegionAccessibilitySnapshot(OFCookbookPageContext *context, OFBuffer *outSnapshotData) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookTextRegionViewportFrame(context);
    OFCookbookConfigureTextRegionContainerForViewportSize(context, viewportFrame.size);
    [state.textLayoutManager ensureLayoutForRange:state.textLayoutManager.documentRange];

    NSMutableArray<NSMutableData *> *retainedCStringData = [NSMutableArray array];
    const char *(^retainedCString)(NSString *) = ^const char *(NSString *string) {
        NSData *encoded = [(string ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSMutableData *storage = [encoded mutableCopy];
        uint8_t terminator = 0;
        [storage appendBytes:&terminator length:1];
        [retainedCStringData addObject:storage];
        return storage.bytes;
    };
    NSString *title = @"Text Region";
    NSString *textLabel = @"Scrollable selectable text";
    NSString *textHint = @"Select text to copy it.";
    NSString *documentValue = state.documentText.string ?: @"";
    const char *titleCString = retainedCString(title);
    const char *textLabelCString = retainedCString(textLabel);
    const char *textHintCString = retainedCString(textHint);
    const char *documentValueCString = retainedCString(documentValue);

    __block size_t fragmentCapacity = 16;
    __block size_t fragmentCount = 0;
    __block BOOL allocationFailed = NO;
    __block OFAccessibilityNode *fragmentNodes = calloc(fragmentCapacity, sizeof(*fragmentNodes));
    if (!fragmentNodes) {
        return false;
    }

    CGRect viewportBoundsInRoot = viewportFrame;
    CGFloat textWidth = MAX(state.textContainer.size.width, 1);
    CGFloat textInsetX = 28;
    CGFloat textInsetY = 24;

    [state.textLayoutManager enumerateTextLayoutFragmentsFromLocation:state.textLayoutManager.documentRange.location
                                                                       options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout
                                                                    usingBlock:^BOOL(NSTextLayoutFragment * _Nonnull fragment) {
        CGRect fragmentFrame = fragment.layoutFragmentFrame;
        if (CGRectGetMinY(fragmentFrame) > state.scrollOffset + viewportFrame.size.height) {
            return NO;
        }

        CGRect rootFrame = CGRectMake(CGRectGetMinX(viewportFrame) + textInsetX,
                                      CGRectGetMinY(viewportFrame) + textInsetY + CGRectGetMinY(fragmentFrame) - state.scrollOffset,
                                      textWidth,
                                      MAX(fragmentFrame.size.height, 1));
        if (!CGRectIntersectsRect(rootFrame, viewportBoundsInRoot)) {
            return YES;
        }

        NSString *fragmentText = OFCookbookTextRegionStringForRange(context, fragment.rangeInElement);
        if ([fragmentText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
            return YES;
        }
        const char *fragmentTextCString = retainedCString(fragmentText);

        if (fragmentCount == fragmentCapacity) {
            size_t newCapacity = fragmentCapacity * 2;
            OFAccessibilityNode *newNodes = realloc(fragmentNodes, newCapacity * sizeof(*fragmentNodes));
            if (!newNodes) {
                allocationFailed = YES;
                return NO;
            }
            memset(newNodes + fragmentCapacity, 0, (newCapacity - fragmentCapacity) * sizeof(*newNodes));
            fragmentNodes = newNodes;
            fragmentCapacity = newCapacity;
        }

        NSInteger startOffset = OFCookbookTextRegionOffsetFromDocumentStartToLocation(context, fragment.rangeInElement.location);
        NSInteger safeOffset = MAX(0, MIN(startOffset, (NSInteger)UINT32_MAX - 1000));
        CGRect visibleFrame = OFCookbookTextRegionAccessibilityFrameFromVisualRootFrame(context, CGRectIntersection(rootFrame, viewportBoundsInRoot));
        fragmentNodes[fragmentCount] = (OFAccessibilityNode){
            .identifier = (uint32_t)(1000 + safeOffset),
            .role = OFAccessibilityRoleStaticText,
            .frame = visibleFrame,
            .value = fragmentTextCString,
            .enabled = true,
        };
        fragmentCount++;
        return YES;
    }];

    if (allocationFailed) {
        free(fragmentNodes);
        return false;
    }

    OFAccessibilityNode children[2] = {
        {
            .identifier = 1,
            .role = OFAccessibilityRoleStaticText,
            .frame = OFCookbookTextRegionAccessibilityFrameFromVisualRootFrame(context, CGRectMake(18, 18, MAX(context->current_size.width - 36, 240), 28)),
            .label = titleCString,
            .enabled = true,
        },
        {
            .identifier = 2,
            .role = OFAccessibilityRoleContainer,
            .frame = OFCookbookTextRegionAccessibilityFrameFromVisualRootFrame(context, OFCookbookTextRegionPanelFrame(context)),
            .label = textLabelCString,
            .value = documentValueCString,
            .hint = textHintCString,
            .enabled = true,
            .children = fragmentNodes,
            .child_count = fragmentCount,
        },
    };

    OFAccessibilityNode root = {
        .identifier = 0,
        .role = OFAccessibilityRoleContainer,
        .frame = CGRectMake(0, 0, context->current_size.width, context->current_size.height),
        .label = titleCString,
        .enabled = true,
        .children = children,
        .child_count = 2,
    };
    OFAccessibilitySnapshot snapshot = {
        .root_nodes = &root,
        .root_count = 1,
    };
    bool result = OFAccessibilitySnapshotEncode(&snapshot, outSnapshotData);
    free(fragmentNodes);
    (void)retainedCStringData;
    return result;
}

static CGFloat OFCookbookTextRegionContentHeightForViewportHeight(OFCookbookPageContext *context, CGFloat viewportHeight) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    [state.textLayoutManager ensureLayoutForRange:state.textLayoutManager.documentRange];
    return MAX(CGRectGetMaxY(state.textLayoutManager.usageBoundsForTextContainer) + 24 * 2, viewportHeight);
}

static void OFCookbookConfigureTextRegionContainerForViewportSize(OFCookbookPageContext *context, CGSize viewportSize) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGFloat textInsetX = 28;
    CGFloat scrollbarWidth = 8;
    CGFloat scrollbarInset = 4;
    CGFloat textWidth = MAX(viewportSize.width - textInsetX * 2 - scrollbarWidth - scrollbarInset, 80);
    if (fabs(state.textContainer.size.width - textWidth) > 0.5) {
        state.textContainer.size = CGSizeMake(textWidth, 1000000);
        [state.textLayoutManager ensureLayoutForRange:state.textLayoutManager.documentRange];
    }
}

static CGPoint OFCookbookTextRegionContainerPointFromPagePoint(OFCookbookPageContext *context, CGPoint point) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookTextRegionViewportFrame(context);
    return CGPointMake(point.x - CGRectGetMinX(viewportFrame) - 28,
                       point.y - CGRectGetMinY(viewportFrame) + state.scrollOffset - 24);
}

static CGRect OFCookbookTextRegionContainerInteractionBounds(OFCookbookPageContext *context) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGFloat contentHeight = OFCookbookTextRegionContentHeightForViewportHeight(context, OFCookbookTextRegionViewportFrame(context).size.height);
    return CGRectMake(0, 0, MAX(state.textContainer.size.width, 1), MAX(contentHeight - 24 * 2, state.textContainer.size.height));
}

static bool OFCookbookIsPointInTextRegionViewport(OFCookbookPageContext *context, CGPoint point) {
    return CGRectContainsPoint(OFCookbookTextRegionViewportFrame(context), point);
}

bool OFCookbookTextRegionIsPointOverText(OFCookbookPageContext *context, CGPoint point) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookTextRegionViewportFrame(context);
    if (!CGRectContainsPoint(viewportFrame, point)) {
        return NO;
    }
    OFCookbookConfigureTextRegionContainerForViewportSize(context, viewportFrame.size);
    CGPoint textPoint = OFCookbookTextRegionContainerPointFromPagePoint(context, point);
    __block BOOL found = NO;
    [state.textLayoutManager enumerateTextSegmentsInRange:state.textLayoutManager.documentRange
                                                              type:NSTextLayoutManagerSegmentTypeStandard
                                                           options:NSTextLayoutManagerSegmentOptionsNone
                                                        usingBlock:^BOOL(NSTextRange * _Nullable textSegmentRange, CGRect rect, CGFloat baselinePosition, NSTextContainer * _Nonnull textContainer) {
        (void)textSegmentRange;
        (void)baselinePosition;
        (void)textContainer;
        if (CGRectContainsPoint(CGRectInset(rect, -1, -2), textPoint)) {
            found = YES;
            return NO;
        }
        return CGRectGetMinY(rect) <= textPoint.y;
    }];
    return found;
}

static void OFCookbookSetTextRegionSelection(OFCookbookPageContext *context, NSTextSelection *selection) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    state.textLayoutManager.textSelections = selection ? @[selection] : @[];
    NSRange range = OFCookbookTextRegionRangeForTextSelection(context, selection);
    state.hasSelectionRange = range.length > 0;
    state.selectionRange = range;
    if (range.length > 0 && NSMaxRange(range) <= state.documentText.length) {
        state.selectedCopyText = [state.documentText attributedSubstringFromRange:range].string;
    } else {
        state.selectedCopyText = nil;
    }

    OFHostSendAccessibilityTreeChanged(context->host, OFAccessibilityNotificationSelectedChildrenChanged);
}

static NSRange OFCookbookTextRegionRangeForTextSelection(OFCookbookPageContext *context, NSTextSelection *selection) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    NSTextRange *textRange = selection.textRanges.firstObject;
    if (!textRange) {
        return NSMakeRange(0, 0);
    }
    id<NSTextLocation> documentStart = state.textLayoutManager.documentRange.location;
    NSInteger start = [state.contentStorage offsetFromLocation:documentStart toLocation:textRange.location];
    NSInteger end = [state.contentStorage offsetFromLocation:documentStart toLocation:textRange.endLocation];
    if (start == NSNotFound || end == NSNotFound) {
        return NSMakeRange(0, 0);
    }
    NSInteger location = MAX(0, MIN(start, end));
    NSInteger length = MIN((NSInteger)state.documentText.length - location, labs(end - start));
    if (length <= 0) {
        return NSMakeRange(0, 0);
    }
    return NSMakeRange((NSUInteger)location, (NSUInteger)length);
}

static NSTextRange *OFCookbookTextRegionTextRangeForRange(OFCookbookPageContext *context, NSRange range) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    if (range.length == 0 || NSMaxRange(range) > state.documentText.length) {
        return nil;
    }
    id<NSTextLocation> documentStart = state.textLayoutManager.documentRange.location;
    id<NSTextLocation> start = [state.contentStorage locationFromLocation:documentStart withOffset:(NSInteger)range.location];
    id<NSTextLocation> end = [state.contentStorage locationFromLocation:documentStart withOffset:(NSInteger)NSMaxRange(range)];
    if (!start || !end) {
        return nil;
    }
    return [[NSTextRange alloc] initWithLocation:start endLocation:end];
}

static NSTextSelection *OFCookbookTextRegionSelectionAtPoint(OFCookbookPageContext *context, CGPoint point) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGPoint textPoint = OFCookbookTextRegionContainerPointFromPagePoint(context, point);
    NSArray<NSTextSelection *> *selections = [state.textLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:state.textLayoutManager.documentRange.location
                                                                                                                                  anchors:@[]
                                                                                                                                modifiers:0
                                                                                                                                selecting:NO
                                                                                                                                   bounds:OFCookbookTextRegionContainerInteractionBounds(context)];
    return selections.firstObject;
}

static NSAttributedString *OFCookbookAttributedTextForTextRegionSelection(OFCookbookPageContext *context, NSTextSelection *selection) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    NSRange range = OFCookbookTextRegionRangeForTextSelection(context, selection);
    if (range.length == 0 || NSMaxRange(range) > state.documentText.length) {
        return nil;
    }
    return [state.documentText attributedSubstringFromRange:range];
}

static NSAttributedString *OFCookbookSelectedTextRegionAttributedText(OFCookbookPageContext *context) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    if (!state.hasSelectionRange ||
        state.selectionRange.length == 0 ||
        NSMaxRange(state.selectionRange) > state.documentText.length) {
        return nil;
    }
    return [state.documentText attributedSubstringFromRange:state.selectionRange];
}

static NSInteger OFCookbookTextRegionLocationOffsetAtPoint(OFCookbookPageContext *context, CGPoint point) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    NSTextSelection *selection = OFCookbookTextRegionSelectionAtPoint(context, point);
    NSTextRange *range = selection.textRanges.firstObject;
    if (!range) {
        return NSNotFound;
    }
    return [state.contentStorage offsetFromLocation:state.textLayoutManager.documentRange.location
                                                  toLocation:range.location];
}

static void OFCookbookShowContextMenuForTextRegionAttributedText(OFCookbookPageContext *context, NSAttributedString *text, CGPoint point) {
    if (text.length == 0) {
        return;
    }
    NSError *error = nil;
    NSData *rtfData = [text dataFromRange:NSMakeRange(0, text.length)
                       documentAttributes:@{ NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType }
                                    error:&error];
    if (!rtfData || error) {
        return;
    }
    OFDataView rtfView = {
        .bytes = rtfData.bytes,
        .length = rtfData.length,
    };
    OFHostShowContextMenu(context->host, rtfView, point.x, point.y);
}

static NSTextSelection *OFCookbookTextRegionLayoutFragmentSelectionAtTextPoint(OFCookbookPageContext *context, CGPoint textPoint) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    __block NSTextLayoutFragment *matchingFragment = nil;
    [state.textLayoutManager enumerateTextLayoutFragmentsFromLocation:state.textLayoutManager.documentRange.location
                                                                       options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout
                                                                    usingBlock:^BOOL(NSTextLayoutFragment * _Nonnull fragment) {
        CGRect frame = fragment.layoutFragmentFrame;
        if (CGRectGetMinY(frame) > textPoint.y) {
            return NO;
        }
        CGRect paragraphHitFrame = CGRectMake(0, CGRectGetMinY(frame), state.textContainer.size.width, MAX(frame.size.height, 1));
        if (CGRectContainsPoint(CGRectInset(paragraphHitFrame, 0, -2), textPoint)) {
            matchingFragment = fragment;
            return NO;
        }
        return YES;
    }];
    if (!matchingFragment.rangeInElement) {
        return nil;
    }
    return [[NSTextSelection alloc] initWithRange:matchingFragment.rangeInElement
                                         affinity:NSTextSelectionAffinityDownstream
                                      granularity:NSTextSelectionGranularityParagraph];
}

void OFCookbookTextRegionMouseDown(OFCookbookPageContext *context, CGPoint point, uint32_t clickCount, bool *needs_render) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookTextRegionViewportFrame(context);
    OFCookbookConfigureTextRegionContainerForViewportSize(context, viewportFrame.size);
    if (!OFCookbookIsPointInTextRegionViewport(context, point)) {
        state.dragAnchorSelections = @[];
        OFCookbookSetTextRegionSelection(context, nil);
        *needs_render = true;
        return;
    }

    CGPoint textPoint = OFCookbookTextRegionContainerPointFromPagePoint(context, point);
    NSArray<NSTextSelection *> *selections = [state.textLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:state.textLayoutManager.documentRange.location
                                                                                                                                  anchors:@[]
                                                                                                                                modifiers:0
                                                                                                                                selecting:NO
                                                                                                                                   bounds:OFCookbookTextRegionContainerInteractionBounds(context)];
    state.dragAnchorSelections = selections ?: @[];
    if (clickCount >= 3) {
        NSTextSelection *paragraphSelection = OFCookbookTextRegionLayoutFragmentSelectionAtTextPoint(context, textPoint);
        state.dragAnchorSelections = paragraphSelection ? @[paragraphSelection] : @[];
        OFCookbookSetTextRegionSelection(context, paragraphSelection);
    } else if (clickCount == 2 && selections.firstObject) {
        NSTextSelection *wordSelection = [state.textLayoutManager.textSelectionNavigation textSelectionForSelectionGranularity:NSTextSelectionGranularityWord
                                                                                                                 enclosingTextSelection:selections.firstObject];
        OFCookbookSetTextRegionSelection(context, wordSelection);
    } else {
        OFCookbookSetTextRegionSelection(context, nil);
    }
    *needs_render = true;
}

void OFCookbookTextRegionMouseDragged(OFCookbookPageContext *context, CGPoint point, bool *needs_render) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    if (state.dragAnchorSelections.count == 0) {
        return;
    }
    CGRect viewportFrame = OFCookbookTextRegionViewportFrame(context);
    OFCookbookConfigureTextRegionContainerForViewportSize(context, viewportFrame.size);
    CGPoint textPoint = OFCookbookTextRegionContainerPointFromPagePoint(context, point);
    NSArray<NSTextSelection *> *selections = [state.textLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:state.textLayoutManager.documentRange.location
                                                                                                                                  anchors:state.dragAnchorSelections
                                                                                                                                modifiers:NSTextSelectionNavigationModifierExtend
                                                                                                                                selecting:YES
                                                                                                                                   bounds:OFCookbookTextRegionContainerInteractionBounds(context)];
    OFCookbookSetTextRegionSelection(context, selections.firstObject);
    *needs_render = true;
}

void OFCookbookTextRegionRightMouseDown(OFCookbookPageContext *context, CGPoint point, CGPoint viewportPoint, bool *needs_render) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookTextRegionViewportFrame(context);
    OFCookbookConfigureTextRegionContainerForViewportSize(context, viewportFrame.size);
    if (!OFCookbookIsPointInTextRegionViewport(context, viewportPoint)) {
        return;
    }

    NSInteger location = OFCookbookTextRegionLocationOffsetAtPoint(context, viewportPoint);
    if (location != NSNotFound &&
        state.hasSelectionRange &&
        NSLocationInRange((NSUInteger)location, state.selectionRange)) {
        NSAttributedString *selectedText = OFCookbookSelectedTextRegionAttributedText(context);
        if (selectedText.length > 0) {
            OFCookbookShowContextMenuForTextRegionAttributedText(context, selectedText, point);
        }
        return;
    }

    NSTextSelection *selection = OFCookbookTextRegionSelectionAtPoint(context, viewportPoint);
    if (!selection) {
        return;
    }
    NSTextSelection *wordSelection = [state.textLayoutManager.textSelectionNavigation textSelectionForSelectionGranularity:NSTextSelectionGranularityWord
                                                                                                             enclosingTextSelection:selection];
    NSAttributedString *selectedText = OFCookbookAttributedTextForTextRegionSelection(context, wordSelection);
    if (selectedText.length == 0 ||
        [selectedText.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        return;
    }

    OFCookbookSetTextRegionSelection(context, wordSelection);
    *needs_render = true;
    OFCookbookShowContextMenuForTextRegionAttributedText(context, selectedText, point);
}

static void OFCookbookTextRegionRenderFrame(OFCookbookPageContext *context) {
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);
    OFCookbookRenderPageFrame(context, OFCookbookRenderTextRegion);
    state.pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
}

static bool OFCookbookTextRegionHandleBrowserMessage(OFCookbookPageContext *context, const OFBrowserMessage *browser_message) {
    if (!browser_message) {
        return false;
    }
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForContext(context);

    switch (browser_message->kind) {
        case OFBrowserMessageInitializeContent: {
            OFHostConfigureFromInitialize(context->host, &browser_message->as.initialize);
            context->current_size = browser_message->as.initialize.has_content_size ? browser_message->as.initialize.content_size : CGSizeMake(800, 600);
            if (browser_message->as.initialize.has_appearance_archive) {
                NSData *data = [NSData dataWithBytesNoCopy:(void *)browser_message->as.initialize.appearance_archive.bytes
                                                     length:browser_message->as.initialize.appearance_archive.length
                                               freeWhenDone:NO];
                NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
                context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            }
            OFCookbookTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = browser_message->as.resize;
            OFCookbookTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)browser_message->as.appearance.appearance_archive.bytes
                                                 length:browser_message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(browser_message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageShutdown:
            OFCookbookRequestShutdown(context->runtime);
            return true;
        case OFBrowserMessageAccessibilitySnapshotRequest: {
            OFBuffer snapshot = {0};
            if (!OFCookbookWriteTextRegionAccessibilitySnapshot(context, &snapshot)) {
                OFAccessibilityNotImplementedSnapshot("Accessibility not implemented", &snapshot);
            }
            OFCookbookSendAccessibilitySnapshotResponse(context, browser_message->as.request.request_id, &snapshot);
            OFBufferFree(&snapshot);
            return true;
        }
        case OFBrowserMessageCopySelectedPasteboardRequest:
            OFCookbookSendCopySelectedPasteboardResponse(context, browser_message->as.request.request_id, state.selectedCopyText);
            return true;
        case OFBrowserMessageMouseMoved: {
            CGPoint point = OFCookbookViewportPointFromRootPoint(context, CGPointMake(browser_message->as.mouse.x, browser_message->as.mouse.y));
            OFHostSetCursor(context->host, OFCookbookTextRegionIsPointOverText(context, point) ? OFCursorTypeIBeam : OFCursorTypeArrow);
            return true;
        }
        case OFBrowserMessageMouseDown: {
            CGPoint point = OFCookbookViewportPointFromRootPoint(context, CGPointMake(browser_message->as.mouse.x, browser_message->as.mouse.y));
            bool needs_render = false;
            OFCookbookTextRegionMouseDown(context, point, browser_message->as.mouse.click_count, &needs_render);
            OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
            if (needs_render) {
                OFCookbookTextRegionRenderFrame(context);
            }
            return true;
        }
        case OFBrowserMessageRightMouseDown: {
            CGPoint root_point = CGPointMake(browser_message->as.mouse.x, browser_message->as.mouse.y);
            CGPoint point = OFCookbookViewportPointFromRootPoint(context, root_point);
            bool needs_render = false;
            OFCookbookTextRegionRightMouseDown(context, root_point, point, &needs_render);
            OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
            if (needs_render) {
                OFCookbookTextRegionRenderFrame(context);
            }
            return true;
        }
        case OFBrowserMessageMouseDragged: {
            CGPoint point = OFCookbookViewportPointFromRootPoint(context, CGPointMake(browser_message->as.mouse.x, browser_message->as.mouse.y));
            bool needs_render = false;
            OFCookbookTextRegionMouseDragged(context, point, &needs_render);
            OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
            if (needs_render) {
                OFCookbookTextRegionRenderFrame(context);
            }
            return true;
        }
        case OFBrowserMessageMouseUp: {
            state.dragAnchorSelections = @[];
            OFHostSetCursor(context->host, OFCursorTypeArrow);
            return true;
        }
        case OFBrowserMessageScrollWheelEvent: {
            CGFloat previous_offset = state.scrollOffset;
            state.scrollOffset = MAX(0, state.scrollOffset - browser_message->as.scroll.delta_y);
            OFCookbookTextRegionRenderFrame(context);
            if (fabs(state.scrollOffset - previous_offset) > 0.0001) {
                OFHostSendAccessibilityTreeChanged(context->host, OFAccessibilityNotificationLayoutChanged);
            }
            return true;
        }
        default:
            return false;
    }
}

static void OFCookbookTextRegionEnterRoute(void *runtime) {
    OFCookbookTextRegionStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookTextRegionState new];
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForRuntime(runtime);
    OFCookbookTextRegionApplyStateToContext(context, state);
    OFCookbookTextRegionRenderFrame(context);
}

static void OFCookbookTextRegionLeaveRoute(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookTextRegionState *state = OFCookbookTextRegionStates()[key];
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    context->page_layer = nil;
    context->page_state = NULL;
    [OFCookbookTextRegionStates() removeObjectForKey:key];
}

static void OFCookbookTextRegionHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookPageContext *context = OFCookbookGetPageContext(runtime);
    OFCookbookTextRegionState *state = OFCookbookTextRegionStateForRuntime(runtime);
    OFCookbookTextRegionApplyStateToContext(context, state);
    OFCookbookTextRegionHandleBrowserMessage(context, message);
}

const OFCookbookPageHandler OFCookbookTextRegionHandler = {
    .handle_message = OFCookbookTextRegionHandleMessage,
    .enter_route = OFCookbookTextRegionEnterRoute,
    .leave_route = OFCookbookTextRegionLeaveRoute,
};
