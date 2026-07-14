//
//  B2ViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 08/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import "B2ViewController.h"
#import "B2AppDelegate.h"
#import "B2ScreenView.h"
#import "B2SettingsViewController.h"
#import "KBKeyboardView.h"
#import "KBKeyboardLayout.h"
#import "B2TouchScreen.h"
#import "B2TrackPad.h"
#include "sysdeps.h"
#include "adb.h"

#ifdef __IPHONE_13_4
@interface B2ViewController (PointerInteraction) <UIPointerInteractionDelegate>

@end
#endif

static B2ViewController *_sharedB2ViewController = nil;

@implementation B2ViewController
{
    KBKeyboardView *keyboardView;
    UISwipeGestureRecognizer *showKeyboardGesture, *hideKeyboardGesture;
    UIControl *pointingDeviceView;
    #ifdef __IPHONE_13_4
    UIPointerInteraction *pointerInteraction;
    #endif
    
    // interactive screen resizing
    NSArray<UIGestureRecognizer*> *resizeGestures;
    CGSize initialScreenSize;
}


- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == NSSelectorFromString(@"_performClose:")) {
        // Blocks Command-W from closing all of Basilisk II
        return true;
    }
    return [super canPerformAction:action withSender:sender];
}


+ (instancetype)sharedViewController {
    return _sharedB2ViewController;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self installKeyboardGestures];
    _sharedB2ViewController = self;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (void)unwindToMainScreen:(UIStoryboardSegue*)segue {
    [[B2AppDelegate sharedInstance] startEmulator];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[B2SettingsViewController class]] && [sender isKindOfClass:[NSString class]]) {
        // open specific settings page
        B2SettingsViewController *svc = (B2SettingsViewController*)segue.destinationViewController;
        svc.selectedSetting = (NSString*)sender;
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if (self.keyboardVisible) {
        [self setKeyboardVisible:NO animated:NO];
        [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
            [self setKeyboardVisible:YES animated:YES];
        }];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    [self setUpPointingDevice];
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:@"trackpad" options:0 context:NULL];
}

- (void)viewDidDisappear:(BOOL)animated {
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"trackpad"];
}

