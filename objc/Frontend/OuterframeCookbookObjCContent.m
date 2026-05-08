#import "OFCookbookController.h"

static void OFCookbookBootstrapMessage(OFHost *host, const OFBrowserMessage *message, void *context);
static void OFCookbookHandleDisconnect(OFHost *host, void *context);

static OFCookbookRoute OFCookbookRouteFromURLStringObject(NSString *urlString) {
    NSURLComponents *components = urlString.length ? [NSURLComponents componentsWithString:urlString] : nil;
    NSString *page = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"page"]) {
            page = item.value.lowercaseString;
            break;
        }
    }
    page = [[page stringByReplacingOccurrencesOfString:@"-" withString:@"_"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([page isEqualToString:@"text_region"] || [page isEqualToString:@"text"] || [page isEqualToString:@"textkit"]) return OFCookbookRouteTextRegion;
    if ([page isEqualToString:@"nested_scroll"] || [page isEqualToString:@"nested"]) return OFCookbookRouteNestedScroll;
    if ([page isEqualToString:@"timeline_range"] || [page isEqualToString:@"timeline"] || [page isEqualToString:@"brush"]) return OFCookbookRouteTimelineRange;
    if ([page isEqualToString:@"giant_page"] || [page isEqualToString:@"giant"] || [page isEqualToString:@"animations"]) return OFCookbookRouteGiantPage;
    if ([page isEqualToString:@"n_cube"] || [page isEqualToString:@"ncube"] || [page isEqualToString:@"hypercube"]) return OFCookbookRouteNCube;
    return OFCookbookRouteTableOfContents;
}

static void OFCookbookRefreshPageContextHistory(OFCookbookPageContext *context) {
    context->history_entry_id = OFHostCurrentHistoryEntryID(context->host);
    context->history_length = OFHostHistoryLength(context->host);
    context->can_go_back = OFHostCanGoBackInHistory(context->host);
    context->can_go_forward = OFHostCanGoForwardInHistory(context->host);
}

OFCookbookPageContext *OFCookbookGetPageContext(void *runtime) {
    OFCookbookController *controller = (__bridge OFCookbookController *)runtime;
    OFCookbookPageContext *context = &controller->_page_context;
    context->runtime = (__bridge void *)controller;
    context->host = controller.host;
    OFCookbookRefreshPageContextHistory(context);
    return context;
}

@implementation OFCookbookController

- (instancetype)initWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection {
    self = [super init];
    if (!self) {
        return nil;
    }

    _appConnection = appConnection;
    _page_context = (OFCookbookPageContext){
        .route = OFCookbookRouteTableOfContents,
        .current_size = CGSizeMake(800, 600),
        .runtime = (__bridge void *)self,
        .bundle = [NSBundle bundleForClass:self.class],
        .appearance = NSAppearance.currentDrawingAppearance,
    };
    _pageHandler = OFCookbookPageHandlerForRoute(_page_context.route);

    OFHostCallbacks callbacks = {
        .message = OFCookbookBootstrapMessage,
        .disconnected = OFCookbookHandleDisconnect,
    };
    _host = OFHostCreate(socketFD, callbacks, (__bridge void *)self);
    if (!_host) {
        return nil;
    }
    _page_context.host = _host;
    OFCookbookRefreshPageContextHistory(&_page_context);

    _retainedSelf = self;
    return self;
}

- (void)dealloc {
    [self leaveCurrentPage];
    if (_host) {
        OFHostDestroy(_host);
        _host = NULL;
    }
}

- (void)initializeWithMessage:(const OFInitializeContent *)initialize {
    OFHostConfigureFromInitialize(self.host, initialize);
    CALayer *root = [CALayer layer];
    root.masksToBounds = YES;
    _page_context.root_layer = root;

    if (!self.registeredLayer && [self.appConnection respondsToSelector:@selector(registerLayer:)]) {
        [self.appConnection registerLayer:root];
        self.registeredLayer = YES;
    }

    OFHostUpdateStartPageMetadata(self.host, "Outerframe Cookbook", NULL, 0, 0, 0);
    [self switchToRoute:[self routeFromURLString:OFHostURL(self.host)]];
}

- (OFCookbookRoute)routeFromURLString:(const char *)urlCString {
    NSString *urlString = urlCString ? [NSString stringWithUTF8String:urlCString] : nil;
    return OFCookbookRouteFromURLStringObject(urlString);
}

- (OFCookbookRoute)routeFromURLStringView:(OFStringView)urlView {
    NSString *urlString = nil;
    if (urlView.bytes && urlView.length > 0) {
        urlString = [[NSString alloc] initWithBytes:urlView.bytes length:urlView.length encoding:NSUTF8StringEncoding];
    }
    return OFCookbookRouteFromURLStringObject(urlString);
}

- (OFCookbookRoute)routeFromURLStringObject:(NSString *)urlString {
    return OFCookbookRouteFromURLStringObject(urlString);
}

- (NSString *)urlStringForRoute:(OFCookbookRoute)route {
    NSString *baseString = OFHostURL(self.host) ? [NSString stringWithUTF8String:OFHostURL(self.host)] : nil;
    NSURLComponents *components = baseString.length ? [NSURLComponents componentsWithString:baseString] : nil;
    if (!components) {
        return nil;
    }

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if (![item.name isEqualToString:@"page"]) {
            [queryItems addObject:item];
        }
    }

    NSString *page = nil;
    switch (route) {
        case OFCookbookRouteTextRegion: page = @"text_region"; break;
        case OFCookbookRouteNestedScroll: page = @"nested_scroll"; break;
        case OFCookbookRouteTimelineRange: page = @"timeline_range"; break;
        case OFCookbookRouteGiantPage: page = @"giant_page"; break;
        case OFCookbookRouteNCube: page = @"n_cube"; break;
        case OFCookbookRouteTableOfContents: break;
    }
    if (page) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"page" value:page]];
    }
    components.queryItems = queryItems.count > 0 ? queryItems : nil;
    components.fragment = nil;
    return components.URL.absoluteString;
}

