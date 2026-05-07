#import "OFCookbookController.h"

static void OFCookbookHandleMessage(OFHost *host, const OFBrowserMessage *message, void *context);
static void OFCookbookHandleDisconnect(OFHost *host, void *context);
static bool OFCookbookWriteAccessibilitySnapshot(OFHost *host, OFBuffer *out_snapshot_data, void *context);
static void OFCookbookDisplayLink(OFHost *host, double target_timestamp, void *context);

@implementation OFCookbookController

- (instancetype)initWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection {
    self = [super init];
    if (!self) {
        return nil;
    }

    _appConnection = appConnection;
    _appearance = NSAppearance.currentDrawingAppearance;
    _currentSize = CGSizeMake(800, 600);
    _route = OFCookbookRouteTableOfContents;
    _timelineStart = 0.24;
    _timelineEnd = 0.72;
    _timelineHasSelection = NO;
    _timelineDragOperation = 0;
    _timelineDragAnchor = 0;
    _timelineCreationDidMove = NO;
    _timelineHasHover = NO;
    _timelineHoverFraction = 0;
    _giantAnimationBaseTime = CACurrentMediaTime();
    _cubeAnimationStartTime = CACurrentMediaTime();
    _hitFrames = [NSMutableArray array];
    _hitRoutes = [NSMutableArray array];
    _accessibilityLabels = [NSMutableArray array];
    _accessibilityFrames = [NSMutableArray array];
    _accessibilityRoles = [NSMutableArray array];
    _accessibleDragAnchorSelections = @[];
    _accessibleContentStorage = [NSTextContentStorage new];
    _accessibleTextLayoutManager = [NSTextLayoutManager new];
    _accessibleTextContainer = [[NSTextContainer alloc] initWithSize:CGSizeMake(640, 1000000)];
    _accessibleTextContainer.lineFragmentPadding = 0;
    _accessibleTextLayoutManager.textContainer = _accessibleTextContainer;
    _accessibleTextLayoutManager.usesFontLeading = YES;
    [_accessibleContentStorage addTextLayoutManager:_accessibleTextLayoutManager];
    _accessibleDocumentText = [self makeAccessibleDocumentText];
    _accessibleContentStorage.attributedString = _accessibleDocumentText;

    OFHostCallbacks callbacks = {
        .message = OFCookbookHandleMessage,
        .disconnected = OFCookbookHandleDisconnect,
        .accessibility_snapshot = OFCookbookWriteAccessibilitySnapshot,
    };
    _host = OFHostCreate(socketFD, callbacks, (__bridge void *)self);
    if (!_host) {
        return nil;
    }

    _retainedSelf = self;
    return self;
}

- (void)dealloc {
    [self stopDisplayLink];
    if (_host) {
        OFHostDestroy(_host);
        _host = NULL;
    }
}

- (void)handleMessage:(const OFBrowserMessage *)message {
    switch (message->kind) {
        case OFBrowserMessageInitializeContent:
            [self initializeWithMessage:&message->as.initialize];
            break;
        case OFBrowserMessageResizeContent:
            self.currentSize = message->as.resize;
            [self renderCurrentRoute];
            break;
        case OFBrowserMessageSystemAppearanceUpdate:
            [self updateAppearanceFromArchive:message->as.appearance.appearance_archive];
            [self renderCurrentRoute];
            break;
        case OFBrowserMessageMouseMoved:
            [self mouseMovedAt:CGPointMake(message->as.mouse.x, message->as.mouse.y)];
            break;
        case OFBrowserMessageMouseDown:
            [self mouseDownAt:CGPointMake(message->as.mouse.x, message->as.mouse.y) clickCount:message->as.mouse.click_count];
            break;
        case OFBrowserMessageRightMouseDown:
            [self rightMouseDownAt:CGPointMake(message->as.mouse.x, message->as.mouse.y) clickCount:message->as.mouse.click_count];
            break;
        case OFBrowserMessageMouseDragged:
            [self mouseDraggedTo:CGPointMake(message->as.mouse.x, message->as.mouse.y)];
            break;
        case OFBrowserMessageMouseUp:
            if (self.route == OFCookbookRouteTimelineRange) {
                [self timelineMouseUpAtPoint:[self viewportPointFromRootPoint:CGPointMake(message->as.mouse.x, message->as.mouse.y)]];
            }
            self.accessibleDragAnchorSelections = @[];
            if (self.route != OFCookbookRouteTimelineRange) {
                OFHostSetCursor(self.host, OFCursorTypeArrow);
            }
            break;
        case OFBrowserMessageScrollWheelEvent:
            [self scrollByDeltaY:message->as.scroll.delta_y atPoint:CGPointMake(message->as.scroll.x, message->as.scroll.y)];
            break;
        case OFBrowserMessageCopySelectedPasteboardRequest:
            [self sendCopyResponse:message->as.request.request_id];
            break;
        case OFBrowserMessageHistoryTraversal:
            [self switchToRoute:[self routeFromURLStringView:message->as.history.url]];
            break;
        case OFBrowserMessageShutdown:
            [self requestShutdown];
            break;
        default:
            break;
    }
}

