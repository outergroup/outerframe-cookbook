#import "OFCookbookController.h"

@implementation OFCookbookController (AccessibleTextRegion)

- (void)renderAccessibleText {
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat textInsetX = 28;
    CGFloat textInsetY = 24;
    CGFloat scrollbarWidth = 8;
    CGFloat scrollbarInset = 4;
    CGFloat contentWidth = MAX(self.currentSize.width - pageInset * 2, 240);
    [self addText:@"Accessible Text Region" fontSize:22 weight:NSFontWeightSemibold color:NSColor.labelColor frame:CGRectMake(pageInset, 18, contentWidth, 28)];
    [self addText:@"TextKit 2 layout with scroll, selection, copy, and accessibility." fontSize:14 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor frame:CGRectMake(pageInset, 47, contentWidth, 34)];

    CGRect panelFrame = CGRectMake(pageInset, headerHeight, contentWidth, MAX(self.currentSize.height - headerHeight - pageInset, 180));
    CALayer *background = OFRoundedLayer(NSColor.textBackgroundColor, NSColor.separatorColor, 8);
    background.frame = panelFrame;
    [self.pageLayer addSublayer:background];

    CALayer *viewport = [CALayer layer];
    viewport.geometryFlipped = YES;
    viewport.masksToBounds = YES;
    viewport.frame = CGRectInset(panelFrame, 1, 1);
    [self.pageLayer addSublayer:viewport];

    CGFloat textWidth = MAX(viewport.bounds.size.width - textInsetX * 2 - scrollbarWidth - scrollbarInset, 80);
    self.accessibleTextContainer.size = CGSizeMake(textWidth, 1000000);
    [self.accessibleTextLayoutManager ensureLayoutForRange:self.accessibleTextLayoutManager.documentRange];
    CGFloat contentHeight = MAX(CGRectGetMaxY(self.accessibleTextLayoutManager.usageBoundsForTextContainer) + textInsetY * 2,
                                viewport.bounds.size.height);
    self.scrollOffset = OFClamp(self.scrollOffset, 0, MAX(0, contentHeight - viewport.bounds.size.height));

    CALayer *selectionLayer = [CALayer layer];
    selectionLayer.geometryFlipped = YES;
    selectionLayer.frame = viewport.bounds;
    [viewport addSublayer:selectionLayer];
    [self addAccessibleSelectionLayersInViewport:selectionLayer textInset:CGPointMake(textInsetX, textInsetY)];

    OFTextKitDisplayLayer *textLayer = [OFTextKitDisplayLayer layer];
    textLayer.geometryFlipped = YES;
    textLayer.frame = viewport.bounds;
    textLayer.visibleBounds = viewport.bounds;
    textLayer.textInset = CGPointMake(textInsetX, textInsetY);
    textLayer.scrollOffset = self.scrollOffset;
    textLayer.appearance = self.appearance;
    textLayer.textLayoutManager = self.accessibleTextLayoutManager;
    [viewport addSublayer:textLayer];
    [textLayer setNeedsDisplay];

    [self addScrollbarInLayer:viewport viewportSize:viewport.bounds.size contentHeight:contentHeight offset:self.scrollOffset bottomOrigin:YES];
    [self.hitFrames addObject:[NSValue valueWithRect:panelFrame]];
    [self.hitRoutes addObject:@(self.route)];
}

