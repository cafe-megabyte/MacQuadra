//
//  B2ScreenView.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 09/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import "B2ScreenView.h"
#include "sysdeps.h"
#include "video.h"
#import "B2AppDelegate.h"

B2ScreenView *sharedScreenView = nil;
NSString * const B2VideoSizePresetDefaultsKey = @"videoSizePreset";
NSString * const B2VideoSizePresetStandard = @"standard";
NSString * const B2VideoSizePresetLarge = @"large";
NSString * const B2VideoSizePresetStandardLandscape = @"standardLandscape";
NSString * const B2VideoSizePresetLargeLandscape = @"largeLandscape";
static const CGFloat B2LayoutEpsilon = 1.0;

typedef struct {
    CGRect containerBounds;
    CGRect safeBounds;
} B2ScreenLayoutMetrics;

typedef struct {
    CGRect baseScreenBounds;
    CGRect viewportClampingBounds;
    CGFloat screenScale;
} B2ScreenLayout;

@implementation B2ScreenView
{
    CGImageRef screenImage;
    CALayer *viewportClippingLayer;
    CALayer *videoLayer;
    UIGestureRecognizer *pinchGestureRecognizer;
    CGSize initialSize;
    CGRect baseScreenBounds;
    CGRect viewportClampingBounds;
    CGRect activeScreenViewFrame;
    BOOL hasActiveScreenLayout;
    BOOL activeLayoutWantsMargins;
    BOOL hasStableLayoutMetrics;
    BOOL allowsResizePreviewImageUpdate;
    B2ScreenLayoutMetrics stableLayoutMetrics;
    NSDictionary<NSString *, NSValue *> *cachedPresetVideoSizes;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    sharedScreenView = self;
    _viewportScale = 1.0;
    viewportClippingLayer = [CALayer layer];
    viewportClippingLayer.masksToBounds = YES;
    [self.layer addSublayer:viewportClippingLayer];
    videoLayer = [CALayer layer];
    NSString *screenFilter = [[NSUserDefaults standardUserDefaults] stringForKey:@"screenFilter"];
    videoLayer.magnificationFilter = screenFilter;
    videoLayer.minificationFilter = screenFilter;
    [viewportClippingLayer addSublayer:videoLayer];
    self.clipsToBounds = YES;
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:@"screenFilter" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([object isEqual:[NSUserDefaults standardUserDefaults]]) {
        if ([keyPath isEqualToString:@"screenFilter"]) {
            NSString *oldValue = change[NSKeyValueChangeOldKey];
            NSString *value = change[NSKeyValueChangeNewKey];
            videoLayer.magnificationFilter = value;
            videoLayer.minificationFilter = value;
            if ([value isEqualToString:kCAFilterNearest] || [oldValue isEqualToString:kCAFilterNearest]) {
                [self setNeedsLayout];
                [self layoutIfNeeded];
            }
        }
    }
}

- (void)dealloc {
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"screenFilter" context:NULL];
}

- (void)initVideoModes {
    NSMutableArray<NSValue*> *videoModes = [[NSMutableArray alloc] initWithCapacity:9];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGSize standardSize = [self videoSizeForPreset:B2VideoSizePresetStandard];
    CGSize standardLandscapeSize = [self videoSizeForPreset:B2VideoSizePresetStandardLandscape];
    CGSize largeSize = [self videoSizeForPreset:B2VideoSizePresetLarge];
    CGSize largeLandscapeSize = [self videoSizeForPreset:B2VideoSizePresetLargeLandscape];

    cachedPresetVideoSizes = @{
        B2VideoSizePresetStandard: [NSValue valueWithCGSize:standardSize],
        B2VideoSizePresetStandardLandscape: [NSValue valueWithCGSize:standardLandscapeSize],
        B2VideoSizePresetLarge: [NSValue valueWithCGSize:largeSize],
        B2VideoSizePresetLargeLandscape: [NSValue valueWithCGSize:largeLandscapeSize],
    };

    // dynamic resolutions
    [self addVideoMode:standardSize to:videoModes allowDuplicate:YES];
    [self addVideoMode:standardLandscapeSize to:videoModes allowDuplicate:YES];
    [self addVideoMode:largeSize to:videoModes allowDuplicate:YES];
    [self addVideoMode:largeLandscapeSize to:videoModes allowDuplicate:YES];
    
    // default resolutions
    [self addVideoMode:CGSizeMake(640, 480) to:videoModes allowDuplicate:YES];
    [self addVideoMode:CGSizeMake(832, 624) to:videoModes allowDuplicate:YES];
    [self addVideoMode:CGSizeMake(1024, 768) to:videoModes allowDuplicate:YES];
    [self addVideoMode:CGSizeMake(1280, 1024) to:videoModes allowDuplicate:YES];
    
    // custom size
    CGSize customSize = CGSizeFromString([defaults valueForKey:@"videoSize"]);
    _hasCustomVideoMode = [self addVideoMode:customSize to:videoModes];
    _videoModes = [NSArray arrayWithArray:videoModes];
}

