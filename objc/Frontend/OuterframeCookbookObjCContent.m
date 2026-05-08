#import "OFCookbookController.h"

static void OFCookbookBootstrapMessage(OFHost *host, const OFBrowserMessage *message, void *context);
static void OFCookbookHandleDisconnect(OFHost *host, void *context);

static OFCookbookRoute OFCookbookRouteFromURLStringObject(NSString *urlString) {
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

static void OFCookbookRefreshRecipeContextHistory(OFCookbookRecipeContext *context) {
    context->history_entry_id = OFHostCurrentHistoryEntryID(context->host);
    context->history_length = OFHostHistoryLength(context->host);
    context->can_go_back = OFHostCanGoBackInHistory(context->host);
    context->can_go_forward = OFHostCanGoForwardInHistory(context->host);
}

OFCookbookRecipeContext *OFCookbookGetRecipeContext(void *runtime) {
    OFCookbookController *controller = (__bridge OFCookbookController *)runtime;
    OFCookbookRecipeContext *context = &controller->_recipe_context;
    context->runtime = (__bridge void *)controller;
    context->host = controller.host;
    OFCookbookRefreshRecipeContextHistory(context);
    return context;
}

@implementation OFCookbookController

- (instancetype)initWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection {
    self = [super init];
    if (!self) {
        return nil;
    }

    _appConnection = appConnection;
    _recipe_context = (OFCookbookRecipeContext){
        .route = OFCookbookRouteTableOfContents,
        .current_size = CGSizeMake(800, 600),
        .runtime = (__bridge void *)self,
        .bundle = [NSBundle bundleForClass:self.class],
        .appearance = NSAppearance.currentDrawingAppearance,
    };
    _recipeHandler = OFCookbookRecipeHandlerForRoute(_recipe_context.route);

    OFHostCallbacks callbacks = {
        .message = OFCookbookBootstrapMessage,
        .disconnected = OFCookbookHandleDisconnect,
    };
    _host = OFHostCreate(socketFD, callbacks, (__bridge void *)self);
    if (!_host) {
        return nil;
    }
    _recipe_context.host = _host;
    OFCookbookRefreshRecipeContextHistory(&_recipe_context);

    _retainedSelf = self;
    return self;
}

- (void)dealloc {
    [self leaveCurrentRecipe];
    if (_host) {
        OFHostDestroy(_host);
        _host = NULL;
    }
}

- (void)initializeWithMessage:(const OFInitializeContent *)initialize {
    OFHostConfigureFromInitialize(self.host, initialize);
    CALayer *root = [CALayer layer];
    root.masksToBounds = YES;
    _recipe_context.root_layer = root;

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
    if (route == _recipe_context.route) {
        return;
    }
    NSString *url = [self urlStringForRoute:route];
    OFHostPushHistoryEntry(self.host, url.UTF8String);
    [self switchToRoute:route];
    [self enterCurrentRecipe];
}

- (void)switchToRoute:(OFCookbookRoute)route {
    [self leaveCurrentRecipe];
    _recipe_context.route = route;
    self.recipeHandler = OFCookbookRecipeHandlerForRoute(route);
    if (self.host && self.recipeHandler) {
        OFHostSetMessageCallback(self.host, self.recipeHandler->handle_message, (__bridge void *)self);
    }
}

- (void)enterCurrentRecipe {
    if (self.recipeHandler && self.recipeHandler->enter_route) {
        self.recipeHandler->enter_route((__bridge void *)self);
    }
    OFHostSendAccessibilityTreeChanged(self.host, OFAccessibilityNotificationLayoutChanged);
}

- (void)leaveCurrentRecipe {
    if (!self.recipeHandler) {
        return;
    }
    if (self.recipeHandler->leave_route) {
        self.recipeHandler->leave_route((__bridge void *)self);
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
    [self leaveCurrentRecipe];
    if (self.host) {
        OFHostDestroy(self.host);
        self.host = NULL;
    }
    _recipe_context.root_layer = nil;
    _recipe_context.page_layer = nil;
    _recipe_context.recipe_state = NULL;
    self.appConnection = nil;
    self.retainedSelf = nil;
}

@end

void OFCookbookSendAccessibilitySnapshotResponse(OFCookbookRecipeContext *context, OFUUID request_id, const OFBuffer *snapshot) {
    OFHostSendAccessibilitySnapshotResponse(context->host, request_id, snapshot ? snapshot->bytes : NULL, snapshot ? snapshot->length : 0);
}

void OFCookbookSendDefaultAccessibilitySnapshotResponse(OFCookbookRecipeContext *context, OFUUID request_id) {
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

void OFCookbookNavigateToRoute(OFCookbookRecipeContext *context, OFCookbookRoute route) {
    OFCookbookController *controller = (__bridge OFCookbookController *)context->runtime;
    [controller navigateToRoute:route];
}

void OFCookbookSwitchToRoute(OFCookbookRecipeContext *context, OFCookbookRoute route) {
    OFCookbookController *controller = (__bridge OFCookbookController *)context->runtime;
    [controller switchToRoute:route];
    [controller enterCurrentRecipe];
}

void OFCookbookRequestShutdown(void *runtime) {
    [(__bridge OFCookbookController *)runtime requestShutdown];
}

static void OFCookbookBootstrapMessage(OFHost *host, const OFBrowserMessage *message, void *context) {
    (void)host;
    OFCookbookController *controller = (__bridge OFCookbookController *)context;
    if (message->kind == OFBrowserMessageInitializeContent) {
        [controller initializeWithMessage:&message->as.initialize];
        if (controller.recipeHandler && controller.recipeHandler->handle_message) {
            controller.recipeHandler->handle_message(host, message, context);
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
