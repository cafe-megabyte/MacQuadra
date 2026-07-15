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

@implementation B2ScreenView
{
    CGImageRef screenImage;
    CALayer *videoLayer;
    UIGestureRecognizer *pinchGestureRecognizer;
    CGSize initialSize;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    sharedScreenView = self;
    videoLayer = [CALayer layer];
    NSString *screenFilter = [[NSUserDefaults standardUserDefaults] stringForKey:@"screenFilter"];
    videoLayer.magnificationFilter = screenFilter;
    videoLayer.minificationFilter = screenFilter;
    [self.layer addSublayer:videoLayer];
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
    NSMutableArray<NSValue*> *videoModes = [[NSMutableArray alloc] initWithCapacity:8];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // dynamic resolutions
    [self addVideoMode:[self videoSizeForPreset:B2VideoSizePresetStandard] to:videoModes];
    [self addVideoMode:[self videoSizeForPreset:B2VideoSizePresetLarge] to:videoModes];
    [self addVideoMode:[self videoSizeForPreset:B2VideoSizePresetStandardLandscape] to:videoModes];
    [self addVideoMode:[self videoSizeForPreset:B2VideoSizePresetLargeLandscape] to:videoModes];
    
    // default resolutions
    [self addVideoMode:CGSizeMake(512, 384) to:videoModes];
    [self addVideoMode:CGSizeMake(640, 480) to:videoModes];
    [self addVideoMode:CGSizeMake(800, 600) to:videoModes];
    [self addVideoMode:CGSizeMake(832, 624) to:videoModes];
    [self addVideoMode:CGSizeMake(1024, 768) to:videoModes];
    
    // custom size
    CGSize customSize = CGSizeFromString([defaults valueForKey:@"videoSize"]);
    _hasCustomVideoMode = [self addVideoMode:customSize to:videoModes];
    _videoModes = [NSArray arrayWithArray:videoModes];
}

- (BOOL)addVideoMode:(CGSize)size to:(NSMutableArray<NSValue*>*)videoModes {
    if (size.width <= 0 || size.height <= 0) {
        return NO;
    }
    NSValue *value = [NSValue valueWithCGSize:size];
    if (![videoModes containsObject:value]) {
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

- (void)layoutSubviews {
    [super layoutSubviews];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self initVideoModes];
    });

    if (CGSizeEqualToSize(_screenSize, CGSizeZero)) {
        return;
    }

    // Resize screen view after updating constraints
    CGRect viewBounds = self.bounds;
    BOOL usesEdgeLayoutBounds = [self screenSizeMatchesEdgePreset:_screenSize];
    BOOL usesSafeLayoutBounds = [self screenSizeMatchesSafeAreaPreset:_screenSize];
    BOOL usesDynamicLayoutBounds = usesEdgeLayoutBounds || usesSafeLayoutBounds;
    if (usesSafeLayoutBounds) {
        viewBounds = [self safeLayoutBoundsWithinBounds:viewBounds];
    }
    CGSize screenSize = _screenSize;
    CGFloat screenScale = MIN(viewBounds.size.width / screenSize.width, viewBounds.size.height / screenSize.height);
    NSString *screenFilter = [[NSUserDefaults standardUserDefaults] stringForKey:@"screenFilter"];
    if (!usesDynamicLayoutBounds && [screenFilter isEqualToString:kCAFilterNearest] && screenScale > 1.0) {
        screenScale = floor(screenScale);
    } else if (!usesDynamicLayoutBounds && screenScale > 1.0 && screenScale <= 1.1) {
        screenScale = 1.0;
    }

    _screenBounds = CGRectMake(0, 0, screenSize.width * screenScale, screenSize.height * screenScale);
    _screenBounds.origin.x = viewBounds.origin.x + (viewBounds.size.width - _screenBounds.size.width)/2;
    if (usesSafeLayoutBounds) {
        _screenBounds.origin.y = viewBounds.origin.y + (viewBounds.size.height - _screenBounds.size.height)/2;
    }
    if (usesSafeLayoutBounds) {
        _screenBounds = [self integralRectInsideBounds:_screenBounds bounds:viewBounds];
    } else {
        _screenBounds = CGRectIntegral(_screenBounds);
    }

    if (!usesSafeLayoutBounds && [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad && (viewBounds.size.height - _screenBounds.size.height) >= 30.0) {
        // move under multitasking indicator on iPad
        _screenBounds.origin.y += 30;
    }
    videoLayer.frame = _screenBounds;
    _screenBounds.origin.y += self.frame.origin.y;
    BOOL scaleIsIntegral = (floor(screenScale) == screenScale);
    if (scaleIsIntegral) screenFilter = kCAFilterNearest;
    videoLayer.magnificationFilter = screenFilter;
    videoLayer.minificationFilter = screenFilter;
}

- (void)setScreenSize:(CGSize)screenSize {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self setScreenSize:screenSize];
        });
        return;
    }
    
    _screenSize = screenSize;
    [self updateConstraints];
    [self setNeedsLayout];
}

