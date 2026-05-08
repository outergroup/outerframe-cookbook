#import "OFCookbookController.h"

static void OFCookbookAddAccessibleSelectionLayersInViewport(OFCookbookRecipeContext *context, CALayer *viewport, CGPoint textInset);
static CGRect OFCookbookAccessibleViewportFrame(OFCookbookRecipeContext *context);
static CGRect OFCookbookAccessibleTextPanelFrame(OFCookbookRecipeContext *context);
static CGRect OFCookbookAccessibleTextAccessibilityFrameFromVisualRootFrame(OFCookbookRecipeContext *context, CGRect frame);
static NSString *OFCookbookAccessibleTextStringForRange(OFCookbookRecipeContext *context, NSTextRange *range);
static NSInteger OFCookbookAccessibleTextOffsetFromDocumentStartToLocation(OFCookbookRecipeContext *context, id<NSTextLocation> location);
static CGFloat OFCookbookAccessibleContentHeightForViewportHeight(OFCookbookRecipeContext *context, CGFloat viewportHeight);
static void OFCookbookConfigureAccessibleTextContainerForViewportSize(OFCookbookRecipeContext *context, CGSize viewportSize);
static CGPoint OFCookbookAccessibleTextContainerPointFromPagePoint(OFCookbookRecipeContext *context, CGPoint point);
static CGRect OFCookbookAccessibleTextContainerInteractionBounds(OFCookbookRecipeContext *context);
static bool OFCookbookIsPointInAccessibleTextViewport(OFCookbookRecipeContext *context, CGPoint point);
static void OFCookbookSetAccessibleTextSelection(OFCookbookRecipeContext *context, NSTextSelection *selection);
static NSRange OFCookbookAccessibleRangeForTextSelection(OFCookbookRecipeContext *context, NSTextSelection *selection);
static NSTextRange *OFCookbookAccessibleTextRangeForRange(OFCookbookRecipeContext *context, NSRange range);
static NSTextSelection *OFCookbookAccessibleTextSelectionAtPoint(OFCookbookRecipeContext *context, CGPoint point);
static NSAttributedString *OFCookbookAttributedTextForAccessibleSelection(OFCookbookRecipeContext *context, NSTextSelection *selection);
static NSAttributedString *OFCookbookSelectedAccessibleAttributedText(OFCookbookRecipeContext *context);
static NSInteger OFCookbookAccessibleTextLocationOffsetAtPoint(OFCookbookRecipeContext *context, CGPoint point);
static void OFCookbookShowContextMenuForAccessibleAttributedText(OFCookbookRecipeContext *context, NSAttributedString *text, CGPoint point);
static NSTextSelection *OFCookbookAccessibleTextLayoutFragmentSelectionAtTextPoint(OFCookbookRecipeContext *context, CGPoint textPoint);
static void OFCookbookAccessibleTextRegionRenderFrame(OFCookbookRecipeContext *context);
static bool OFCookbookAccessibleTextRegionHandleBrowserMessage(OFCookbookRecipeContext *context, const OFBrowserMessage *browser_message);

@interface OFCookbookAccessibleTextRegionState : NSObject
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

@implementation OFCookbookAccessibleTextRegionState
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
        _documentText = OFCookbookMakeAccessibleDocumentText();
        _contentStorage.attributedString = _documentText;
        _dragAnchorSelections = @[];
        _accessibilityLabels = [NSMutableArray array];
        _accessibilityFrames = [NSMutableArray array];
        _accessibilityRoles = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableDictionary<NSValue *, OFCookbookAccessibleTextRegionState *> *OFCookbookAccessibleTextRegionStates(void) {
    static NSMutableDictionary<NSValue *, OFCookbookAccessibleTextRegionState *> *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        states = [NSMutableDictionary dictionary];
    });
    return states;
}

static OFCookbookAccessibleTextRegionState *OFCookbookAccessibleTextRegionStateForRuntime(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStates()[key];
    if (!state) {
        state = [OFCookbookAccessibleTextRegionState new];
        OFCookbookAccessibleTextRegionStates()[key] = state;
    }
    return state;
}