- (BOOL)addVideoMode:(CGSize)size to:(NSMutableArray<NSValue*>*)videoModes {
    return [self addVideoMode:size to:videoModes allowDuplicate:NO];
}

- (BOOL)addVideoMode:(CGSize)size to:(NSMutableArray<NSValue*>*)videoModes allowDuplicate:(BOOL)allowDuplicate {
    if (size.width <= 0 || size.height <= 0) {
        return NO;
    }
    NSValue *value = [NSValue valueWithCGSize:size];
    if (allowDuplicate || ![videoModes containsObject:value]) {
        [videoModes addObject:value];
        return YES;
    }
    return NO;
}

- (void)updateCustomSize:(CGSize)customSize {
    NSMutableArray<NSValue*> *videoModes = _videoModes.mutableCopy;
    if (self.hasCustomVideoMode) {
        [videoModes removeLastObject];
        _hasCustomVideoMode = NO;
    }
    _hasCustomVideoMode = [self addVideoMode:customSize to:videoModes];
    _videoModes = [NSArray arrayWithArray:videoModes];
}

- (void)reloadVideoModes {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self reloadVideoModes];
        });
        return;
    }

    [self initVideoModes];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self initVideoModes];
    });

    if (CGSizeEqualToSize(_screenSize, CGSizeZero)) {
        return;
    }

    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive && hasActiveScreenLayout) {
        [self restoreActiveLayoutFrameIfNeeded];
        return;
    }

    [self updateStableLayoutMetricsIfNeeded];

    CGSize screenSize = _screenSize;
    B2ScreenLayout screenLayout = [self screenLayoutForScreenSize:screenSize];
    baseScreenBounds = screenLayout.baseScreenBounds;
    viewportClampingBounds = screenLayout.viewportClampingBounds;
    CGFloat screenScale = screenLayout.screenScale;

    NSString *screenFilter = [[NSUserDefaults standardUserDefaults] stringForKey:@"screenFilter"];
    [self updateViewportClippingMask];
    _viewportOffset = [self clampedViewportOffset:_viewportOffset scale:_viewportScale];
    CGRect screenBounds = [self screenBoundsForViewportScale:_viewportScale offset:_viewportOffset];
    CGRect clippingBounds = CGRectIsEmpty(viewportClampingBounds) ? self.bounds : viewportClampingBounds;
    CGRect layerScreenBounds = CGRectOffset(screenBounds, -clippingBounds.origin.x, -clippingBounds.origin.y);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    viewportClippingLayer.frame = clippingBounds;
    videoLayer.frame = layerScreenBounds;
    [CATransaction commit];
    _screenBounds = screenBounds;
    _screenBounds.origin.y += self.frame.origin.y;
    hasActiveScreenLayout = YES;
    BOOL scaleIsIntegral = (floor(screenScale) == screenScale);
    if (scaleIsIntegral) screenFilter = kCAFilterNearest;
    videoLayer.magnificationFilter = screenFilter;
    videoLayer.minificationFilter = screenFilter;
    activeScreenViewFrame = self.frame;
}

