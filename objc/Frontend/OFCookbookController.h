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
    OFCookbookRouteAccessibleText,
    OFCookbookRouteManualScroll,
    OFCookbookRouteNestedScroll,
    OFCookbookRouteTimelineRange,
    OFCookbookRouteGiantPage,
    OFCookbookRouteNCube,
};

extern const NSInteger OFCookbookRecipeCount;

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
    void *recipe_state;
    OFHost *host;
    __strong NSBundle *bundle;
    __strong CALayer *root_layer;
    __unsafe_unretained CALayer *page_layer;
    __strong NSAppearance *appearance;
    __unsafe_unretained NSMutableArray<NSString *> *accessibility_labels;
    __unsafe_unretained NSMutableArray<NSValue *> *accessibility_frames;
    __unsafe_unretained NSMutableArray<NSNumber *> *accessibility_roles;
} OFCookbookRecipeContext;

typedef void (*OFCookbookRecipeRouteCallback)(void *runtime);

typedef struct OFCookbookRecipeHandler {
    OFHostMessageCallback handle_message;
    OFCookbookRecipeRouteCallback enter_route;
    OFCookbookRecipeRouteCallback leave_route;
} OFCookbookRecipeHandler;

extern const OFCookbookRecipeHandler OFCookbookTableOfContentsHandler;
extern const OFCookbookRecipeHandler OFCookbookAccessibleTextRegionHandler;
extern const OFCookbookRecipeHandler OFCookbookManualScrollViewHandler;
extern const OFCookbookRecipeHandler OFCookbookNestedScrollDemoHandler;
extern const OFCookbookRecipeHandler OFCookbookTimelineRangeSelectorHandler;
extern const OFCookbookRecipeHandler OFCookbookGiantPageWithAnimationsHandler;
extern const OFCookbookRecipeHandler OFCookbookNCubeHandler;

const OFCookbookRecipeHandler *OFCookbookRecipeHandlerForRoute(OFCookbookRoute route);

void OFCookbookAddAccessibilityLabel(OFCookbookRecipeContext *context, NSString *label, CGRect frame, OFAccessibilityRole role);
CATextLayer *OFCookbookAddText(OFCookbookRecipeContext *context, NSString *text, CGFloat font_size, NSFontWeight weight, NSColor *color, CGRect frame);
void OFCookbookAddScrollbarForContentHeight(OFCookbookRecipeContext *context, CGFloat content_height, CGFloat viewport_height, CGFloat offset);
void OFCookbookAddScrollbarInLayer(OFCookbookRecipeContext *context, CALayer *layer, CGSize viewport_size, CGFloat content_height, CGFloat offset, bool bottom_origin);
CGPoint OFCookbookViewportPointFromRootPoint(OFCookbookRecipeContext *context, CGPoint root_point);
void OFCookbookRenderRecipeFrame(OFCookbookRecipeContext *context, void (*render)(OFCookbookRecipeContext *context));
void OFCookbookUpdateRoutePageMetadata(OFCookbookRecipeContext *context);
void OFCookbookUpdatePasteboardCapabilities(OFCookbookRecipeContext *context, NSString *selected_text);
void OFCookbookSendCopySelectedPasteboardResponse(OFCookbookRecipeContext *context, OFUUID request_id, NSString *selected_text);
void OFCookbookSendAccessibilitySnapshotResponse(OFCookbookRecipeContext *context, OFUUID request_id, const OFBuffer *snapshot);
void OFCookbookSendDefaultAccessibilitySnapshotResponse(OFCookbookRecipeContext *context, OFUUID request_id);
OFCookbookRecipeContext *OFCookbookGetRecipeContext(void *runtime);
OFCookbookRoute OFCookbookRouteFromURLStringView(OFStringView url);
void OFCookbookNavigateToRoute(OFCookbookRecipeContext *context, OFCookbookRoute route);
void OFCookbookSwitchToRoute(OFCookbookRecipeContext *context, OFCookbookRoute route);
void OFCookbookRequestShutdown(void *runtime);

void OFCookbookRenderTableOfContents(OFCookbookRecipeContext *context);
void OFCookbookRenderManualScrollView(OFCookbookRecipeContext *context);
void OFCookbookRenderNestedScrollDemo(OFCookbookRecipeContext *context);
bool OFCookbookNestedScrollDemoScroll(OFCookbookRecipeContext *context, CGFloat adjusted_delta, CGPoint point);
void OFCookbookRenderTimelineRangeSelector(OFCookbookRecipeContext *context);
void OFCookbookTimelineRangeMouseDown(OFCookbookRecipeContext *context, CGPoint point, bool *needs_render);
void OFCookbookTimelineRangeMouseDragged(OFCookbookRecipeContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render);
void OFCookbookTimelineRangeMouseUp(OFCookbookRecipeContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render);
void OFCookbookTimelineRangeMouseMoved(OFCookbookRecipeContext *context, CGPoint point, OFCursorType *cursor, bool *needs_render);
void OFCookbookRenderGiantPageWithAnimations(OFCookbookRecipeContext *context);
NSAttributedString *OFCookbookMakeAccessibleDocumentText(void);
void OFCookbookRenderAccessibleTextRegion(OFCookbookRecipeContext *context);
bool OFCookbookWriteAccessibleTextAccessibilitySnapshot(OFCookbookRecipeContext *context, OFBuffer *out_snapshot_data);
bool OFCookbookAccessibleTextIsPointOverText(OFCookbookRecipeContext *context, CGPoint point);
void OFCookbookAccessibleTextMouseDown(OFCookbookRecipeContext *context, CGPoint point, uint32_t click_count, bool *needs_render);
void OFCookbookAccessibleTextMouseDragged(OFCookbookRecipeContext *context, CGPoint point, bool *needs_render);
void OFCookbookAccessibleTextRightMouseDown(OFCookbookRecipeContext *context, CGPoint root_point, CGPoint viewport_point, bool *needs_render);
void OFCookbookRenderNCube(OFCookbookRecipeContext *context);
void OFCookbookRenderNCubeFrameAtTimestamp(OFCookbookRecipeContext *context, CFTimeInterval target_timestamp);

@interface OFCookbookController : NSObject {
@public
    OFCookbookRecipeContext _recipe_context;
}
@property(nonatomic, assign) OFHost *host;
@property(nonatomic, strong) id<OuterframeAppConnection> appConnection;
@property(nonatomic, strong) id retainedSelf;
@property(nonatomic, assign) const OFCookbookRecipeHandler *recipeHandler;
@property(nonatomic, assign) BOOL registeredLayer;
@property(nonatomic, assign) BOOL destroyScheduled;

- (instancetype)initWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection;
- (void)navigateToRoute:(OFCookbookRoute)route;
- (void)switchToRoute:(OFCookbookRoute)route;
- (void)initializeWithMessage:(const OFInitializeContent *)initialize;
- (void)enterCurrentRecipe;
- (void)leaveCurrentRecipe;
- (void)requestShutdown;
@end

@interface OFTextKitDisplayLayer : CALayer
@property(nonatomic, strong) NSAppearance *appearance;
@property(nonatomic, strong) NSTextLayoutManager *textLayoutManager;
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, assign) CGPoint textInset;
@property(nonatomic, assign) CGRect visibleBounds;
@end