static OFCookbookAccessibleTextRegionState *OFCookbookAccessibleTextRegionStateForContext(OFCookbookRecipeContext *context) {
    return (__bridge OFCookbookAccessibleTextRegionState *)context->recipe_state;
}

static void OFCookbookAccessibleTextRegionApplyStateToContext(OFCookbookRecipeContext *context, OFCookbookAccessibleTextRegionState *state) {
    context->recipe_state = (__bridge void *)state;
    context->page_layer = state.pageLayer;
    context->accessibility_labels = state.accessibilityLabels;
    context->accessibility_frames = state.accessibilityFrames;
    context->accessibility_roles = state.accessibilityRoles;
}

void OFCookbookRenderAccessibleTextRegion(OFCookbookRecipeContext *context) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat textInsetX = 28;
    CGFloat textInsetY = 24;
    CGFloat scrollbarWidth = 8;
    CGFloat scrollbarInset = 4;
    CGFloat contentWidth = MAX(context->current_size.width - pageInset * 2, 240);
    OFCookbookAddText(context, @"Accessible Text Region", 22, NSFontWeightSemibold, NSColor.labelColor, CGRectMake(pageInset, 18, contentWidth, 28));
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
    OFCookbookAddAccessibleSelectionLayersInViewport(context, selectionLayer, CGPointMake(textInsetX, textInsetY));

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

NSAttributedString *OFCookbookMakeAccessibleDocumentText(void) {
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
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"Lorem Ipsum, Accessible and Copyable\n"
                                                                   attributes:@{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: NSColor.labelColor,
        NSParagraphStyleAttributeName: titleParagraph,
    }]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"This recipe keeps text layout in TextKit 2 while the surrounding surface stays layer-backed. Drag through the paragraphs to highlight text, then copy it with the browser or system copy command.\n"
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

static void OFCookbookAddAccessibleSelectionLayersInViewport(OFCookbookRecipeContext *context, CALayer *viewport, CGPoint textInset) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    if (!state.hasSelectionRange || state.selectionRange.length == 0) {
        return;
    }
    NSTextRange *textRange = OFCookbookAccessibleTextRangeForRange(context, state.selectionRange);
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

static CGRect OFCookbookAccessibleViewportFrame(OFCookbookRecipeContext *context) {
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat contentWidth = MAX(context->current_size.width - pageInset * 2, 240);
    CGRect panelFrame = CGRectMake(pageInset, headerHeight, contentWidth, MAX(context->current_size.height - headerHeight - pageInset, 180));
    return CGRectInset(panelFrame, 1, 1);
}

static CGRect OFCookbookAccessibleTextPanelFrame(OFCookbookRecipeContext *context) {
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat contentWidth = MAX(context->current_size.width - pageInset * 2, 240);
    return CGRectMake(pageInset, headerHeight, contentWidth, MAX(context->current_size.height - headerHeight - pageInset, 180));
}

static CGRect OFCookbookAccessibleTextAccessibilityFrameFromVisualRootFrame(OFCookbookRecipeContext *context, CGRect frame) {
    return CGRectMake(CGRectGetMinX(frame),
                      context->current_size.height - CGRectGetMaxY(frame),
                      frame.size.width,
                      frame.size.height);
}

static NSString *OFCookbookAccessibleTextStringForRange(OFCookbookRecipeContext *context, NSTextRange *range) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
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

static NSInteger OFCookbookAccessibleTextOffsetFromDocumentStartToLocation(OFCookbookRecipeContext *context, id<NSTextLocation> location) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    NSInteger offset = [state.contentStorage offsetFromLocation:state.textLayoutManager.documentRange.location
                                                              toLocation:location];
    return offset == NSNotFound ? 0 : offset;
}