- (void)setScreenSize:(CGSize)screenSize {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setScreenSize:screenSize];
        });
        return;
    }
    
    _screenSize = screenSize;
    [self updateConstraints];
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)setViewportScale:(CGFloat)viewportScale {
    [self setViewportScale:viewportScale anchoredAtPoint:CGPointMake(CGRectGetMidX(baseScreenBounds), CGRectGetMidY(baseScreenBounds))];
}

- (void)setViewportScale:(CGFloat)viewportScale anchoredAtPoint:(CGPoint)anchorPoint {
    CGFloat oldScale = MAX(_viewportScale, 1.0);
    CGFloat newScale = MAX(1.0, MIN(viewportScale, 6.0));
    if (newScale <= 1.0) {
        _viewportScale = 1.0;
        _viewportOffset = CGPointZero;
        [self setNeedsLayout];
        return;
    }

    CGPoint baseCenter = CGPointMake(CGRectGetMidX(baseScreenBounds), CGRectGetMidY(baseScreenBounds));
    CGPoint oldCenter = CGPointMake(baseCenter.x + _viewportOffset.x, baseCenter.y + _viewportOffset.y);
    CGFloat scaleRatio = newScale / oldScale;
    CGPoint newCenter = CGPointMake(anchorPoint.x - (anchorPoint.x - oldCenter.x) * scaleRatio,
                                    anchorPoint.y - (anchorPoint.y - oldCenter.y) * scaleRatio);
    _viewportScale = newScale;
    _viewportOffset = CGPointMake(newCenter.x - baseCenter.x, newCenter.y - baseCenter.y);
    _viewportOffset = [self clampedViewportOffset:_viewportOffset scale:_viewportScale];
    [self setNeedsLayout];
}

- (void)panViewportByTranslation:(CGPoint)translation {
    if (_viewportScale <= 1.0) {
        return;
    }
    _viewportOffset = CGPointMake(_viewportOffset.x + translation.x, _viewportOffset.y + translation.y);
    _viewportOffset = [self clampedViewportOffset:_viewportOffset scale:_viewportScale];
    [self setNeedsLayout];
}

- (void)resetViewportAnimated:(BOOL)animated {
    void (^resetBlock)(void) = ^{
        self->_viewportScale = 1.0;
        self->_viewportOffset = CGPointZero;
        [self layoutIfNeeded];
    };

    [self setNeedsLayout];
    if (animated) {
        [UIView animateWithDuration:0.2 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:resetBlock completion:nil];
    } else {
        resetBlock();
    }
}

- (void)refreshLayout {
    [UIView performWithoutAnimation:^{
        [self setNeedsUpdateConstraints];
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }];
}

- (void)restoreActiveLayoutFrameIfNeeded {
    if (!hasActiveScreenLayout || CGRectIsEmpty(activeScreenViewFrame) || CGRectEqualToRect(self.frame, activeScreenViewFrame)) {
        return;
    }

    [UIView performWithoutAnimation:^{
        self.frame = self->activeScreenViewFrame;
    }];
}

- (CGRect)screenBoundsForViewportScale:(CGFloat)scale offset:(CGPoint)offset {
    if (scale <= 1.0 || CGRectIsEmpty(baseScreenBounds)) {
        return baseScreenBounds;
    }

    CGSize scaledSize = CGSizeMake(baseScreenBounds.size.width * scale, baseScreenBounds.size.height * scale);
    CGPoint center = CGPointMake(CGRectGetMidX(baseScreenBounds) + offset.x, CGRectGetMidY(baseScreenBounds) + offset.y);
    return CGRectIntegral(CGRectMake(center.x - scaledSize.width / 2.0,
                                    center.y - scaledSize.height / 2.0,
                                    scaledSize.width,
                                    scaledSize.height));
}

- (CGRect)safeViewportBoundsWithinBounds:(CGRect)bounds {
    return [self safeLayoutBoundsWithinBounds:bounds
                               safeAreaInsets:[self safeAreaInsetsForPresetLayout]
                                    landscape:NO
                              referenceBounds:(self.superview ? self.superview.bounds : self.bounds)];
}