- (void)initializeWithMessage:(const OFInitializeContent *)initialize {
    OFHostConfigureFromInitialize(self.host, initialize);
    if (initialize->has_appearance_archive) {
        [self updateAppearanceFromArchive:initialize->appearance_archive];
    }
    self.currentSize = initialize->has_content_size ? initialize->content_size : CGSizeMake(800, 600);
    self.route = [self routeFromURLString:OFHostURL(self.host)];

    CALayer *root = [CALayer layer];
    root.masksToBounds = YES;
    self.rootLayer = root;

    if (!self.registeredLayer && [self.appConnection respondsToSelector:@selector(registerLayer:)]) {
        [self.appConnection registerLayer:root];
        self.registeredLayer = YES;
    }

    OFHostUpdateStartPageMetadata(self.host, "Outerframe Cookbook", NULL, 0, 0, 0);
    [self renderCurrentRoute];
}

- (void)updateAppearanceFromArchive:(OFDataView)archive {
    NSData *data = [NSData dataWithBytesNoCopy:(void *)archive.bytes length:archive.length freeWhenDone:NO];
    NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
    self.appearance = appearance ?: NSAppearance.currentDrawingAppearance;
}

- (OFCookbookRoute)routeFromURLString:(const char *)urlCString {
    NSString *urlString = urlCString ? [NSString stringWithUTF8String:urlCString] : nil;
    return [self routeFromURLStringObject:urlString];
}

- (OFCookbookRoute)routeFromURLStringView:(OFStringView)urlView {
    NSString *urlString = nil;
    if (urlView.bytes && urlView.length > 0) {
        urlString = [[NSString alloc] initWithBytes:urlView.bytes length:urlView.length encoding:NSUTF8StringEncoding];
    }
    return [self routeFromURLStringObject:urlString];
}

- (OFCookbookRoute)routeFromURLStringObject:(NSString *)urlString {
    NSURLComponents *components = urlString.length ? [NSURLComponents componentsWithString:urlString] : nil;
    NSString *recipe = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"recipe"]) {
            recipe = item.value.lowercaseString;
            break;
        }
    }
    recipe = [[recipe stringByReplacingOccurrencesOfString:@"-" withString:@"_"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([recipe isEqualToString:@"accessible_text"] || [recipe isEqualToString:@"text"] || [recipe isEqualToString:@"textkit"]) return OFCookbookRouteAccessibleText;
    if ([recipe isEqualToString:@"manual_scroll"] || [recipe isEqualToString:@"manual"]) return OFCookbookRouteManualScroll;
    if ([recipe isEqualToString:@"nested_scroll"] || [recipe isEqualToString:@"nested"]) return OFCookbookRouteNestedScroll;
    if ([recipe isEqualToString:@"timeline_range"] || [recipe isEqualToString:@"timeline"] || [recipe isEqualToString:@"brush"]) return OFCookbookRouteTimelineRange;
    if ([recipe isEqualToString:@"giant_page"] || [recipe isEqualToString:@"giant"] || [recipe isEqualToString:@"animations"]) return OFCookbookRouteGiantPage;
    if ([recipe isEqualToString:@"n_cube"] || [recipe isEqualToString:@"ncube"] || [recipe isEqualToString:@"hypercube"]) return OFCookbookRouteNCube;
    return OFCookbookRouteTableOfContents;
}

- (NSString *)urlStringForRoute:(OFCookbookRoute)route {
    NSString *baseString = OFHostURL(self.host) ? [NSString stringWithUTF8String:OFHostURL(self.host)] : nil;
    NSURLComponents *components = baseString.length ? [NSURLComponents componentsWithString:baseString] : nil;
    if (!components) {
        return nil;
    }

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if (![item.name isEqualToString:@"recipe"]) {
            [queryItems addObject:item];
        }
    }

    NSString *recipe = nil;
    switch (route) {
        case OFCookbookRouteAccessibleText: recipe = @"accessible_text"; break;
        case OFCookbookRouteManualScroll: recipe = @"manual_scroll"; break;
        case OFCookbookRouteNestedScroll: recipe = @"nested_scroll"; break;
        case OFCookbookRouteTimelineRange: recipe = @"timeline_range"; break;
        case OFCookbookRouteGiantPage: recipe = @"giant_page"; break;
        case OFCookbookRouteNCube: recipe = @"n_cube"; break;
        case OFCookbookRouteTableOfContents: break;
    }
    if (recipe) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"recipe" value:recipe]];
    }
    components.queryItems = queryItems.count > 0 ? queryItems : nil;
    components.fragment = nil;
    return components.URL.absoluteString;
}