bool OFCookbookWriteAccessibleTextAccessibilitySnapshot(OFCookbookRecipeContext *context, OFBuffer *outSnapshotData) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookAccessibleViewportFrame(context);
    OFCookbookConfigureAccessibleTextContainerForViewportSize(context, viewportFrame.size);
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
    NSString *title = @"Accessible Text Region";
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

        NSString *fragmentText = OFCookbookAccessibleTextStringForRange(context, fragment.rangeInElement);
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

        NSInteger startOffset = OFCookbookAccessibleTextOffsetFromDocumentStartToLocation(context, fragment.rangeInElement.location);
        NSInteger safeOffset = MAX(0, MIN(startOffset, (NSInteger)UINT32_MAX - 1000));
        CGRect visibleFrame = OFCookbookAccessibleTextAccessibilityFrameFromVisualRootFrame(context, CGRectIntersection(rootFrame, viewportBoundsInRoot));
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
            .frame = OFCookbookAccessibleTextAccessibilityFrameFromVisualRootFrame(context, CGRectMake(18, 18, MAX(context->current_size.width - 36, 240), 28)),
            .label = titleCString,
            .enabled = true,
        },
        {
            .identifier = 2,
            .role = OFAccessibilityRoleContainer,
            .frame = OFCookbookAccessibleTextAccessibilityFrameFromVisualRootFrame(context, OFCookbookAccessibleTextPanelFrame(context)),
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

static CGFloat OFCookbookAccessibleContentHeightForViewportHeight(OFCookbookRecipeContext *context, CGFloat viewportHeight) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    [state.textLayoutManager ensureLayoutForRange:state.textLayoutManager.documentRange];
    return MAX(CGRectGetMaxY(state.textLayoutManager.usageBoundsForTextContainer) + 24 * 2, viewportHeight);
}

static void OFCookbookConfigureAccessibleTextContainerForViewportSize(OFCookbookRecipeContext *context, CGSize viewportSize) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGFloat textInsetX = 28;
    CGFloat scrollbarWidth = 8;
    CGFloat scrollbarInset = 4;
    CGFloat textWidth = MAX(viewportSize.width - textInsetX * 2 - scrollbarWidth - scrollbarInset, 80);
    if (fabs(state.textContainer.size.width - textWidth) > 0.5) {
        state.textContainer.size = CGSizeMake(textWidth, 1000000);
        [state.textLayoutManager ensureLayoutForRange:state.textLayoutManager.documentRange];
    }
}

static CGPoint OFCookbookAccessibleTextContainerPointFromPagePoint(OFCookbookRecipeContext *context, CGPoint point) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookAccessibleViewportFrame(context);
    return CGPointMake(point.x - CGRectGetMinX(viewportFrame) - 28,
                       point.y - CGRectGetMinY(viewportFrame) + state.scrollOffset - 24);
}

static CGRect OFCookbookAccessibleTextContainerInteractionBounds(OFCookbookRecipeContext *context) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGFloat contentHeight = OFCookbookAccessibleContentHeightForViewportHeight(context, OFCookbookAccessibleViewportFrame(context).size.height);
    return CGRectMake(0, 0, MAX(state.textContainer.size.width, 1), MAX(contentHeight - 24 * 2, state.textContainer.size.height));
}

static bool OFCookbookIsPointInAccessibleTextViewport(OFCookbookRecipeContext *context, CGPoint point) {
    return CGRectContainsPoint(OFCookbookAccessibleViewportFrame(context), point);
}

bool OFCookbookAccessibleTextIsPointOverText(OFCookbookRecipeContext *context, CGPoint point) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookAccessibleViewportFrame(context);
    if (!CGRectContainsPoint(viewportFrame, point)) {
        return NO;
    }
    OFCookbookConfigureAccessibleTextContainerForViewportSize(context, viewportFrame.size);
    CGPoint textPoint = OFCookbookAccessibleTextContainerPointFromPagePoint(context, point);
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

static void OFCookbookSetAccessibleTextSelection(OFCookbookRecipeContext *context, NSTextSelection *selection) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    state.textLayoutManager.textSelections = selection ? @[selection] : @[];
    NSRange range = OFCookbookAccessibleRangeForTextSelection(context, selection);
    state.hasSelectionRange = range.length > 0;
    state.selectionRange = range;
    if (range.length > 0 && NSMaxRange(range) <= state.documentText.length) {
        state.selectedCopyText = [state.documentText attributedSubstringFromRange:range].string;
    } else {
        state.selectedCopyText = nil;
    }

    OFHostSendAccessibilityTreeChanged(context->host, OFAccessibilityNotificationSelectedChildrenChanged);
}

