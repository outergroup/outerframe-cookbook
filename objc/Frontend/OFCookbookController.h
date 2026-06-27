#import "OuterframeCookbookObjCContent.h"
#import "Vendor/OuterframeC/OuterframeHost.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <stdbool.h>
#import <simd/simd.h>
#import <string.h>

typedef struct {
    vector_float4 axis01;
    vector_float4 axis23;
    vector_float4 axis4;
} OFNCubeUniforms;

enum {
    OFNCubeDimension = 5,
};

typedef NS_ENUM(NSInteger, OFCookbookRoute) {
    OFCookbookRouteTableOfContents = 0,
    OFCookbookRouteTextRegion,
    OFCookbookRouteNestedScroll,
    OFCookbookRouteTimelineRange,
    OFCookbookRouteGiantPage,
    OFCookbookRouteNCube,
};

extern const NSInteger OFCookbookPageCount;

NSString *OFCookbookRouteTitle(OFCookbookRoute route);
NSString *OFCookbookRouteDescription(OFCookbookRoute route);
OFCookbookRoute OFCookbookRouteAtIndex(NSInteger index);
CGFloat OFClamp(CGFloat value, CGFloat lower, CGFloat upper);
CATextLayer *OFTextLayer(NSString *text, NSFont *font, NSColor *color, CGFloat fontSize);
CALayer *OFRoundedLayer(NSColor *fill, NSColor *stroke, CGFloat radius);

typedef struct {
    OFCookbookRoute route;
    CGSize current_size;
    OFUUID history_entry_id;
    uint32_t history_length;
    bool can_go_back;
    bool can_go_forward;
    void *runtime;
    void *page_state;
    OFHost *host;
    __strong NSBundle *bundle;
    __strong CALayer *root_layer;
    __unsafe_unretained CALayer *page_layer;
    __strong NSAppearance *appearance;
    __unsafe_unretained NSMutableArray<NSString *> *accessibility_labels;
    __unsafe_unretained NSMutableArray<NSValue *> *accessibility_frames;
    __unsafe_unretained NSMutableArray<NSNumber *> *accessibility_roles;
} OFCookbookPageContext;

typedef void (*OFCookbookPageRouteCallback)(void *runtime);

typedef struct OFCookbookPageHandler {
    OFHostMessageCallback handle_message;
    OFCookbookPageRouteCallback enter_route;
    OFCookbookPageRouteCallback leave_route;
} OFCookbookPageHandler;

extern const OFCookbookPageHandler OFCookbookTableOfContentsHandler;
extern const OFCookbookPageHandler OFCookbookTextRegionHandler;
extern const OFCookbookPageHandler OFCookbookNestedScrollDemoHandler;
extern const OFCookbookPageHandler OFCookbookTimelineRangeSelectorHandler;
extern const OFCookbookPageHandler OFCookbookGiantPageWithAnimationsHandler;
extern const OFCookbookPageHandler OFCookbookNCubeHandler;

const OFCookbookPageHandler *OFCookbookPageHandlerForRoute(OFCookbookRoute route);