- (void)navigateToRoute:(OFCookbookRoute)route {
    if (route == self.route) {
        return;
    }
    NSString *url = [self urlStringForRoute:route];
    OFHostPushHistoryEntry(self.host, url.UTF8String);
    [self switchToRoute:route];
}

- (void)switchToRoute:(OFCookbookRoute)route {
    self.route = route;
    self.scrollOffset = 0;
    self.innerScrollOffset = 0;
    self.selectedCopyText = nil;
    self.accessibleSelectionRange = NSMakeRange(0, 0);
    self.hasAccessibleSelectionRange = NO;
    self.accessibleDragAnchorSelections = @[];
    self.accessibleTextLayoutManager.textSelections = @[];
    self.timelineHasSelection = NO;
    self.timelineDragOperation = 0;
    self.timelineCreationDidMove = NO;
    self.timelineHasHover = NO;
    [self renderCurrentRoute];
    OFHostSendAccessibilityTreeChanged(self.host, OFAccessibilityNotificationLayoutChanged);
}

- (void)renderCurrentRoute {
    if (!self.rootLayer) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [self stopDisplayLink];
    [self.hitFrames removeAllObjects];
    [self.hitRoutes removeAllObjects];
    [self.accessibilityLabels removeAllObjects];
    [self.accessibilityFrames removeAllObjects];
    [self.accessibilityRoles removeAllObjects];

    [self.appearance performAsCurrentDrawingAppearance:^{
        self.rootLayer.frame = CGRectMake(0, 0, self.currentSize.width, self.currentSize.height);
        self.rootLayer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

        [self.pageLayer removeFromSuperlayer];
        self.metalLayer = nil;

        CALayer *page = [CALayer layer];
        page.geometryFlipped = YES;
        page.frame = self.rootLayer.bounds;
        page.masksToBounds = YES;
        [self.rootLayer addSublayer:page];
        self.pageLayer = page;

        switch (self.route) {
            case OFCookbookRouteTableOfContents:
                [self renderTableOfContents];
                break;
            case OFCookbookRouteAccessibleText:
                [self renderAccessibleText];
                break;
            case OFCookbookRouteManualScroll:
                [self renderManualScroll];
                break;
            case OFCookbookRouteNestedScroll:
                [self renderNestedScroll];
                break;
            case OFCookbookRouteTimelineRange:
                [self renderTimelineRange];
                break;
            case OFCookbookRouteGiantPage:
                [self renderGiantPage];
                break;
            case OFCookbookRouteNCube:
                [self renderNCube];
                [self startDisplayLink];
                break;
        }
    }];

    [CATransaction commit];
    OFHostUpdatePageMetadata(self.host, OFCookbookRouteTitle(self.route).UTF8String, NULL, 0, 0, 0);
    [self updatePasteboardCapabilities];
}

- (void)addAccessibilityLabel:(NSString *)label frame:(CGRect)frame role:(OFAccessibilityRole)role {
    [self.accessibilityLabels addObject:label ?: @""];
    [self.accessibilityFrames addObject:[NSValue valueWithRect:frame]];
    [self.accessibilityRoles addObject:@(role)];
}

- (CATextLayer *)addText:(NSString *)text fontSize:(CGFloat)fontSize weight:(NSFontWeight)weight color:(NSColor *)color frame:(CGRect)frame {
    CATextLayer *layer = OFTextLayer(text, [NSFont systemFontOfSize:fontSize weight:weight], color, fontSize);
    layer.frame = frame;
    [self.pageLayer addSublayer:layer];
    [self addAccessibilityLabel:text frame:frame role:OFAccessibilityRoleStaticText];
    return layer;
}