static NSRange OFCookbookAccessibleRangeForTextSelection(OFCookbookRecipeContext *context, NSTextSelection *selection) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
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

static NSTextRange *OFCookbookAccessibleTextRangeForRange(OFCookbookRecipeContext *context, NSRange range) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
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

static NSTextSelection *OFCookbookAccessibleTextSelectionAtPoint(OFCookbookRecipeContext *context, CGPoint point) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGPoint textPoint = OFCookbookAccessibleTextContainerPointFromPagePoint(context, point);
    NSArray<NSTextSelection *> *selections = [state.textLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:state.textLayoutManager.documentRange.location
                                                                                                                                  anchors:@[]
                                                                                                                                modifiers:0
                                                                                                                                selecting:NO
                                                                                                                                   bounds:OFCookbookAccessibleTextContainerInteractionBounds(context)];
    return selections.firstObject;
}

static NSAttributedString *OFCookbookAttributedTextForAccessibleSelection(OFCookbookRecipeContext *context, NSTextSelection *selection) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    NSRange range = OFCookbookAccessibleRangeForTextSelection(context, selection);
    if (range.length == 0 || NSMaxRange(range) > state.documentText.length) {
        return nil;
    }
    return [state.documentText attributedSubstringFromRange:range];
}

static NSAttributedString *OFCookbookSelectedAccessibleAttributedText(OFCookbookRecipeContext *context) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    if (!state.hasSelectionRange ||
        state.selectionRange.length == 0 ||
        NSMaxRange(state.selectionRange) > state.documentText.length) {
        return nil;
    }
    return [state.documentText attributedSubstringFromRange:state.selectionRange];
}

static NSInteger OFCookbookAccessibleTextLocationOffsetAtPoint(OFCookbookRecipeContext *context, CGPoint point) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    NSTextSelection *selection = OFCookbookAccessibleTextSelectionAtPoint(context, point);
    NSTextRange *range = selection.textRanges.firstObject;
    if (!range) {
        return NSNotFound;
    }
    return [state.contentStorage offsetFromLocation:state.textLayoutManager.documentRange.location
                                                  toLocation:range.location];
}

static void OFCookbookShowContextMenuForAccessibleAttributedText(OFCookbookRecipeContext *context, NSAttributedString *text, CGPoint point) {
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

static NSTextSelection *OFCookbookAccessibleTextLayoutFragmentSelectionAtTextPoint(OFCookbookRecipeContext *context, CGPoint textPoint) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
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

void OFCookbookAccessibleTextMouseDown(OFCookbookRecipeContext *context, CGPoint point, uint32_t clickCount, bool *needs_render) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookAccessibleViewportFrame(context);
    OFCookbookConfigureAccessibleTextContainerForViewportSize(context, viewportFrame.size);
    if (!OFCookbookIsPointInAccessibleTextViewport(context, point)) {
        state.dragAnchorSelections = @[];
        OFCookbookSetAccessibleTextSelection(context, nil);
        *needs_render = true;
        return;
    }

    CGPoint textPoint = OFCookbookAccessibleTextContainerPointFromPagePoint(context, point);
    NSArray<NSTextSelection *> *selections = [state.textLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:state.textLayoutManager.documentRange.location
                                                                                                                                  anchors:@[]
                                                                                                                                modifiers:0
                                                                                                                                selecting:NO
                                                                                                                                   bounds:OFCookbookAccessibleTextContainerInteractionBounds(context)];
    state.dragAnchorSelections = selections ?: @[];
    if (clickCount >= 3) {
        NSTextSelection *paragraphSelection = OFCookbookAccessibleTextLayoutFragmentSelectionAtTextPoint(context, textPoint);
        state.dragAnchorSelections = paragraphSelection ? @[paragraphSelection] : @[];
        OFCookbookSetAccessibleTextSelection(context, paragraphSelection);
    } else if (clickCount == 2 && selections.firstObject) {
        NSTextSelection *wordSelection = [state.textLayoutManager.textSelectionNavigation textSelectionForSelectionGranularity:NSTextSelectionGranularityWord
                                                                                                                 enclosingTextSelection:selections.firstObject];
        OFCookbookSetAccessibleTextSelection(context, wordSelection);
    } else {
        OFCookbookSetAccessibleTextSelection(context, nil);
    }
    *needs_render = true;
}