- (void)updateConstraints {
    [super updateConstraints];
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }
    CGFloat scale = _screenSize.height / (self.superview.bounds.size.height * nativeScale);
    BOOL matchesDynamicLayoutPreset = [self screenSizeMatchesEdgePreset:_screenSize] || [self screenSizeMatchesSafeAreaPreset:_screenSize];
    BOOL wantsMargins = !matchesDynamicLayoutPreset && scale > 1.0 && floor(scale) != scale;
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
    UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
    if (@available(iOS 11, *)) {
        safeAreaInsets = self.safeAreaInsets;
    }
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        CGFloat safeInset = MAX(MAX(safeAreaInsets.top, safeAreaInsets.bottom), MAX(safeAreaInsets.left, safeAreaInsets.right));
        return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safeInset, safeInset, safeInset, safeInset));
    }
    if (landscape && self.bounds.size.width < self.bounds.size.height) {
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

- (CGRect)integralRectInsideBounds:(CGRect)rect bounds:(CGRect)bounds {
    CGRect integralRect = CGRectMake(ceil(rect.origin.x),
                                     ceil(rect.origin.y),
                                     floor(rect.size.width),
                                     floor(rect.size.height));
    integralRect.size.width = MIN(integralRect.size.width, CGRectGetMaxX(bounds) - integralRect.origin.x);
    integralRect.size.height = MIN(integralRect.size.height, CGRectGetMaxY(bounds) - integralRect.origin.y);
    return integralRect;
}

- (CGSize)videoSizeForPreset:(NSString *)preset {
    if (![NSThread isMainThread]) {
        __block CGSize presetSize;
        dispatch_sync(dispatch_get_main_queue(), ^{
            presetSize = [self videoSizeForPreset:preset];
        });
        return presetSize;
    }

    if ([preset isEqualToString:B2VideoSizePresetStandard]) {
        return [self videoSizeForSafeLayoutWithDivisor:2.0 landscape:NO];
    } else if ([preset isEqualToString:B2VideoSizePresetLarge]) {
        return [self videoSizeForEdgeLayoutWithDivisor:4.0 landscape:NO];
    } else if ([preset isEqualToString:B2VideoSizePresetStandardLandscape]) {
        return [self videoSizeForSafeLayoutWithDivisor:2.0 landscape:YES];
    } else if ([preset isEqualToString:B2VideoSizePresetLargeLandscape]) {
        return [self videoSizeForEdgeLayoutWithDivisor:4.0 landscape:YES];
    } else {
        return CGSizeZero;
    }
}

- (CGRect)boundsForLandscape:(BOOL)landscape {
    CGRect bounds = self.bounds;
    if (landscape && bounds.size.width < bounds.size.height) {
        bounds.size = CGSizeMake(bounds.size.height, bounds.size.width);
    }
    return bounds;
}

- (CGSize)videoSizeForEdgeLayoutWithDivisor:(CGFloat)divisor landscape:(BOOL)landscape {
    if (![NSThread isMainThread]) {
        __block CGSize presetSize;
        dispatch_sync(dispatch_get_main_queue(), ^{
            presetSize = [self videoSizeForEdgeLayoutWithDivisor:divisor landscape:landscape];
        });
        return presetSize;
    }

    CGRect bounds = [self boundsForLandscape:landscape];
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }
    uint32_t w = (uint32_t)(bounds.size.width * nativeScale / divisor) &~ 1;
    uint32_t h = (uint32_t)(bounds.size.height * nativeScale / divisor) &~ 1;
    return CGSizeMake(w, h);
}

- (BOOL)screenSizeMatchesEdgePreset:(CGSize)screenSize {
    if (CGSizeEqualToSize(screenSize, CGSizeZero)) {
        return NO;
    }

    const CGFloat divisors[] = {1.0, 2.0, 4.0};
    for (NSUInteger i = 0; i < sizeof(divisors) / sizeof(divisors[0]); i++) {
        CGSize presetSize = [self videoSizeForEdgeLayoutWithDivisor:divisors[i] landscape:NO];
        if ((uint32_t)screenSize.width == (uint32_t)presetSize.width && (uint32_t)screenSize.height == (uint32_t)presetSize.height) {
            return YES;
        }
    }
    return NO;
}

- (CGSize)videoSizeForSafeLayoutWithDivisor:(CGFloat)divisor landscape:(BOOL)landscape {
    if (![NSThread isMainThread]) {
        __block CGSize presetSize;
        dispatch_sync(dispatch_get_main_queue(), ^{
            presetSize = [self videoSizeForSafeLayoutWithDivisor:divisor landscape:landscape];
        });
        return presetSize;
    }

    CGRect bounds = [self safeLayoutBoundsWithinBounds:[self boundsForLandscape:landscape] landscape:landscape];
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }
    uint32_t w = (uint32_t)(bounds.size.width * nativeScale / divisor) &~ 1;
    uint32_t h = (uint32_t)(bounds.size.height * nativeScale / divisor) &~ 1;
    return CGSizeMake(w, h);
}

- (BOOL)screenSizeMatchesSafeAreaPreset:(CGSize)screenSize {
    if (CGSizeEqualToSize(screenSize, CGSizeZero)) {
        return NO;
    }

    const CGFloat divisors[] = {1.0, 2.0, 4.0};
    for (NSUInteger i = 0; i < sizeof(divisors) / sizeof(divisors[0]); i++) {
        CGSize presetSize = [self videoSizeForSafeLayoutWithDivisor:divisors[i] landscape:NO];
        if ((uint32_t)screenSize.width == (uint32_t)presetSize.width && (uint32_t)screenSize.height == (uint32_t)presetSize.height) {
            return YES;
        }
    }
    return NO;
}

- (void)updateImage:(CGImageRef)newImage {
    CGImageRef oldImage = screenImage;
    CGImageRelease(oldImage);
    screenImage = newImage;
    if (screenImage != nil) {
        CGImageRetain(screenImage);
    }
    [videoLayer performSelectorOnMainThread:@selector(setContents:) withObject:(__bridge id)screenImage waitUntilDone:NO];
}

@end
