//
//  B2ScreenView.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 09/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface B2ScreenView : UIView

@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, assign) CGRect screenBounds;
@property (nonatomic, readonly) NSArray<NSValue*> *videoModes;
@property (nonatomic, readonly) BOOL hasCustomVideoMode;
@property (nonatomic, strong) IBOutletCollection(NSLayoutConstraint) NSArray<NSLayoutConstraint*> *fullScreenConstraints;
@property (nonatomic, strong) IBOutletCollection(NSLayoutConstraint) NSArray<NSLayoutConstraint*> *marginConstraints;

- (CGSize)videoSizeForPreset:(NSString *)preset;
- (CGRect)safeLayoutBoundsWithinBounds:(CGRect)bounds;
- (BOOL)screenSizeMatchesSafeAreaPreset:(CGSize)screenSize;
- (void)updateImage:(nullable CGImageRef)newImage;
- (void)updateCustomSize:(CGSize)customSize;

@end

extern B2ScreenView* _Nullable sharedScreenView;
extern NSString * const B2VideoSizePresetDefaultsKey;
extern NSString * const B2VideoSizePresetStandard;
extern NSString * const B2VideoSizePresetLarge;
extern NSString * const B2VideoSizePresetStandardLandscape;
extern NSString * const B2VideoSizePresetLargeLandscape;

NS_ASSUME_NONNULL_END