- (void)addPageHeaderWithSubtitle:(NSString *)subtitle {
    [self addText:OFCookbookRouteTitle(self.route)
         fontSize:26
           weight:NSFontWeightSemibold
            color:NSColor.labelColor
            frame:CGRectMake(28, 24, self.currentSize.width - 56, 34)];
    [self addText:subtitle
         fontSize:14
           weight:NSFontWeightRegular
            color:NSColor.secondaryLabelColor
             frame:CGRectMake(28, 62, self.currentSize.width - 56, 24)];
}

- (CGPoint)viewportPointFromRootPoint:(CGPoint)point {
    return [self.rootLayer convertPoint:point toLayer:self.pageLayer];
}

- (CGFloat)scrollbarTrackHeightForViewportHeight:(CGFloat)viewportHeight {
    return MAX(viewportHeight - 8, 0);
}

- (NSColor *)scrollbarTrackColor {
    __block NSColor *track = [NSColor.unemphasizedSelectedTextBackgroundColor colorWithAlphaComponent:0.35];
    [self.appearance performAsCurrentDrawingAppearance:^{
        NSColor *controlBackground = NSColor.controlBackgroundColor;
        NSColor *label = NSColor.labelColor;
        CGFloat controlRed = 0;
        CGFloat controlGreen = 0;
        CGFloat controlBlue = 0;
        CGFloat labelRed = 0;
        CGFloat labelGreen = 0;
        CGFloat labelBlue = 0;
        [[controlBackground colorUsingColorSpace:NSColorSpace.genericRGBColorSpace] getRed:&controlRed green:&controlGreen blue:&controlBlue alpha:NULL];
        [[label colorUsingColorSpace:NSColorSpace.genericRGBColorSpace] getRed:&labelRed green:&labelGreen blue:&labelBlue alpha:NULL];
        CGFloat brightness = (controlRed + controlGreen + controlBlue) / 3.0;
        CGFloat blend = brightness > 0.6 ? 0.25 : 0.45;
        NSColor *fallback = [NSColor colorWithCalibratedRed:controlRed + (labelRed - controlRed) * blend
                                                      green:controlGreen + (labelGreen - controlGreen) * blend
                                                       blue:controlBlue + (labelBlue - controlBlue) * blend
                                                      alpha:brightness > 0.6 ? 0.35 : 0.6];
        track = [NSColor.unemphasizedSelectedTextBackgroundColor isEqual:controlBackground] ? fallback : [NSColor.unemphasizedSelectedTextBackgroundColor colorWithAlphaComponent:(brightness > 0.6 ? 0.35 : 0.6)];
    }];
    return track;
}


- (void)addScrollbarForContentHeight:(CGFloat)contentHeight viewportHeight:(CGFloat)viewportHeight offset:(CGFloat)offset outer:(BOOL)outer {
    (void)outer;
    [self addScrollbarInLayer:self.pageLayer viewportSize:self.currentSize contentHeight:contentHeight offset:offset bottomOrigin:NO];
}

- (void)addScrollbarInLayer:(CALayer *)layer viewportSize:(CGSize)viewportSize contentHeight:(CGFloat)contentHeight offset:(CGFloat)offset bottomOrigin:(BOOL)bottomOrigin {
    CGFloat width = 8;
    CGFloat inset = 4;
    CGFloat trackHeight = MAX(0, viewportSize.height - inset * 2);
    CGFloat maxOffset = MAX(0, contentHeight - viewportSize.height);
    if (maxOffset <= 0.5 || trackHeight <= 0) {
        return;
    }
    CGFloat knobProportion = MIN(MAX(viewportSize.height / contentHeight, 0.05), 1.0);
    CGFloat knobHeight = MIN(MAX(trackHeight * knobProportion, 12), trackHeight);
    CGFloat knobRange = MAX(trackHeight - knobHeight, 0);
    CGFloat ratio = OFClamp(offset / maxOffset, 0, 1);
    CGFloat knobY = knobRange * (bottomOrigin ? (1.0 - ratio) : ratio);
    CALayer *track = [CALayer layer];
    track.frame = CGRectMake(viewportSize.width - inset - width, inset, width, trackHeight);
    track.cornerRadius = width * 0.5;
    track.backgroundColor = [self scrollbarTrackColor].CGColor;
    track.opacity = 0.9;
    track.zPosition = 200;
    [layer addSublayer:track];

    CALayer *knob = [CALayer layer];
    knob.frame = CGRectMake(0, knobY, width, knobHeight);
    knob.cornerRadius = width * 0.5;
    knob.masksToBounds = YES;
    __block CGFloat knobAlpha = 0.75;
    [self.appearance performAsCurrentDrawingAppearance:^{
        NSColor *controlBackground = [NSColor.controlBackgroundColor colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
        CGFloat red = 0;
        CGFloat green = 0;
        CGFloat blue = 0;
        [controlBackground getRed:&red green:&green blue:&blue alpha:NULL];
        CGFloat brightness = (red + green + blue) / 3.0;
        knobAlpha = brightness > 0.6 ? 0.75 : 0.85;
    }];
    knob.backgroundColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:knobAlpha].CGColor;
    [track addSublayer:knob];
}

