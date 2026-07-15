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

- (BOOL)hasRetinaVideoMode {
    return [UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad && (int)[UIScreen mainScreen].scale >= 2;
}

- (void)initVideoModes {
    NSMutableArray<NSValue*> *videoModes = [[NSMutableArray alloc] initWithCapacity:8];
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    if (screenSize.width < screenSize.height) {
        auto swp = screenSize.width;
        screenSize.width = screenSize.height;
        screenSize.height = swp;
    }
    CGSize landscapeScreenSize = screenSize;
    CGSize portraitScreenSize = CGSizeMake(screenSize.height, screenSize.width);
    
    // current screen size
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{@"screenSize": NSStringFromCGSize(screenSize)}];
    [self addVideoMode:landscapeScreenSize to:videoModes];
    [self addVideoMode:portraitScreenSize to:videoModes];
    if ([self hasRetinaVideoMode]) {
        [self addVideoMode:CGSizeMake(landscapeScreenSize.width * 2, landscapeScreenSize.height * 2) to:videoModes];
        [self addVideoMode:CGSizeMake(portraitScreenSize.width * 2, portraitScreenSize.height * 2) to:videoModes];
    }
    
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
    BOOL usesSafeLayoutBounds = [self screenSizeMatchesSafeAreaPreset:_screenSize];
    if (usesSafeLayoutBounds) {
        viewBounds = [self safeLayoutBoundsWithinBounds:viewBounds];
    }
    CGSize screenSize = _screenSize;
    CGFloat screenScale = MIN(viewBounds.size.width / screenSize.width, viewBounds.size.height / screenSize.height);
    NSString *screenFilter = [[NSUserDefaults standardUserDefaults] stringForKey:@"screenFilter"];
    if ([screenFilter isEqualToString:kCAFilterNearest] && screenScale > 1.0) {
        screenScale = floor(screenScale);
    } else if (screenScale > 1.0 && screenScale <= 1.1) {
        screenScale = 1.0;
    }

    _screenBounds = CGRectMake(0, 0, screenSize.width * screenScale, screenSize.height * screenScale);
    _screenBounds.origin.x = viewBounds.origin.x + (viewBounds.size.width - _screenBounds.size.width)/2;
    if (usesSafeLayoutBounds) {
        _screenBounds.origin.y = viewBounds.origin.y + (viewBounds.size.height - _screenBounds.size.height)/2;
    }
    _screenBounds = CGRectIntegral(_screenBounds);

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
    CGFloat scale = _screenSize.height / self.superview.bounds.size.height;
    BOOL wantsMargins = ![self screenSizeMatchesSafeAreaPreset:_screenSize] && scale > 1.0 && floor(scale) != scale;
    if (wantsMargins) {
        [NSLayoutConstraint deactivateConstraints:self.fullScreenConstraints];
        [NSLayoutConstraint activateConstraints:self.marginConstraints];
    } else {
        [NSLayoutConstraint deactivateConstraints:self.marginConstraints];
        [NSLayoutConstraint activateConstraints:self.fullScreenConstraints];
    }
}

- (CGRect)safeLayoutBoundsWithinBounds:(CGRect)bounds {
    UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
    if (@available(iOS 11, *)) {
        safeAreaInsets = self.safeAreaInsets;
    }
    CGFloat safeInset = MAX(MAX(safeAreaInsets.top, safeAreaInsets.bottom), MAX(safeAreaInsets.left, safeAreaInsets.right));
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safeInset, safeInset, safeInset, safeInset));
}

- (BOOL)screenSizeMatchesSafeAreaPreset:(CGSize)screenSize {
    if (CGSizeEqualToSize(screenSize, CGSizeZero)) {
        return NO;
    }
    
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }
    
    CGRect safeBounds = [self safeLayoutBoundsWithinBounds:self.bounds];
    CGSize safePixelSize = CGSizeMake(safeBounds.size.width * nativeScale, safeBounds.size.height * nativeScale);
    const CGFloat divisors[] = {1.0, 2.0, 4.0};
    for (NSUInteger i = 0; i < sizeof(divisors) / sizeof(divisors[0]); i++) {
        uint32_t w = (uint32_t)(safePixelSize.width / divisors[i]) &~ 1;
        uint32_t h = (uint32_t)(safePixelSize.height / divisors[i]) &~ 1;
        if ((uint32_t)screenSize.width == w && (uint32_t)screenSize.height == h) {
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
