#import "OuterframeCookbookObjCContent.h"
#import "Vendor/OuterframeC/OuterframeHost.h"

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
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

@interface OFTextKitDisplayLayer : CALayer
@property(nonatomic, strong) NSAppearance *appearance;
@property(nonatomic, strong) NSTextLayoutManager *textLayoutManager;
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, assign) CGPoint textInset;
@property(nonatomic, assign) CGRect visibleBounds;
@end

@interface OFCookbookController : NSObject
@property(nonatomic, assign) OFHost *host;
@property(nonatomic, strong) id<OuterframeAppConnection> appConnection;
@property(nonatomic, strong) id retainedSelf;
@property(nonatomic, strong) NSAppearance *appearance;
@property(nonatomic, strong) CALayer *rootLayer;
@property(nonatomic, strong) CALayer *pageLayer;
@property(nonatomic, strong) NSMutableArray<NSValue *> *hitFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *hitRoutes;
@property(nonatomic, strong) NSMutableArray<NSString *> *accessibilityLabels;
@property(nonatomic, strong) NSMutableArray<NSValue *> *accessibilityFrames;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *accessibilityRoles;
@property(nonatomic, strong) NSString *selectedCopyText;
@property(nonatomic, strong) NSTextContentStorage *accessibleContentStorage;
@property(nonatomic, strong) NSTextLayoutManager *accessibleTextLayoutManager;
@property(nonatomic, strong) NSTextContainer *accessibleTextContainer;
@property(nonatomic, strong) NSAttributedString *accessibleDocumentText;
@property(nonatomic, strong) NSArray<NSTextSelection *> *accessibleDragAnchorSelections;
@property(nonatomic, assign) NSRange accessibleSelectionRange;
@property(nonatomic, assign) BOOL hasAccessibleSelectionRange;
@property(nonatomic, assign) CGSize currentSize;
@property(nonatomic, assign) OFCookbookRoute route;
@property(nonatomic, assign) CGFloat scrollOffset;
@property(nonatomic, assign) CGFloat innerScrollOffset;
@property(nonatomic, assign) CGFloat timelineStart;
@property(nonatomic, assign) CGFloat timelineEnd;
@property(nonatomic, assign) BOOL timelineHasSelection;
@property(nonatomic, assign) NSInteger timelineDragOperation;
@property(nonatomic, assign) CGFloat timelineDragAnchor;
@property(nonatomic, assign) BOOL timelineCreationDidMove;
@property(nonatomic, assign) BOOL timelineHasHover;
@property(nonatomic, assign) CGFloat timelineHoverFraction;
@property(nonatomic, assign) CGFloat animationTime;
@property(nonatomic, assign) CFTimeInterval giantAnimationBaseTime;
@property(nonatomic, assign) CFTimeInterval cubeAnimationStartTime;
@property(nonatomic, strong) id<MTLDevice> metalDevice;
@property(nonatomic, strong) id<MTLCommandQueue> metalCommandQueue;
@property(nonatomic, strong) id<MTLRenderPipelineState> metalPipelineState;
@property(nonatomic, strong) CAMetalLayer *metalLayer;
@property(nonatomic, strong) NSString *metalSetupError;
@property(nonatomic, assign) BOOL registeredLayer;
@property(nonatomic, assign) BOOL hasDisplayLink;
@property(nonatomic, assign) BOOL destroyScheduled;
@property(nonatomic, assign) OFUUID displayLinkID;