- (void)navigateToRoute:(OFCookbookRoute)route {
    if (route == _page_context.route) {
        return;
    }
    NSString *url = [self urlStringForRoute:route];
    OFHostPushHistoryEntry(self.host, url.UTF8String);
    [self switchToRoute:route];
    [self enterCurrentPage];
}

- (void)switchToRoute:(OFCookbookRoute)route {
    [self leaveCurrentPage];
    _page_context.route = route;
    self.pageHandler = OFCookbookPageHandlerForRoute(route);
    if (self.host && self.pageHandler) {
        OFHostSetMessageCallback(self.host, self.pageHandler->handle_message, (__bridge void *)self);
    }
}

- (void)enterCurrentPage {
    if (self.pageHandler && self.pageHandler->enter_route) {
        self.pageHandler->enter_route((__bridge void *)self);
    }
    OFHostSendAccessibilityTreeChanged(self.host, OFAccessibilityNotificationLayoutChanged);
}

- (void)leaveCurrentPage {
    if (!self.pageHandler) {
        return;
    }
    if (self.pageHandler->leave_route) {
        self.pageHandler->leave_route((__bridge void *)self);
    }
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

- (void)shutdown {
    [self leaveCurrentPage];
    if (self.host) {
        OFHostDestroy(self.host);
        self.host = NULL;
    }
    _page_context.root_layer = nil;
    _page_context.page_layer = nil;
    _page_context.page_state = NULL;
    self.appConnection = nil;
    self.retainedSelf = nil;
}

@end

void OFCookbookSendAccessibilitySnapshotResponse(OFCookbookPageContext *context, OFUUID request_id, const OFBuffer *snapshot) {
    OFHostSendAccessibilitySnapshotResponse(context->host, request_id, snapshot ? snapshot->bytes : NULL, snapshot ? snapshot->length : 0);
}

void OFCookbookSendDefaultAccessibilitySnapshotResponse(OFCookbookPageContext *context, OFUUID request_id) {
    NSMutableArray<NSMutableData *> *retainedCStringData = [NSMutableArray array];
    const char *(^retainedCString)(NSString *) = ^const char *(NSString *string) {
        NSData *encoded = [(string ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSMutableData *storage = [encoded mutableCopy];
        uint8_t terminator = 0;
        [storage appendBytes:&terminator length:1];
        [retainedCStringData addObject:storage];
        return storage.bytes;
    };

    size_t childCount = context->accessibility_labels.count;
    OFAccessibilityNode *children = calloc(childCount ? childCount : 1, sizeof(*children));
    if (!children) {
        OFBuffer fallback = {0};
        if (OFAccessibilityNotImplementedSnapshot("Accessibility not implemented", &fallback)) {
            OFCookbookSendAccessibilitySnapshotResponse(context, request_id, &fallback);
        }
        OFBufferFree(&fallback);
        return;
    }

    for (size_t i = 0; i < childCount; i++) {
        children[i] = (OFAccessibilityNode){
            .identifier = (uint32_t)i + 1,
            .role = (OFAccessibilityRole)context->accessibility_roles[i].unsignedCharValue,
            .frame = context->accessibility_frames[i].rectValue,
            .label = retainedCString(context->accessibility_labels[i]),
            .enabled = true,
        };
    }

    const char *rootLabel = retainedCString(OFCookbookRouteTitle(context->route));
    OFAccessibilityNode root = {
        .identifier = 0,
        .role = OFAccessibilityRoleContainer,
        .frame = CGRectMake(0, 0, context->current_size.width, context->current_size.height),
        .label = rootLabel,
        .enabled = true,
        .children = children,
        .child_count = childCount,
    };
    OFAccessibilitySnapshot snapshot = {
        .root_nodes = &root,
        .root_count = 1,
    };
    OFBuffer snapshot_data = {0};
    if (OFAccessibilitySnapshotEncode(&snapshot, &snapshot_data)) {
        OFCookbookSendAccessibilitySnapshotResponse(context, request_id, &snapshot_data);
    }
    OFBufferFree(&snapshot_data);
    free(children);
    (void)retainedCStringData;
}

OFCookbookRoute OFCookbookRouteFromURLStringView(OFStringView url) {
    NSString *urlString = nil;
    if (url.bytes && url.length > 0) {
        urlString = [[NSString alloc] initWithBytes:url.bytes length:url.length encoding:NSUTF8StringEncoding];
    }
    return OFCookbookRouteFromURLStringObject(urlString);
}

void OFCookbookNavigateToRoute(OFCookbookPageContext *context, OFCookbookRoute route) {
    OFCookbookController *controller = (__bridge OFCookbookController *)context->runtime;
    [controller navigateToRoute:route];
}

void OFCookbookSwitchToRoute(OFCookbookPageContext *context, OFCookbookRoute route) {
    OFCookbookController *controller = (__bridge OFCookbookController *)context->runtime;
    [controller switchToRoute:route];
    [controller enterCurrentPage];
}

void OFCookbookRequestShutdown(void *runtime) {
    [(__bridge OFCookbookController *)runtime requestShutdown];
}

static void OFCookbookBootstrapMessage(OFHost *host, const OFBrowserMessage *message, void *context) {
    (void)host;
    OFCookbookController *controller = (__bridge OFCookbookController *)context;
    if (message->kind == OFBrowserMessageInitializeContent) {
        [controller initializeWithMessage:&message->as.initialize];
        if (controller.pageHandler && controller.pageHandler->handle_message) {
            controller.pageHandler->handle_message(host, message, context);
        }
        return;
    }
    if (message->kind == OFBrowserMessageShutdown) {
        [controller requestShutdown];
    }
}

static void OFCookbookHandleDisconnect(OFHost *host, void *context) {
    (void)host;
    [(__bridge OFCookbookController *)context requestShutdown];
}

@implementation OuterframeCookbookObjCContent

+ (int32_t)startWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection {
    return [[OFCookbookController alloc] initWithSocketFD:socketFD appConnection:appConnection] ? 0 : 1;
}

@end