- (void)mouseMovedAt:(CGPoint)point {
    CGPoint viewportPoint = [self viewportPointFromRootPoint:point];
    OFCursorType cursor = OFCursorTypeArrow;
    if (self.route == OFCookbookRouteTableOfContents) {
        for (NSValue *frameValue in self.hitFrames) {
            if (CGRectContainsPoint(frameValue.rectValue, viewportPoint)) {
                cursor = OFCursorTypePointingHand;
                break;
            }
        }
    } else if (self.route == OFCookbookRouteAccessibleText) {
        cursor = [self isPointOverAccessibleText:viewportPoint] ? OFCursorTypeIBeam : OFCursorTypeArrow;
    } else if (self.route == OFCookbookRouteTimelineRange) {
        [self timelineMouseMovedAtPoint:viewportPoint];
        return;
    }
    OFHostSetCursor(self.host, cursor);
}

- (void)mouseDownAt:(CGPoint)point clickCount:(uint32_t)clickCount {
    CGPoint viewportPoint = [self viewportPointFromRootPoint:point];
    if (self.route == OFCookbookRouteTableOfContents) {
        for (NSUInteger i = 0; i < self.hitFrames.count; i++) {
            if (CGRectContainsPoint(self.hitFrames[i].rectValue, viewportPoint)) {
                [self navigateToRoute:self.hitRoutes[i].integerValue];
                return;
            }
        }
    } else if (self.route == OFCookbookRouteAccessibleText) {
        [self accessibleMouseDownAtPoint:viewportPoint clickCount:clickCount];
    } else if (self.route == OFCookbookRouteTimelineRange) {
        [self timelineMouseDownAtPoint:viewportPoint];
    }
}

- (void)mouseDraggedTo:(CGPoint)point {
    if (self.route == OFCookbookRouteAccessibleText) {
        [self accessibleMouseDraggedToPoint:[self viewportPointFromRootPoint:point]];
    } else if (self.route == OFCookbookRouteTimelineRange) {
        [self timelineMouseDraggedToPoint:[self viewportPointFromRootPoint:point]];
    }
}

- (void)scrollByDeltaY:(CGFloat)deltaY atPoint:(CGPoint)point {
    CGPoint viewportPoint = [self viewportPointFromRootPoint:point];
    CGFloat adjusted = -deltaY;
    if (self.route == OFCookbookRouteNestedScroll) {
        if ([self nestedScrollByAdjustedDelta:adjusted atPoint:viewportPoint]) {
            return;
        }
    }
    if (self.route == OFCookbookRouteAccessibleText ||
        self.route == OFCookbookRouteTableOfContents ||
        self.route == OFCookbookRouteManualScroll ||
        self.route == OFCookbookRouteNestedScroll ||
        self.route == OFCookbookRouteGiantPage) {
        CGFloat previousOffset = self.scrollOffset;
        self.scrollOffset = MAX(0, self.scrollOffset + adjusted);
        [self renderCurrentRoute];
        if (self.route == OFCookbookRouteAccessibleText && fabs(self.scrollOffset - previousOffset) > 0.0001) {
            OFHostSendAccessibilityTreeChanged(self.host, OFAccessibilityNotificationLayoutChanged);
        }
    }
}

- (void)startDisplayLink {
    if (self.hasDisplayLink) {
        return;
    }
    self.displayLinkID = OFHostRegisterDisplayLinkCallback(self.host, OFCookbookDisplayLink, (__bridge void *)self);
    self.hasDisplayLink = YES;
}

- (void)stopDisplayLink {
    if (!self.hasDisplayLink) {
        return;
    }
    OFHostStopDisplayLinkCallback(self.host, self.displayLinkID);
    self.hasDisplayLink = NO;
}