void OFCookbookAccessibleTextMouseDragged(OFCookbookRecipeContext *context, CGPoint point, bool *needs_render) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    if (state.dragAnchorSelections.count == 0) {
        return;
    }
    CGRect viewportFrame = OFCookbookAccessibleViewportFrame(context);
    OFCookbookConfigureAccessibleTextContainerForViewportSize(context, viewportFrame.size);
    CGPoint textPoint = OFCookbookAccessibleTextContainerPointFromPagePoint(context, point);
    NSArray<NSTextSelection *> *selections = [state.textLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:state.textLayoutManager.documentRange.location
                                                                                                                                  anchors:state.dragAnchorSelections
                                                                                                                                modifiers:NSTextSelectionNavigationModifierExtend
                                                                                                                                selecting:YES
                                                                                                                                   bounds:OFCookbookAccessibleTextContainerInteractionBounds(context)];
    OFCookbookSetAccessibleTextSelection(context, selections.firstObject);
    *needs_render = true;
}

void OFCookbookAccessibleTextRightMouseDown(OFCookbookRecipeContext *context, CGPoint point, CGPoint viewportPoint, bool *needs_render) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    CGRect viewportFrame = OFCookbookAccessibleViewportFrame(context);
    OFCookbookConfigureAccessibleTextContainerForViewportSize(context, viewportFrame.size);
    if (!OFCookbookIsPointInAccessibleTextViewport(context, viewportPoint)) {
        return;
    }

    NSInteger location = OFCookbookAccessibleTextLocationOffsetAtPoint(context, viewportPoint);
    if (location != NSNotFound &&
        state.hasSelectionRange &&
        NSLocationInRange((NSUInteger)location, state.selectionRange)) {
        NSAttributedString *selectedText = OFCookbookSelectedAccessibleAttributedText(context);
        if (selectedText.length > 0) {
            OFCookbookShowContextMenuForAccessibleAttributedText(context, selectedText, point);
        }
        return;
    }

    NSTextSelection *selection = OFCookbookAccessibleTextSelectionAtPoint(context, viewportPoint);
    if (!selection) {
        return;
    }
    NSTextSelection *wordSelection = [state.textLayoutManager.textSelectionNavigation textSelectionForSelectionGranularity:NSTextSelectionGranularityWord
                                                                                                             enclosingTextSelection:selection];
    NSAttributedString *selectedText = OFCookbookAttributedTextForAccessibleSelection(context, wordSelection);
    if (selectedText.length == 0 ||
        [selectedText.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        return;
    }

    OFCookbookSetAccessibleTextSelection(context, wordSelection);
    *needs_render = true;
    OFCookbookShowContextMenuForAccessibleAttributedText(context, selectedText, point);
}

static void OFCookbookAccessibleTextRegionRenderFrame(OFCookbookRecipeContext *context) {
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);
    OFCookbookRenderRecipeFrame(context, OFCookbookRenderAccessibleTextRegion);
    state.pageLayer = context->page_layer;
    OFCookbookUpdateRoutePageMetadata(context);
    OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
}