- (void)setUpPointingDevice {
    if (pointingDeviceView) {
        [pointingDeviceView removeFromSuperview];
        pointingDeviceView = nil;
    }
    BOOL useTrackPad = [[NSUserDefaults standardUserDefaults] boolForKey:@"trackpad"];
    Class pointingDeviceClass = useTrackPad ? [B2TrackPad class] : [B2TouchScreen class];
    pointingDeviceView = [[pointingDeviceClass alloc] initWithFrame:self.view.bounds];
    [self.view insertSubview:pointingDeviceView aboveSubview:sharedScreenView];
    if (@available(iOS 13.4, *)) {
        pointerInteraction = [[UIPointerInteraction alloc] initWithDelegate:self];
        [pointingDeviceView addInteraction:pointerInteraction];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    pointingDeviceView.frame = self.view.bounds;
    [sharedScreenView setNeedsUpdateConstraints];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if (object == [NSUserDefaults standardUserDefaults]) {
        if ([keyPath isEqualToString:@"keyboardLayout"] && keyboardView != nil) {
            BOOL keyboardWasVisible = self.keyboardVisible;
            [self setKeyboardVisible:NO animated:NO];
            [keyboardView removeFromSuperview];
            keyboardView = nil;
            if (keyboardWasVisible) {
                [self setKeyboardVisible:YES animated:NO];
            }
        } else if ([keyPath isEqualToString:@"trackpad"]) {
            [self setUpPointingDevice];
        }
    }
}

#pragma mark - Settings

- (void)showSettings:(id)sender {
    [self performSegueWithIdentifier:@"settings" sender:sender];
}

#pragma mark - Interactive Resizing

- (void)startChoosingCustomSizeUI {
    [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
    sharedScreenView.screenSize = sharedScreenView.videoModes.lastObject.CGSizeValue;
    self.keyboardVisible = YES;
    pointingDeviceView.userInteractionEnabled = NO;
    // pinch to scale
    UIPinchGestureRecognizer *pinchGestureRecognizer = [UIPinchGestureRecognizer new];
    [pinchGestureRecognizer addTarget:self action:@selector(handleResizePinch:)];
    // double-tap for full size
    UITapGestureRecognizer *tapGestureRecognizer = [UITapGestureRecognizer new];
    tapGestureRecognizer.numberOfTapsRequired = 2;
    [tapGestureRecognizer addTarget:self action:@selector(handleResizeTap:)];
    resizeGestures = @[pinchGestureRecognizer, tapGestureRecognizer];
    for (UIGestureRecognizer *recognizer in resizeGestures) {
        [sharedScreenView addGestureRecognizer:recognizer];
    }
    [self updateInteractiveScreenResize:sharedScreenView.screenSize];
    _helpView.hidden = NO;
}

- (IBAction)endChoosingCustomSizeUI:(id)sender {
    self.keyboardVisible = NO;
    pointingDeviceView.userInteractionEnabled = YES;
    for (UIGestureRecognizer *recognizer in resizeGestures) {
        [sharedScreenView removeGestureRecognizer:recognizer];
    }
    resizeGestures = nil;
    _helpView.hidden = YES;
    
    CGSize newScreenSize = sharedScreenView.screenSize;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:NSStringFromCGSize(newScreenSize) forKey:@"videoSize"];
    [sharedScreenView updateCustomSize:newScreenSize];
    [sharedScreenView updateImage:nil];
    [self showSettings:@"graphicsAndSound"];
}

- (void)handleResizePinch:(UIPinchGestureRecognizer*)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        initialScreenSize = sharedScreenView.screenSize;
    }
    if (recognizer.state == UIGestureRecognizerStateChanged && recognizer.numberOfTouches == 2) {
        CGPoint firstPoint = [recognizer locationOfTouch:0 inView:recognizer.view];
        CGPoint secondPoint = [recognizer locationOfTouch:1 inView:recognizer.view];
        
        double angle = atan2(abs(secondPoint.y - firstPoint.y), abs(secondPoint.x - firstPoint.x));
        CGFloat hScale = recognizer.scale;
        CGFloat vScale = recognizer.scale;
        if (angle <= 0.3) {
            // resize horizontally
            vScale = 1.0;
        } else if (angle >= 1.3) {
            // resize vertically
            hScale = 1.0;
        }
        [self updateInteractiveScreenResize:CGSizeMake(initialScreenSize.width * hScale, initialScreenSize.height * vScale)];
    }
}

- (void)handleResizeTap:(UITapGestureRecognizer*)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        CGSize fullSize = sharedScreenView.bounds.size;
        if (self.keyboardVisible) {
            fullSize.height -= keyboardView.bounds.size.height;
        }
        [self updateInteractiveScreenResize:fullSize];
    }
}

- (void)updateInteractiveScreenResize:(CGSize)size {
    uint32_t w = (uint32_t)size.width &~ 1;
    uint32_t h = (uint32_t)size.height &~ 1;
    if (w < 240 || h < 240 || w * h > 3840 * 2160) {
        // invalid size
        return;
    }
    size = CGSizeMake(w, h);
    [sharedScreenView setScreenSize:size];
    UIGraphicsBeginImageContext(size);
    [[UIImage imageNamed:@"desktop"] drawInRect:CGRectMake(0, 0, size.width, size.height)];
    [sharedScreenView updateImage:UIGraphicsGetImageFromCurrentImageContext().CGImage];
    UIGraphicsPopContext();
    _helpLabel.text = [NSString stringWithFormat:L(@"settings.gfx.size.customize.help"), (int)size.width, (int)size.height];
}

#pragma mark - Keyboard

- (void)installKeyboardGestures {
    showKeyboardGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(showKeyboard:)];
    showKeyboardGesture.direction = UISwipeGestureRecognizerDirectionUp;
    showKeyboardGesture.numberOfTouchesRequired = 2;
    [self.view addGestureRecognizer:showKeyboardGesture];
    
    hideKeyboardGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard:)];
    hideKeyboardGesture.direction = UISwipeGestureRecognizerDirectionDown;
    hideKeyboardGesture.numberOfTouchesRequired = 2;
    [self.view addGestureRecognizer:hideKeyboardGesture];
}

- (BOOL)isKeyboardVisible {
    return keyboardView != nil && CGRectIntersectsRect(keyboardView.frame, self.view.bounds) && !keyboardView.hidden;
}

- (void)setKeyboardVisible:(BOOL)keyboardVisible {
    [self setKeyboardVisible:keyboardVisible animated:YES];
}