- (void)updateStableLayoutMetricsIfNeeded {
    CGRect containerBounds = self.bounds;
    if (CGRectIsEmpty(containerBounds)) {
        return;
    }

    if (hasStableLayoutMetrics && CGSizeEqualToSize(stableLayoutMetrics.containerBounds.size, containerBounds.size)) {
        return;
    }

    stableLayoutMetrics.containerBounds = containerBounds;
    stableLayoutMetrics.safeBounds = [self safeViewportBoundsWithinBounds:containerBounds];
    hasStableLayoutMetrics = YES;
}

- (B2ScreenLayout)screenLayoutForScreenSize:(CGSize)screenSize {
    B2ScreenLayout layout;
    layout.baseScreenBounds = CGRectZero;
    layout.viewportClampingBounds = CGRectZero;
    layout.screenScale = 1.0;

    CGRect containerBounds = hasStableLayoutMetrics ? stableLayoutMetrics.containerBounds : self.bounds;
    CGRect safeBounds = hasStableLayoutMetrics ? stableLayoutMetrics.safeBounds : [self safeViewportBoundsWithinBounds:self.bounds];
    if (CGRectIsEmpty(containerBounds) || CGSizeEqualToSize(screenSize, CGSizeZero)) {
        return layout;
    }

    BOOL usesEdgeLayoutBounds = [self screenSize:screenSize matchesLayoutBounds:containerBounds];
    BOOL usesSafeLayoutBounds = [self screenSize:screenSize matchesLayoutBounds:safeBounds];
    BOOL usesDynamicLayoutBounds = usesEdgeLayoutBounds || usesSafeLayoutBounds;
    CGRect layoutBounds = usesSafeLayoutBounds ? safeBounds : containerBounds;

    CGFloat screenScale = MIN(layoutBounds.size.width / screenSize.width,
                              layoutBounds.size.height / screenSize.height);
    NSString *screenFilter = [[NSUserDefaults standardUserDefaults] stringForKey:@"screenFilter"];
    if (!usesDynamicLayoutBounds && [screenFilter isEqualToString:kCAFilterNearest] && screenScale > 1.0) {
        screenScale = floor(screenScale);
    } else if (!usesDynamicLayoutBounds && screenScale > 1.0 && screenScale <= 1.1) {
        screenScale = 1.0;
    }

    CGSize screenBoundsSize = CGSizeMake(screenSize.width * screenScale, screenSize.height * screenScale);

    CGRect baseBounds = CGRectMake(0.0, 0.0, screenBoundsSize.width, screenBoundsSize.height);
    baseBounds.origin.x = [self originForLength:screenBoundsSize.width
                                  preferredMin:CGRectGetMinX(layoutBounds)
                                  preferredMax:CGRectGetMaxX(layoutBounds)
                                   containerMin:CGRectGetMinX(containerBounds)
                                   containerMax:CGRectGetMaxX(containerBounds)
                                      alignment:0.5];
    CGFloat topPreferredMinY = usesSafeLayoutBounds ? CGRectGetMinY(safeBounds) : [self topPreferredMinYForScreenWidth:screenBoundsSize.width
                                                                                                                originX:baseBounds.origin.x
                                                                                                                 height:screenBoundsSize.height
                                                                                                         containerBounds:containerBounds
                                                                                                              safeBounds:safeBounds];
    baseBounds.origin.y = [self originForLength:screenBoundsSize.height
                                  preferredMin:topPreferredMinY
                                  preferredMax:CGRectGetMaxY(layoutBounds)
                                   containerMin:CGRectGetMinY(containerBounds)
                                   containerMax:CGRectGetMaxY(containerBounds)
                                      alignment:0.0];
    if (usesSafeLayoutBounds) {
        baseBounds = [self integralRectInsideBounds:baseBounds bounds:safeBounds];
    } else {
        baseBounds = CGRectIntegral(baseBounds);
    }

    BOOL baseScreenFitsSafeAreaLeft = CGRectGetMinX(baseBounds) >= CGRectGetMinX(safeBounds) - B2LayoutEpsilon;
    BOOL baseScreenFitsSafeAreaRight = CGRectGetMaxX(baseBounds) <= CGRectGetMaxX(safeBounds) + B2LayoutEpsilon;
    BOOL baseScreenFitsSafeAreaTop = CGRectGetMinY(baseBounds) >= CGRectGetMinY(safeBounds) - B2LayoutEpsilon;
    BOOL baseScreenFitsSafeAreaBottom = CGRectGetMaxY(baseBounds) <= CGRectGetMaxY(safeBounds) + B2LayoutEpsilon;
    CGFloat clampingMinX = baseScreenFitsSafeAreaLeft ? CGRectGetMinX(safeBounds) : CGRectGetMinX(containerBounds);
    CGFloat clampingMaxX = baseScreenFitsSafeAreaRight ? CGRectGetMaxX(safeBounds) : CGRectGetMaxX(containerBounds);
    CGFloat clampingMinY = baseScreenFitsSafeAreaTop ? CGRectGetMinY(safeBounds) : CGRectGetMinY(containerBounds);
    CGFloat clampingMaxY = baseScreenFitsSafeAreaBottom ? CGRectGetMaxY(safeBounds) : CGRectGetMaxY(containerBounds);

    layout.baseScreenBounds = baseBounds;
    layout.viewportClampingBounds = CGRectMake(clampingMinX,
                                               clampingMinY,
                                               clampingMaxX - clampingMinX,
                                               clampingMaxY - clampingMinY);
    layout.screenScale = screenScale;
    return layout;
}