void OFCookbookAddAccessibilityLabel(OFCookbookPageContext *context, NSString *label, CGRect frame, OFAccessibilityRole role);
CATextLayer *OFCookbookAddText(OFCookbookPageContext *context, NSString *text, CGFloat font_size, NSFontWeight weight, NSColor *color, CGRect frame);
void OFCookbookAddScrollbarForContentHeight(OFCookbookPageContext *context, CGFloat content_height, CGFloat viewport_height, CGFloat offset);
void OFCookbookAddScrollbarInLayer(OFCookbookPageContext *context, CALayer *layer, CGSize viewport_size, CGFloat content_height, CGFloat offset, bool bottom_origin);
CGPoint OFCookbookViewportPointFromRootPoint(OFCookbookPageContext *context, CGPoint root_point);
void OFCookbookRenderPageFrame(OFCookbookPageContext *context, void (*render)(OFCookbookPageContext *context));
void OFCookbookUpdateRoutePageMetadata(OFCookbookPageContext *context);
void OFCookbookUpdatePasteboardCapabilities(OFCookbookPageContext *context, NSString *selected_text);
void OFCookbookSendCopySelectedPasteboardResponse(OFCookbookPageContext *context, OFUUID request_id, NSString *selected_text);
void OFCookbookSendEditCommandValidationResponse(OFCookbookPageContext *context, OFUUID request_id, OFEditCommandSet requested_commands, NSString *selected_text);
void OFCookbookSendAccessibilitySnapshotResponse(OFCookbookPageContext *context, OFUUID request_id, const OFBuffer *snapshot);
void OFCookbookSendDefaultAccessibilitySnapshotResponse(OFCookbookPageContext *context, OFUUID request_id);
OFCookbookPageContext *OFCookbookGetPageContext(void *runtime);
OFCookbookRoute OFCookbookRouteFromURLStringView(OFStringView url);
void OFCookbookNavigateToRoute(OFCookbookPageContext *context, OFCookbookRoute route);
void OFCookbookSwitchToRoute(OFCookbookPageContext *context, OFCookbookRoute route);
void OFCookbookRequestShutdown(void *runtime);

void OFCookbookRenderTableOfContents(OFCookbookPageContext *context);
void OFCookbookRenderNestedScrollDemo(OFCookbookPageContext *context);
bool OFCookbookNestedScrollDemoScroll(OFCookbookPageContext *context, CGFloat adjusted_delta, CGPoint point);
void OFCookbookRenderTimelineRangeSelector(OFCookbookPageContext *context);
void OFCookbookTimelineRangeMouseDown(OFCookbookPageContext *context, CGPoint point, bool *needs_render);
void OFCookbookTimelineRangeMouseDragged(OFCookbookPageContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render);
void OFCookbookTimelineRangeMouseUp(OFCookbookPageContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render);
void OFCookbookTimelineRangeMouseMoved(OFCookbookPageContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render);
void OFCookbookRenderGiantPageWithAnimations(OFCookbookPageContext *context);
NSAttributedString *OFCookbookMakeTextRegionDocumentText(void);
void OFCookbookRenderTextRegion(OFCookbookPageContext *context);
bool OFCookbookWriteTextRegionAccessibilitySnapshot(OFCookbookPageContext *context, OFBuffer *out_snapshot_data);
bool OFCookbookTextRegionIsPointOverText(OFCookbookPageContext *context, CGPoint point);
void OFCookbookTextRegionMouseDown(OFCookbookPageContext *context, CGPoint point, uint32_t click_count, bool *needs_render);
void OFCookbookTextRegionMouseDragged(OFCookbookPageContext *context, CGPoint point, bool *needs_render);
void OFCookbookTextRegionRightMouseDown(OFCookbookPageContext *context, CGPoint root_point, CGPoint viewport_point, bool *needs_render);
void OFCookbookRenderNCube(OFCookbookPageContext *context);
void OFCookbookRenderNCubeFrameAtTimestamp(OFCookbookPageContext *context, CFTimeInterval target_timestamp);

@interface OFCookbookController : NSObject {
@public
    OFCookbookPageContext _page_context;
}
@property(nonatomic, assign) OFHost *host;
@property(nonatomic, strong) id<OuterframeAppConnection> appConnection;
@property(nonatomic, strong) id retainedSelf;
@property(nonatomic, assign) const OFCookbookPageHandler *pageHandler;
@property(nonatomic, assign) BOOL registeredLayer;
@property(nonatomic, assign) BOOL destroyScheduled;

- (instancetype)initWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection;
- (void)navigateToRoute:(OFCookbookRoute)route;
- (void)switchToRoute:(OFCookbookRoute)route;
- (void)initializeWithMessage:(const OFInitializeContent *)initialize;
- (void)enterCurrentPage;
- (void)leaveCurrentPage;
- (void)requestShutdown;
@end

@interface OFTextKitDisplayLayer : CALayer
@property(nonatomic, strong) NSAppearance *appearance;
@property(nonatomic, strong) NSTextLayoutManager *textLayoutManager;
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, assign) CGPoint textInset;
@property(nonatomic, assign) CGRect visibleBounds;
@end