- (void)showKeyboard:(id)sender {
    [self setKeyboardVisible:YES animated:YES];
}

- (void)hideKeyboard:(id)sender {
    [self setKeyboardVisible:NO animated:YES];
}

- (void)setKeyboardVisible:(BOOL)visible animated:(BOOL)animated {
    if (self.keyboardVisible == visible) {
        return;
    }
    
    if (visible) {
        [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:@"keyboardLayout" options:0 context:NULL];
        [self loadKeyboardView];
        if (keyboardView.layout == nil) {
            [keyboardView removeFromSuperview];
            return;
        }
        [self.view addSubview:keyboardView];
        keyboardView.hidden = NO;
        CGRect finalFrame = CGRectMake(0.0, self.view.bounds.size.height - keyboardView.bounds.size.height, keyboardView.bounds.size.width, keyboardView.bounds.size.height);
        if (animated) {
            keyboardView.frame = CGRectOffset(finalFrame, 0.0, finalFrame.size.height);
            [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                keyboardView.frame = finalFrame;
            } completion:nil];
        } else {
            keyboardView.frame = finalFrame;
        }
    } else {
        [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"keyboardLayout"];
        if (animated) {
            CGRect finalFrame = CGRectMake(0.0, self.view.bounds.size.height, keyboardView.bounds.size.width, keyboardView.bounds.size.height);
            [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                keyboardView.frame = finalFrame;
            } completion:^(BOOL finished) {
                if (finished) {
                    keyboardView.hidden = YES;
                }
            }];
        } else {
            keyboardView.hidden = YES;
        }
    }
}

- (void)loadKeyboardView {
    if (keyboardView != nil && keyboardView.bounds.size.width != self.view.bounds.size.width) {
        // keyboard needs resizing
        [keyboardView removeFromSuperview];
        keyboardView = nil;
    }
    
    if (keyboardView == nil) {
        UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
        if (@available(iOS 11, *)) {
            safeAreaInsets = self.view.safeAreaInsets;
        }
        keyboardView = [[KBKeyboardView alloc] initWithFrame:self.view.bounds safeAreaInsets:safeAreaInsets];
        keyboardView.layout = [self keyboardLayout];
        keyboardView.delegate = self;
    }
}

- (KBKeyboardLayout*)keyboardLayout {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *layoutName = [defaults stringForKey:@"keyboardLayout"];
    NSString *layoutPath = [[[B2AppDelegate sharedInstance] userKeyboardLayoutsPath] stringByAppendingPathComponent:layoutName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:layoutPath]) {
        layoutPath = [[NSBundle mainBundle] pathForResource:layoutName ofType:nil inDirectory:@"Keyboard Layouts"];
    }
    if (layoutPath == nil) {
        NSLog(@"Layout not found: %@", layoutPath);
    }
    return layoutPath ? [[KBKeyboardLayout alloc] initWithContentsOfFile:layoutPath] : nil;
}

- (void)keyDown:(int)scancode {
    ADBKeyDown(scancode);
}

- (void)keyUp:(int)scancode {
    ADBKeyUp(scancode);
}

@end


#ifdef __IPHONE_13_4
@implementation B2ViewController (PointerInteraction)

- (Point)mouseLocForCGPoint:(CGPoint)point {
    Point mouseLoc;
    CGRect screenBounds = sharedScreenView.screenBounds;
    CGSize screenSize = sharedScreenView.screenSize;
    mouseLoc.h = (point.x - screenBounds.origin.x) * (screenSize.width/screenBounds.size.width);
    mouseLoc.v = (point.y - screenBounds.origin.y) * (screenSize.height/screenBounds.size.height);
    return mouseLoc;
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction regionForRequest:(UIPointerRegionRequest *)request defaultRegion:(UIPointerRegion *)defaultRegion  API_AVAILABLE(ios(13.4)){
    if (request != nil && [B2AppDelegate sharedInstance].emulatorRunning) {
        ADBSetRelMouseMode(false);
        Point mouseLoc = [self mouseLocForCGPoint:request.location];
        ADBMouseMoved(mouseLoc.h, mouseLoc.v);
    }
    return defaultRegion;
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region API_AVAILABLE(ios(13.4)) {
    return [UIPointerStyle hiddenPointerStyle];
}

@end
#endif