- (BOOL)screenSize:(CGSize)screenSize matchesLayoutBounds:(CGRect)bounds {
    if (CGRectIsEmpty(bounds) || CGSizeEqualToSize(screenSize, CGSizeZero)) {
        return NO;
    }

    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }

    const CGFloat divisors[] = {1.0, 2.0, 4.0};
    for (NSUInteger i = 0; i < sizeof(divisors) / sizeof(divisors[0]); i++) {
        uint32_t width = [self pixelDimensionForLength:bounds.size.width nativeScale:nativeScale divisor:divisors[i]];
        uint32_t height = [self pixelDimensionForLength:bounds.size.height nativeScale:nativeScale divisor:divisors[i]];
        if ((uint32_t)screenSize.width == width && (uint32_t)screenSize.height == height) {
            return YES;
        }
    }
    return NO;
}

- (CGFloat)topPreferredMinYForScreenWidth:(CGFloat)screenWidth
                                  originX:(CGFloat)originX
                                   height:(CGFloat)screenHeight
                          containerBounds:(CGRect)containerBounds
                               safeBounds:(CGRect)safeBounds {
    if (screenHeight > safeBounds.size.height + B2LayoutEpsilon) {
        return CGRectGetMinY(containerBounds);
    }

    // We use the idiom as a cutout heuristic: iPhones may have notches or islands,
    // so reduced screens must stay inside the top safe area. iPads currently only
    // have rounded corners/system indicators, so a narrow emulator can safely sit
    // above the reported safe area when it does not reach the risky side regions.
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        return CGRectGetMinY(safeBounds);
    }

    CGFloat screenMinX = originX;
    CGFloat screenMaxX = originX + screenWidth;
    BOOL screenFitsSafeAreaHorizontally = screenMinX >= CGRectGetMinX(safeBounds) - B2LayoutEpsilon &&
                                          screenMaxX <= CGRectGetMaxX(safeBounds) + B2LayoutEpsilon;
    if (screenFitsSafeAreaHorizontally) {
        return CGRectGetMinY(containerBounds);
    }

    return CGRectGetMinY(safeBounds);
}

- (CGFloat)originForLength:(CGFloat)length
             preferredMin:(CGFloat)preferredMin
             preferredMax:(CGFloat)preferredMax
              containerMin:(CGFloat)containerMin
              containerMax:(CGFloat)containerMax
                alignment:(CGFloat)alignment {
    CGFloat preferredLength = preferredMax - preferredMin;
    CGFloat containerLength = containerMax - containerMin;
    CGFloat origin;
    if (length <= preferredLength + B2LayoutEpsilon) {
        origin = preferredMin + (preferredLength - length) * alignment;
    } else {
        origin = containerMin + (containerLength - length) * alignment;
    }
    return origin;
}

- (void)updateViewportClippingMask {
    viewportClippingLayer.frame = CGRectIsEmpty(viewportClampingBounds) ? self.bounds : viewportClampingBounds;
}