- (NSAttributedString *)makeAccessibleDocumentText {
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

- (void)addAccessibleSelectionLayersInViewport:(CALayer *)viewport textInset:(CGPoint)textInset {
    if (!self.hasAccessibleSelectionRange || self.accessibleSelectionRange.length == 0) {
        return;
    }
    NSTextRange *textRange = [self accessibleTextRangeForRange:self.accessibleSelectionRange];
    if (!textRange) {
        return;
    }

    CGColorRef selectionColor = [[NSColor selectedTextBackgroundColor] colorWithAlphaComponent:0.75].CGColor;
    [self.accessibleTextLayoutManager enumerateTextSegmentsInRange:textRange
                                                              type:NSTextLayoutManagerSegmentTypeSelection
                                                           options:NSTextLayoutManagerSegmentOptionsNone
                                                        usingBlock:^BOOL(NSTextRange * _Nullable textSegmentRange, CGRect rect, CGFloat baselinePosition, NSTextContainer * _Nonnull textContainer) {
        (void)textSegmentRange;
        (void)baselinePosition;
        (void)textContainer;
        CGRect visibleFrame = CGRectMake(textInset.x + rect.origin.x,
                                         textInset.y + rect.origin.y - self.scrollOffset,
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

- (CGRect)accessibleViewportFrame {
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat contentWidth = MAX(self.currentSize.width - pageInset * 2, 240);
    CGRect panelFrame = CGRectMake(pageInset, headerHeight, contentWidth, MAX(self.currentSize.height - headerHeight - pageInset, 180));
    return CGRectInset(panelFrame, 1, 1);
}

- (CGRect)accessibleTextPanelFrame {
    CGFloat pageInset = 18;
    CGFloat headerHeight = 74;
    CGFloat contentWidth = MAX(self.currentSize.width - pageInset * 2, 240);
    return CGRectMake(pageInset, headerHeight, contentWidth, MAX(self.currentSize.height - headerHeight - pageInset, 180));
}

- (CGRect)accessibleTextAccessibilityFrameFromVisualRootFrame:(CGRect)frame {
    return CGRectMake(CGRectGetMinX(frame),
                      self.currentSize.height - CGRectGetMaxY(frame),
                      frame.size.width,
                      frame.size.height);
}

- (NSString *)accessibleTextStringForRange:(NSTextRange *)range {
    if (!range) {
        return nil;
    }
    id<NSTextLocation> documentStart = self.accessibleTextLayoutManager.documentRange.location;
    NSInteger start = [self.accessibleContentStorage offsetFromLocation:documentStart toLocation:range.location];
    NSInteger end = [self.accessibleContentStorage offsetFromLocation:documentStart toLocation:range.endLocation];
    if (start == NSNotFound || end == NSNotFound) {
        return nil;
    }
    NSInteger location = MAX(0, MIN(start, end));
    NSInteger length = MIN((NSInteger)self.accessibleDocumentText.length - location, labs(end - start));
    if (length <= 0) {
        return nil;
    }
    return [self.accessibleDocumentText attributedSubstringFromRange:NSMakeRange((NSUInteger)location, (NSUInteger)length)].string;
}

- (NSInteger)accessibleTextOffsetFromDocumentStartToLocation:(id<NSTextLocation>)location {
    NSInteger offset = [self.accessibleContentStorage offsetFromLocation:self.accessibleTextLayoutManager.documentRange.location
                                                              toLocation:location];
    return offset == NSNotFound ? 0 : offset;
}

- (bool)writeAccessibleTextAccessibilitySnapshot:(OFBuffer *)outSnapshotData {
    CGRect viewportFrame = [self accessibleViewportFrame];
    [self configureAccessibleTextContainerForViewportSize:viewportFrame.size];
    [self.accessibleTextLayoutManager ensureLayoutForRange:self.accessibleTextLayoutManager.documentRange];

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
    NSString *documentValue = self.accessibleDocumentText.string ?: @"";
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
    CGFloat textWidth = MAX(self.accessibleTextContainer.size.width, 1);
    CGFloat textInsetX = 28;
    CGFloat textInsetY = 24;

    [self.accessibleTextLayoutManager enumerateTextLayoutFragmentsFromLocation:self.accessibleTextLayoutManager.documentRange.location
                                                                       options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout
                                                                    usingBlock:^BOOL(NSTextLayoutFragment * _Nonnull fragment) {
        CGRect fragmentFrame = fragment.layoutFragmentFrame;
        if (CGRectGetMinY(fragmentFrame) > self.scrollOffset + viewportFrame.size.height) {
            return NO;
        }

        CGRect rootFrame = CGRectMake(CGRectGetMinX(viewportFrame) + textInsetX,
                                      CGRectGetMinY(viewportFrame) + textInsetY + CGRectGetMinY(fragmentFrame) - self.scrollOffset,
                                      textWidth,
                                      MAX(fragmentFrame.size.height, 1));
        if (!CGRectIntersectsRect(rootFrame, viewportBoundsInRoot)) {
            return YES;
        }

        NSString *fragmentText = [self accessibleTextStringForRange:fragment.rangeInElement];
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

        NSInteger startOffset = [self accessibleTextOffsetFromDocumentStartToLocation:fragment.rangeInElement.location];
        NSInteger safeOffset = MAX(0, MIN(startOffset, (NSInteger)UINT32_MAX - 1000));
        CGRect visibleFrame = [self accessibleTextAccessibilityFrameFromVisualRootFrame:CGRectIntersection(rootFrame, viewportBoundsInRoot)];
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
            .frame = [self accessibleTextAccessibilityFrameFromVisualRootFrame:CGRectMake(18, 18, MAX(self.currentSize.width - 36, 240), 28)],
            .label = titleCString,
            .enabled = true,
        },
        {
            .identifier = 2,
            .role = OFAccessibilityRoleContainer,
            .frame = [self accessibleTextAccessibilityFrameFromVisualRootFrame:[self accessibleTextPanelFrame]],
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
        .frame = CGRectMake(0, 0, self.currentSize.width, self.currentSize.height),
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

- (CGFloat)accessibleContentHeightForViewportHeight:(CGFloat)viewportHeight {
    [self.accessibleTextLayoutManager ensureLayoutForRange:self.accessibleTextLayoutManager.documentRange];
    return MAX(CGRectGetMaxY(self.accessibleTextLayoutManager.usageBoundsForTextContainer) + 24 * 2, viewportHeight);
}

- (void)configureAccessibleTextContainerForViewportSize:(CGSize)viewportSize {
    CGFloat textInsetX = 28;
    CGFloat scrollbarWidth = 8;
    CGFloat scrollbarInset = 4;
    CGFloat textWidth = MAX(viewportSize.width - textInsetX * 2 - scrollbarWidth - scrollbarInset, 80);
    if (fabs(self.accessibleTextContainer.size.width - textWidth) > 0.5) {
        self.accessibleTextContainer.size = CGSizeMake(textWidth, 1000000);
        [self.accessibleTextLayoutManager ensureLayoutForRange:self.accessibleTextLayoutManager.documentRange];
    }
}

- (CGPoint)accessibleTextContainerPointFromPagePoint:(CGPoint)point {
    CGRect viewportFrame = [self accessibleViewportFrame];
    return CGPointMake(point.x - CGRectGetMinX(viewportFrame) - 28,
                       point.y - CGRectGetMinY(viewportFrame) + self.scrollOffset - 24);
}

- (CGRect)accessibleTextContainerInteractionBounds {
    CGFloat contentHeight = [self accessibleContentHeightForViewportHeight:[self accessibleViewportFrame].size.height];
    return CGRectMake(0, 0, MAX(self.accessibleTextContainer.size.width, 1), MAX(contentHeight - 24 * 2, self.accessibleTextContainer.size.height));
}

- (BOOL)isPointInAccessibleTextViewport:(CGPoint)point {
    return CGRectContainsPoint([self accessibleViewportFrame], point);
}

- (BOOL)isPointOverAccessibleText:(CGPoint)point {
    CGRect viewportFrame = [self accessibleViewportFrame];
    if (!CGRectContainsPoint(viewportFrame, point)) {
        return NO;
    }
    [self configureAccessibleTextContainerForViewportSize:viewportFrame.size];
    CGPoint textPoint = [self accessibleTextContainerPointFromPagePoint:point];
    __block BOOL found = NO;
    [self.accessibleTextLayoutManager enumerateTextSegmentsInRange:self.accessibleTextLayoutManager.documentRange
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

- (void)setAccessibleTextSelection:(NSTextSelection *)selection {
    self.accessibleTextLayoutManager.textSelections = selection ? @[selection] : @[];
    NSRange range = [self accessibleRangeForTextSelection:selection];
    self.hasAccessibleSelectionRange = range.length > 0;
    self.accessibleSelectionRange = range;
    if (range.length > 0 && NSMaxRange(range) <= self.accessibleDocumentText.length) {
        self.selectedCopyText = [self.accessibleDocumentText attributedSubstringFromRange:range].string;
    } else {
        self.selectedCopyText = nil;
    }
    [self updatePasteboardCapabilities];
    OFHostSendAccessibilityTreeChanged(self.host, OFAccessibilityNotificationSelectedChildrenChanged);
}

- (NSRange)accessibleRangeForTextSelection:(NSTextSelection *)selection {
    NSTextRange *textRange = selection.textRanges.firstObject;
    if (!textRange) {
        return NSMakeRange(0, 0);
    }
    id<NSTextLocation> documentStart = self.accessibleTextLayoutManager.documentRange.location;
    NSInteger start = [self.accessibleContentStorage offsetFromLocation:documentStart toLocation:textRange.location];
    NSInteger end = [self.accessibleContentStorage offsetFromLocation:documentStart toLocation:textRange.endLocation];
    if (start == NSNotFound || end == NSNotFound) {
        return NSMakeRange(0, 0);
    }
    NSInteger location = MAX(0, MIN(start, end));
    NSInteger length = MIN((NSInteger)self.accessibleDocumentText.length - location, labs(end - start));
    if (length <= 0) {
        return NSMakeRange(0, 0);
    }
    return NSMakeRange((NSUInteger)location, (NSUInteger)length);
}

- (NSTextRange *)accessibleTextRangeForRange:(NSRange)range {
    if (range.length == 0 || NSMaxRange(range) > self.accessibleDocumentText.length) {
        return nil;
    }
    id<NSTextLocation> documentStart = self.accessibleTextLayoutManager.documentRange.location;
    id<NSTextLocation> start = [self.accessibleContentStorage locationFromLocation:documentStart withOffset:(NSInteger)range.location];
    id<NSTextLocation> end = [self.accessibleContentStorage locationFromLocation:documentStart withOffset:(NSInteger)NSMaxRange(range)];
    if (!start || !end) {
        return nil;
    }
    return [[NSTextRange alloc] initWithLocation:start endLocation:end];
}

- (NSTextSelection *)accessibleTextSelectionAtPoint:(CGPoint)point {
    CGPoint textPoint = [self accessibleTextContainerPointFromPagePoint:point];
    NSArray<NSTextSelection *> *selections = [self.accessibleTextLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:self.accessibleTextLayoutManager.documentRange.location
                                                                                                                                  anchors:@[]
                                                                                                                                modifiers:0
                                                                                                                                selecting:NO
                                                                                                                                   bounds:[self accessibleTextContainerInteractionBounds]];
    return selections.firstObject;
}

- (NSAttributedString *)attributedTextForAccessibleSelection:(NSTextSelection *)selection {
    NSRange range = [self accessibleRangeForTextSelection:selection];
    if (range.length == 0 || NSMaxRange(range) > self.accessibleDocumentText.length) {
        return nil;
    }
    return [self.accessibleDocumentText attributedSubstringFromRange:range];
}

- (NSAttributedString *)selectedAccessibleAttributedText {
    if (!self.hasAccessibleSelectionRange ||
        self.accessibleSelectionRange.length == 0 ||
        NSMaxRange(self.accessibleSelectionRange) > self.accessibleDocumentText.length) {
        return nil;
    }
    return [self.accessibleDocumentText attributedSubstringFromRange:self.accessibleSelectionRange];
}

- (NSInteger)accessibleTextLocationOffsetAtPoint:(CGPoint)point {
    NSTextSelection *selection = [self accessibleTextSelectionAtPoint:point];
    NSTextRange *range = selection.textRanges.firstObject;
    if (!range) {
        return NSNotFound;
    }
    return [self.accessibleContentStorage offsetFromLocation:self.accessibleTextLayoutManager.documentRange.location
                                                  toLocation:range.location];
}

- (void)showContextMenuForAccessibleAttributedText:(NSAttributedString *)text atPoint:(CGPoint)point {
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
    OFHostShowContextMenu(self.host, rtfView, point.x, point.y);
}

- (NSTextSelection *)accessibleTextLayoutFragmentSelectionAtTextPoint:(CGPoint)textPoint {
    __block NSTextLayoutFragment *matchingFragment = nil;
    [self.accessibleTextLayoutManager enumerateTextLayoutFragmentsFromLocation:self.accessibleTextLayoutManager.documentRange.location
                                                                       options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout
                                                                    usingBlock:^BOOL(NSTextLayoutFragment * _Nonnull fragment) {
        CGRect frame = fragment.layoutFragmentFrame;
        if (CGRectGetMinY(frame) > textPoint.y) {
            return NO;
        }
        CGRect paragraphHitFrame = CGRectMake(0, CGRectGetMinY(frame), self.accessibleTextContainer.size.width, MAX(frame.size.height, 1));
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

- (void)accessibleMouseDownAtPoint:(CGPoint)point clickCount:(uint32_t)clickCount {
    CGRect viewportFrame = [self accessibleViewportFrame];
    [self configureAccessibleTextContainerForViewportSize:viewportFrame.size];
    if (![self isPointInAccessibleTextViewport:point]) {
        self.accessibleDragAnchorSelections = @[];
        [self setAccessibleTextSelection:nil];
        [self renderCurrentRoute];
        return;
    }

    CGPoint textPoint = [self accessibleTextContainerPointFromPagePoint:point];
    NSArray<NSTextSelection *> *selections = [self.accessibleTextLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:self.accessibleTextLayoutManager.documentRange.location
                                                                                                                                  anchors:@[]
                                                                                                                                modifiers:0
                                                                                                                                selecting:NO
                                                                                                                                   bounds:[self accessibleTextContainerInteractionBounds]];
    self.accessibleDragAnchorSelections = selections ?: @[];
    if (clickCount >= 3) {
        NSTextSelection *paragraphSelection = [self accessibleTextLayoutFragmentSelectionAtTextPoint:textPoint];
        self.accessibleDragAnchorSelections = paragraphSelection ? @[paragraphSelection] : @[];
        [self setAccessibleTextSelection:paragraphSelection];
    } else if (clickCount == 2 && selections.firstObject) {
        NSTextSelection *wordSelection = [self.accessibleTextLayoutManager.textSelectionNavigation textSelectionForSelectionGranularity:NSTextSelectionGranularityWord
                                                                                                                 enclosingTextSelection:selections.firstObject];
        [self setAccessibleTextSelection:wordSelection];
    } else {
        [self setAccessibleTextSelection:nil];
    }
    [self renderCurrentRoute];
}

- (void)accessibleMouseDraggedToPoint:(CGPoint)point {
    if (self.accessibleDragAnchorSelections.count == 0) {
        return;
    }
    CGRect viewportFrame = [self accessibleViewportFrame];
    [self configureAccessibleTextContainerForViewportSize:viewportFrame.size];
    CGPoint textPoint = [self accessibleTextContainerPointFromPagePoint:point];
    NSArray<NSTextSelection *> *selections = [self.accessibleTextLayoutManager.textSelectionNavigation textSelectionsInteractingAtPoint:textPoint
                                                                                                                    inContainerAtLocation:self.accessibleTextLayoutManager.documentRange.location
                                                                                                                                  anchors:self.accessibleDragAnchorSelections
                                                                                                                                modifiers:NSTextSelectionNavigationModifierExtend
                                                                                                                                selecting:YES
                                                                                                                                   bounds:[self accessibleTextContainerInteractionBounds]];
    [self setAccessibleTextSelection:selections.firstObject];
    [self renderCurrentRoute];
}

- (void)rightMouseDownAt:(CGPoint)point clickCount:(uint32_t)clickCount {
    (void)clickCount;
    if (self.route != OFCookbookRouteAccessibleText) {
        return;
    }

    CGPoint viewportPoint = [self viewportPointFromRootPoint:point];
    CGRect viewportFrame = [self accessibleViewportFrame];
    [self configureAccessibleTextContainerForViewportSize:viewportFrame.size];
    if (![self isPointInAccessibleTextViewport:viewportPoint]) {
        return;
    }

    NSInteger location = [self accessibleTextLocationOffsetAtPoint:viewportPoint];
    if (location != NSNotFound &&
        self.hasAccessibleSelectionRange &&
        NSLocationInRange((NSUInteger)location, self.accessibleSelectionRange)) {
        NSAttributedString *selectedText = [self selectedAccessibleAttributedText];
        if (selectedText.length > 0) {
            [self showContextMenuForAccessibleAttributedText:selectedText atPoint:point];
        }
        return;
    }

    NSTextSelection *selection = [self accessibleTextSelectionAtPoint:viewportPoint];
    if (!selection) {
        return;
    }
    NSTextSelection *wordSelection = [self.accessibleTextLayoutManager.textSelectionNavigation textSelectionForSelectionGranularity:NSTextSelectionGranularityWord
                                                                                                             enclosingTextSelection:selection];
    NSAttributedString *selectedText = [self attributedTextForAccessibleSelection:wordSelection];
    if (selectedText.length == 0 ||
        [selectedText.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        return;
    }

    [self setAccessibleTextSelection:wordSelection];
    [self renderCurrentRoute];
    [self showContextMenuForAccessibleAttributedText:selectedText atPoint:point];
}

@end