- (instancetype)initWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection;
- (void)handleMessage:(const OFBrowserMessage *)message;
- (void)renderCurrentRoute;
- (void)navigateToRoute:(OFCookbookRoute)route;
- (void)switchToRoute:(OFCookbookRoute)route;
- (void)addAccessibilityLabel:(NSString *)label frame:(CGRect)frame role:(OFAccessibilityRole)role;
- (CATextLayer *)addText:(NSString *)text fontSize:(CGFloat)fontSize weight:(NSFontWeight)weight color:(NSColor *)color frame:(CGRect)frame;
- (void)addPageHeaderWithSubtitle:(NSString *)subtitle;
- (CGPoint)viewportPointFromRootPoint:(CGPoint)point;
- (void)addScrollbarForContentHeight:(CGFloat)contentHeight viewportHeight:(CGFloat)viewportHeight offset:(CGFloat)offset outer:(BOOL)outer;
- (void)addScrollbarInLayer:(CALayer *)layer viewportSize:(CGSize)viewportSize contentHeight:(CGFloat)contentHeight offset:(CGFloat)offset bottomOrigin:(BOOL)bottomOrigin;
- (void)updatePasteboardCapabilities;
- (void)sendCopyResponse:(OFUUID)requestID;
- (bool)writeAccessibilitySnapshot:(OFBuffer *)outSnapshotData;
- (void)requestShutdown;
- (void)displayLinkTick:(double)targetTimestamp;
- (void)startDisplayLink;
- (void)stopDisplayLink;
@end

@interface OFCookbookController (TableOfContents)
- (void)renderTableOfContents;
@end

@interface OFCookbookController (AccessibleTextRegion)
- (void)renderAccessibleText;
- (NSAttributedString *)makeAccessibleDocumentText;
- (bool)writeAccessibleTextAccessibilitySnapshot:(OFBuffer *)outSnapshotData;
- (CGRect)accessibleViewportFrame;
- (CGPoint)accessibleTextContainerPointFromPagePoint:(CGPoint)point;
- (CGRect)accessibleTextContainerInteractionBounds;
- (void)configureAccessibleTextContainerForViewportSize:(CGSize)viewportSize;
- (BOOL)isPointInAccessibleTextViewport:(CGPoint)point;
- (BOOL)isPointOverAccessibleText:(CGPoint)point;
- (void)setAccessibleTextSelection:(NSTextSelection *)selection;
- (NSRange)accessibleRangeForTextSelection:(NSTextSelection *)selection;
- (NSTextRange *)accessibleTextRangeForRange:(NSRange)range;
- (NSTextSelection *)accessibleTextSelectionAtPoint:(CGPoint)point;
- (NSAttributedString *)attributedTextForAccessibleSelection:(NSTextSelection *)selection;
- (NSAttributedString *)selectedAccessibleAttributedText;
- (NSInteger)accessibleTextLocationOffsetAtPoint:(CGPoint)point;
- (void)showContextMenuForAccessibleAttributedText:(NSAttributedString *)text atPoint:(CGPoint)point;
- (NSTextSelection *)accessibleTextLayoutFragmentSelectionAtTextPoint:(CGPoint)textPoint;
- (void)accessibleMouseDownAtPoint:(CGPoint)point clickCount:(uint32_t)clickCount;
- (void)accessibleMouseDraggedToPoint:(CGPoint)point;
- (void)rightMouseDownAt:(CGPoint)point clickCount:(uint32_t)clickCount;
@end

@interface OFCookbookController (ManualScrollView)
- (void)renderManualScroll;
@end

@interface OFCookbookController (NestedScrollDemo)
- (void)renderNestedScroll;
- (BOOL)nestedScrollByAdjustedDelta:(CGFloat)adjusted atPoint:(CGPoint)point;
@end

@interface OFCookbookController (TimelineRangeSelector)
- (void)renderTimelineRange;
- (CGFloat)timelineFunctionValueAt:(CGFloat)x;
- (CGFloat)timelineIntegralFrom:(CGFloat)start to:(CGFloat)end;
- (void)timelineMouseDownAtPoint:(CGPoint)point;
- (void)timelineMouseDraggedToPoint:(CGPoint)point;
- (void)timelineMouseUpAtPoint:(CGPoint)point;
- (void)timelineMouseMovedAtPoint:(CGPoint)point;
@end

@interface OFCookbookController (GiantPageWithAnimations)
- (void)renderGiantPage;
@end

@interface OFCookbookController (NDimensionalCubeShadow)
- (void)renderNCube;
- (void)setupMetalIfNeeded;
- (void)renderNCubeFrameAtTimestamp:(CFTimeInterval)targetTimestamp;
- (OFNCubeUniforms)makeNCubeUniformsAtTime:(float)time drawableSize:(CGSize)drawableSize;
- (void)rotateNCubeVector:(const float *)vector time:(float)time output:(float *)output;
@end