- (CGPoint)clampedViewportOffset:(CGPoint)offset scale:(CGFloat)scale {
    if (scale <= 1.0 || CGRectIsEmpty(baseScreenBounds)) {
        return CGPointZero;
    }

    CGRect bounds = CGRectIsEmpty(viewportClampingBounds) ? self.bounds : viewportClampingBounds;
    CGSize scaledSize = CGSizeMake(baseScreenBounds.size.width * scale, baseScreenBounds.size.height * scale);
    CGPoint baseCenter = CGPointMake(CGRectGetMidX(baseScreenBounds), CGRectGetMidY(baseScreenBounds));
    CGPoint center = CGPointMake(baseCenter.x + offset.x, baseCenter.y + offset.y);

    center.x = [self clampedCenterCoordinate:center.x
                                      length:scaledSize.width
                                 boundsStart:CGRectGetMinX(bounds)
                                   boundsEnd:CGRectGetMaxX(bounds)
                                  baseCenter:baseCenter.x];
    center.y = [self clampedCenterCoordinate:center.y
                                      length:scaledSize.height
                                 boundsStart:CGRectGetMinY(bounds)
                                   boundsEnd:CGRectGetMaxY(bounds)
                                  baseCenter:baseCenter.y];
    CGPoint clampedOffset = CGPointMake(center.x - baseCenter.x, center.y - baseCenter.y);
    return clampedOffset;
}

- (CGFloat)clampedCenterCoordinate:(CGFloat)center
                            length:(CGFloat)length
                       boundsStart:(CGFloat)boundsStart
                         boundsEnd:(CGFloat)boundsEnd
                        baseCenter:(CGFloat)baseCenter {
    CGFloat boundsLength = boundsEnd - boundsStart;
    if (length <= boundsLength + B2LayoutEpsilon) {
        return baseCenter;
    }

    CGFloat halfLength = length / 2.0;
    CGFloat minimumCenter = boundsEnd - halfLength;
    CGFloat maximumCenter = boundsStart + halfLength;
    return MIN(MAX(center, minimumCenter), maximumCenter);
}

- (void)updateConstraints {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive && hasActiveScreenLayout) {
        [self applyScreenViewConstraintsWantsMargins:activeLayoutWantsMargins];
        [self restoreActiveLayoutFrameIfNeeded];
        [super updateConstraints];
        return;
    }

    BOOL wantsMargins = NO;
    activeLayoutWantsMargins = wantsMargins;
    [self applyScreenViewConstraintsWantsMargins:wantsMargins];
    [super updateConstraints];
}

- (void)applyScreenViewConstraintsWantsMargins:(BOOL)wantsMargins {
    BOOL marginConstraintsNeedUpdate = NO;
    for (NSLayoutConstraint *constraint in self.marginConstraints) {
        if (constraint.active != wantsMargins) {
            marginConstraintsNeedUpdate = YES;
            break;
        }
    }

    BOOL fullScreenConstraintsNeedUpdate = NO;
    for (NSLayoutConstraint *constraint in self.fullScreenConstraints) {
        if (constraint.active == wantsMargins) {
            fullScreenConstraintsNeedUpdate = YES;
            break;
        }
    }

    if (!marginConstraintsNeedUpdate && !fullScreenConstraintsNeedUpdate) {
        return;
    }

    if (wantsMargins) {
        [NSLayoutConstraint deactivateConstraints:self.fullScreenConstraints];
        [NSLayoutConstraint activateConstraints:self.marginConstraints];
    } else {
        [NSLayoutConstraint deactivateConstraints:self.marginConstraints];
        [NSLayoutConstraint activateConstraints:self.fullScreenConstraints];
    }
}

- (CGRect)safeLayoutBoundsWithinBounds:(CGRect)bounds {
    return [self safeLayoutBoundsWithinBounds:bounds landscape:NO];
}

- (CGRect)safeLayoutBoundsWithinBounds:(CGRect)bounds landscape:(BOOL)landscape {
    return [self safeLayoutBoundsWithinBounds:bounds
                               safeAreaInsets:[self safeAreaInsetsForLayout]
                                    landscape:landscape
                              referenceBounds:self.bounds];
}

- (CGRect)safeLayoutBoundsWithinBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets landscape:(BOOL)landscape referenceBounds:(CGRect)referenceBounds {
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // There is no clean cutout API. Use the idiom as a display-shape heuristic:
        // iPad safe areas usually describe rounded corners or system indicators, not
        // notches. Keep iPad presets symmetric and let the placement solver bypass
        // the top safe area when the emulator is narrow enough.
        CGFloat safeInset = MAX(MAX(safeAreaInsets.top, safeAreaInsets.bottom), MAX(safeAreaInsets.left, safeAreaInsets.right));
        return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safeInset, safeInset, safeInset, safeInset));
    }
    if (landscape && referenceBounds.size.width < referenceBounds.size.height) {
        // Landscape presets may be calculated while the app is still portrait; rotate the current safe area for sizing.
        safeAreaInsets = UIEdgeInsetsMake(safeAreaInsets.left, safeAreaInsets.top, safeAreaInsets.right, safeAreaInsets.bottom);
    }
    if (bounds.size.width < bounds.size.height && safeAreaInsets.left == 0.0 && safeAreaInsets.right == 0.0 && safeAreaInsets.bottom > 0.0) {
        // UIKit reports no horizontal safe area in iPhone portrait, but the bottom rounded corners still clip full-width content.
        CGFloat cornerInset = MIN(6.0, MAX(2.0, ceil(safeAreaInsets.bottom * 0.125)));
        safeAreaInsets.left = cornerInset;
        safeAreaInsets.right = cornerInset;
    }
    return UIEdgeInsetsInsetRect(bounds, safeAreaInsets);
}

- (UIEdgeInsets)safeAreaInsetsForLayout {
    if (@available(iOS 11, *)) {
        return self.safeAreaInsets;
    }
    return UIEdgeInsetsZero;
}

- (UIEdgeInsets)safeAreaInsetsForPresetLayout {
    if (@available(iOS 11, *)) {
        return self.superview ? self.superview.safeAreaInsets : self.safeAreaInsets;
    }
    return UIEdgeInsetsZero;
}

- (CGRect)integralRectInsideBounds:(CGRect)rect bounds:(CGRect)bounds {
    CGRect integralRect = CGRectMake(ceil(rect.origin.x),
                                     ceil(rect.origin.y),
                                     floor(rect.size.width),
                                     floor(rect.size.height));
    integralRect.size.width = MIN(integralRect.size.width, CGRectGetMaxX(bounds) - integralRect.origin.x);
    integralRect.size.height = MIN(integralRect.size.height, CGRectGetMaxY(bounds) - integralRect.origin.y);
    return integralRect;
}

- (uint32_t)pixelDimensionForLength:(CGFloat)length nativeScale:(CGFloat)nativeScale divisor:(CGFloat)divisor {
    return (uint32_t)(length * nativeScale / divisor) &~ 1;
}

- (CGSize)videoSizeForPreset:(NSString *)preset {
    if (![NSThread isMainThread]) {
        NSValue *cachedSize = cachedPresetVideoSizes[preset];
        if (cachedSize != nil) {
            return cachedSize.CGSizeValue;
        }
        __block CGSize presetSize;
        dispatch_sync(dispatch_get_main_queue(), ^{
            presetSize = [self videoSizeForPreset:preset];
        });
        return presetSize;
    }

    if ([preset isEqualToString:B2VideoSizePresetStandard]) {
        return [self videoSizeForSafeLayoutWithDivisor:2.0 landscape:NO];
    } else if ([preset isEqualToString:B2VideoSizePresetLarge]) {
        return [self videoSizeForLargeLayoutWithDivisor:4.0 landscape:NO];
    } else if ([preset isEqualToString:B2VideoSizePresetStandardLandscape]) {
        return [self videoSizeForSafeLayoutWithDivisor:2.0 landscape:YES];
    } else if ([preset isEqualToString:B2VideoSizePresetLargeLandscape]) {
        return [self videoSizeForLargeLayoutWithDivisor:4.0 landscape:YES];
    } else {
        return CGSizeZero;
    }
}