- (void)displayLinkTick:(double)targetTimestamp {
    self.animationTime = targetTimestamp;
    if (self.route == OFCookbookRouteNCube) {
        [self renderNCubeFrameAtTimestamp:targetTimestamp];
    }
}

- (void)updatePasteboardCapabilities {
    const char *types[] = { "public.utf8-plain-text" };
    BOOL canCopy = self.selectedCopyText.length > 0;
    OFHostSetPasteboardCapabilities(self.host, canCopy, false, canCopy ? types : NULL, canCopy ? 1 : 0);
}

- (void)sendCopyResponse:(OFUUID)requestID {
    if (self.selectedCopyText.length == 0) {
        OFHostSendCopySelectedPasteboardResponse(self.host, requestID, NULL, 0);
        return;
    }
    NSData *data = [self.selectedCopyText dataUsingEncoding:NSUTF8StringEncoding];
    const char *type = "public.utf8-plain-text";
    OFPasteboardItemView item = {
        .type_identifier = { .bytes = type, .length = strlen(type) },
        .data = { .bytes = data.bytes, .length = data.length },
    };
    OFHostSendCopySelectedPasteboardResponse(self.host, requestID, &item, 1);
}

- (bool)writeAccessibilitySnapshot:(OFBuffer *)outSnapshotData {
    if (self.route == OFCookbookRouteAccessibleText) {
        return [self writeAccessibleTextAccessibilitySnapshot:outSnapshotData];
    }

    NSMutableArray<NSMutableData *> *retainedCStringData = [NSMutableArray array];
    const char *(^retainedCString)(NSString *) = ^const char *(NSString *string) {
        NSData *encoded = [(string ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSMutableData *storage = [encoded mutableCopy];
        uint8_t terminator = 0;
        [storage appendBytes:&terminator length:1];
        [retainedCStringData addObject:storage];
        return storage.bytes;
    };

    size_t childCount = self.accessibilityLabels.count;
    OFAccessibilityNode *children = calloc(childCount ? childCount : 1, sizeof(*children));
    if (!children) {
        return false;
    }

    for (size_t i = 0; i < childCount; i++) {
        children[i] = (OFAccessibilityNode){
            .identifier = (uint32_t)i + 1,
            .role = (OFAccessibilityRole)self.accessibilityRoles[i].unsignedCharValue,
            .frame = self.accessibilityFrames[i].rectValue,
            .label = retainedCString(self.accessibilityLabels[i]),
            .enabled = true,
        };
    }

    const char *rootLabel = retainedCString(OFCookbookRouteTitle(self.route));
    OFAccessibilityNode root = {
        .identifier = 0,
        .role = OFAccessibilityRoleContainer,
        .frame = CGRectMake(0, 0, self.currentSize.width, self.currentSize.height),
        .label = rootLabel,
        .enabled = true,
        .children = children,
        .child_count = childCount,
    };
    OFAccessibilitySnapshot snapshot = {
        .root_nodes = &root,
        .root_count = 1,
    };
    bool result = OFAccessibilitySnapshotEncode(&snapshot, outSnapshotData);
    free(children);
    (void)retainedCStringData;
    return result;
}

- (void)shutdown {
    [self stopDisplayLink];
    if (self.host) {
        OFHostDestroy(self.host);
        self.host = NULL;
    }
    self.rootLayer = nil;
    self.pageLayer = nil;
    self.appConnection = nil;
    self.retainedSelf = nil;
}

- (void)requestShutdown {
    if (self.destroyScheduled) {
        return;
    }
    self.destroyScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self shutdown];
    });
}

@end

static void OFCookbookHandleMessage(OFHost *host, const OFBrowserMessage *message, void *context) {
    (void)host;
    [(__bridge OFCookbookController *)context handleMessage:message];
}

static void OFCookbookHandleDisconnect(OFHost *host, void *context) {
    (void)host;
    [(__bridge OFCookbookController *)context requestShutdown];
}

static bool OFCookbookWriteAccessibilitySnapshot(OFHost *host, OFBuffer *out_snapshot_data, void *context) {
    (void)host;
    return [(__bridge OFCookbookController *)context writeAccessibilitySnapshot:out_snapshot_data];
}

static void OFCookbookDisplayLink(OFHost *host, double target_timestamp, void *context) {
    (void)host;
    [(__bridge OFCookbookController *)context displayLinkTick:target_timestamp];
}

@implementation OuterframeCookbookObjCContent

+ (int32_t)startWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection {
    return [[OFCookbookController alloc] initWithSocketFD:socketFD appConnection:appConnection] ? 0 : 1;
}

@end