static bool OFCookbookAccessibleTextRegionHandleBrowserMessage(OFCookbookRecipeContext *context, const OFBrowserMessage *browser_message) {
    if (!browser_message) {
        return false;
    }
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForContext(context);

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
            OFCookbookAccessibleTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageResizeContent: {
            context->current_size = browser_message->as.resize;
            OFCookbookAccessibleTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageSystemAppearanceUpdate: {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)browser_message->as.appearance.appearance_archive.bytes
                                                 length:browser_message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            context->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
            OFCookbookAccessibleTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageHistoryTraversal: {
            OFCookbookRoute route = OFCookbookRouteFromURLStringView(browser_message->as.history.url);
            if (route != context->route) {
                OFCookbookSwitchToRoute(context, route);
                return true;
            }
            OFCookbookAccessibleTextRegionRenderFrame(context);
            return true;
        }
        case OFBrowserMessageShutdown:
            OFCookbookRequestShutdown(context->runtime);
            return true;
        case OFBrowserMessageAccessibilitySnapshotRequest: {
            OFBuffer snapshot = {0};
            if (!OFCookbookWriteAccessibleTextAccessibilitySnapshot(context, &snapshot)) {
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
            OFHostSetCursor(context->host, OFCookbookAccessibleTextIsPointOverText(context, point) ? OFCursorTypeIBeam : OFCursorTypeArrow);
            return true;
        }
        case OFBrowserMessageMouseDown: {
            CGPoint point = OFCookbookViewportPointFromRootPoint(context, CGPointMake(browser_message->as.mouse.x, browser_message->as.mouse.y));
            bool needs_render = false;
            OFCookbookAccessibleTextMouseDown(context, point, browser_message->as.mouse.click_count, &needs_render);
            OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
            if (needs_render) {
                OFCookbookAccessibleTextRegionRenderFrame(context);
            }
            return true;
        }
        case OFBrowserMessageRightMouseDown: {
            CGPoint root_point = CGPointMake(browser_message->as.mouse.x, browser_message->as.mouse.y);
            CGPoint point = OFCookbookViewportPointFromRootPoint(context, root_point);
            bool needs_render = false;
            OFCookbookAccessibleTextRightMouseDown(context, root_point, point, &needs_render);
            OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
            if (needs_render) {
                OFCookbookAccessibleTextRegionRenderFrame(context);
            }
            return true;
        }
        case OFBrowserMessageMouseDragged: {
            CGPoint point = OFCookbookViewportPointFromRootPoint(context, CGPointMake(browser_message->as.mouse.x, browser_message->as.mouse.y));
            bool needs_render = false;
            OFCookbookAccessibleTextMouseDragged(context, point, &needs_render);
            OFCookbookUpdatePasteboardCapabilities(context, state.selectedCopyText);
            if (needs_render) {
                OFCookbookAccessibleTextRegionRenderFrame(context);
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
            OFCookbookAccessibleTextRegionRenderFrame(context);
            if (fabs(state.scrollOffset - previous_offset) > 0.0001) {
                OFHostSendAccessibilityTreeChanged(context->host, OFAccessibilityNotificationLayoutChanged);
            }
            return true;
        }
        default:
            return false;
    }
}

static void OFCookbookAccessibleTextRegionEnterRoute(void *runtime) {
    OFCookbookAccessibleTextRegionStates()[[NSValue valueWithPointer:runtime]] = [OFCookbookAccessibleTextRegionState new];
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForRuntime(runtime);
    OFCookbookAccessibleTextRegionApplyStateToContext(context, state);
    OFCookbookAccessibleTextRegionRenderFrame(context);
}

static void OFCookbookAccessibleTextRegionLeaveRoute(void *runtime) {
    NSValue *key = [NSValue valueWithPointer:runtime];
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStates()[key];
    [state.pageLayer removeFromSuperlayer];
    state.pageLayer = nil;
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    context->page_layer = nil;
    context->recipe_state = NULL;
    [OFCookbookAccessibleTextRegionStates() removeObjectForKey:key];
}

static void OFCookbookAccessibleTextRegionHandleMessage(OFHost *host, const OFBrowserMessage *message, void *runtime) {
    (void)host;
    OFCookbookRecipeContext *context = OFCookbookGetRecipeContext(runtime);
    OFCookbookAccessibleTextRegionState *state = OFCookbookAccessibleTextRegionStateForRuntime(runtime);
    OFCookbookAccessibleTextRegionApplyStateToContext(context, state);
    OFCookbookAccessibleTextRegionHandleBrowserMessage(context, message);
}

const OFCookbookRecipeHandler OFCookbookAccessibleTextRegionHandler = {
    .handle_message = OFCookbookAccessibleTextRegionHandleMessage,
    .enter_route = OFCookbookAccessibleTextRegionEnterRoute,
    .leave_route = OFCookbookAccessibleTextRegionLeaveRoute,
};