- (CGRect)boundsForLandscape:(BOOL)landscape {
    return [self bounds:self.bounds forLandscape:landscape];
}

- (CGRect)boundsForPresetLandscape:(BOOL)landscape {
    CGRect bounds = self.superview ? self.superview.bounds : self.bounds;
    return [self bounds:bounds forLandscape:landscape];
}

- (CGRect)bounds:(CGRect)bounds forLandscape:(BOOL)landscape {
    if (landscape && bounds.size.width < bounds.size.height) {
        bounds.size = CGSizeMake(bounds.size.height, bounds.size.width);
    }
    return bounds;
}

- (CGSize)videoSizeForLargeLayoutWithDivisor:(CGFloat)divisor landscape:(BOOL)landscape {
    // Same cutout heuristic as above: large iPhone modes stay inside the safe area
    // because a notch/island may intrude; iPad large modes may use the full edge area.
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        return [self videoSizeForSafeLayoutWithDivisor:divisor landscape:landscape];
    }
    return [self videoSizeForEdgeLayoutWithDivisor:divisor landscape:landscape];
}

- (CGSize)videoSizeForEdgeLayoutWithDivisor:(CGFloat)divisor landscape:(BOOL)landscape {
    if (![NSThread isMainThread]) {
        __block CGSize presetSize;
        dispatch_sync(dispatch_get_main_queue(), ^{
            presetSize = [self videoSizeForEdgeLayoutWithDivisor:divisor landscape:landscape];
        });
        return presetSize;
    }

    CGRect bounds = [self boundsForPresetLandscape:landscape];
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }
    uint32_t w = [self pixelDimensionForLength:bounds.size.width nativeScale:nativeScale divisor:divisor];
    uint32_t h = [self pixelDimensionForLength:bounds.size.height nativeScale:nativeScale divisor:divisor];
    return CGSizeMake(w, h);
}

- (CGSize)videoSizeForSafeLayoutWithDivisor:(CGFloat)divisor landscape:(BOOL)landscape {
    if (![NSThread isMainThread]) {
        __block CGSize presetSize;
        dispatch_sync(dispatch_get_main_queue(), ^{
            presetSize = [self videoSizeForSafeLayoutWithDivisor:divisor landscape:landscape];
        });
        return presetSize;
    }

    CGRect presetBounds = [self boundsForPresetLandscape:landscape];
    CGRect bounds = [self safeLayoutBoundsWithinBounds:presetBounds
                                       safeAreaInsets:[self safeAreaInsetsForPresetLayout]
                                            landscape:landscape
                                      referenceBounds:(self.superview ? self.superview.bounds : self.bounds)];
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }
    uint32_t w = [self pixelDimensionForLength:bounds.size.width nativeScale:nativeScale divisor:divisor];
    uint32_t h = [self pixelDimensionForLength:bounds.size.height nativeScale:nativeScale divisor:divisor];
    return CGSizeMake(w, h);
}

- (void)updateImage:(CGImageRef)newImage {
    if (![NSThread isMainThread]) {
        CGImageRef imageForMainThread = newImage;
        if (imageForMainThread != nil) {
            CGImageRetain(imageForMainThread);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateImage:imageForMainThread];
            if (imageForMainThread != nil) {
                CGImageRelease(imageForMainThread);
            }
        });
        return;
    }

    if (self.resizePreviewActive && !allowsResizePreviewImageUpdate) {
        return;
    }

    CGImageRef oldImage = screenImage;
    CGImageRelease(oldImage);
    screenImage = newImage;
    if (screenImage != nil) {
        CGImageRetain(screenImage);
    }
    CGImageRef imageForLayer = screenImage;
    if (imageForLayer != nil) {
        CGImageRetain(imageForLayer);
    }

    [self setNeedsLayout];
    [self layoutIfNeeded];
    videoLayer.contents = (__bridge id)imageForLayer;
    if (imageForLayer != nil) {
        CGImageRelease(imageForLayer);
    }
}

- (void)updateResizePreviewImage:(CGImageRef)newImage {
    allowsResizePreviewImageUpdate = YES;
    [self updateImage:newImage];
    allowsResizePreviewImageUpdate = NO;
}

@end
