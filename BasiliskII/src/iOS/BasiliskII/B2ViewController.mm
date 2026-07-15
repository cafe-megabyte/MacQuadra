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

typedef NS_ENUM(NSInteger, B2ResizeAreaMode) {
    B2ResizeAreaModeEdge,
    B2ResizeAreaModeSafeArea,
};

typedef NS_ENUM(NSInteger, B2ResizeScaleMode) {
    B2ResizeScaleMode1x,
    B2ResizeScaleMode2x,
    B2ResizeScaleMode4x,
};

@interface B2ViewController () <UITextFieldDelegate>

@end

@implementation B2ViewController
{
    KBKeyboardView *keyboardView;
    UISwipeGestureRecognizer *showKeyboardGesture, *hideKeyboardGesture;
    UIScreenEdgePanGestureRecognizer *showKeyboardLeftEdgeGesture, *showKeyboardRightEdgeGesture;
    UIControl *pointingDeviceView;
    #ifdef __IPHONE_13_4
    id pointerInteraction;
    #endif
    
    // interactive screen resizing
    NSArray<UIGestureRecognizer*> *resizeGestures;
    CGSize initialScreenSize;
    B2ResizeAreaMode resizeAreaMode;
    B2ResizeScaleMode resizeScaleMode;
    UIVisualEffectView *resizeControlsView;
    UISegmentedControl *resizeAreaControl;
    UISegmentedControl *resizeScaleControl;
    UISegmentedControl *resizeModeControl;
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
    self.keyboardVisible = NO;
    [self setKeyboardGesturesEnabled:NO];
    resizeAreaMode = B2ResizeAreaModeEdge;
    resizeScaleMode = B2ResizeScaleMode2x;
    [self installResizeControls];
    pointingDeviceView.userInteractionEnabled = NO;
    // pinch to scale
    UIPinchGestureRecognizer *pinchGestureRecognizer = [UIPinchGestureRecognizer new];
    [pinchGestureRecognizer addTarget:self action:@selector(handleResizePinch:)];
    resizeGestures = @[pinchGestureRecognizer];
    for (UIGestureRecognizer *recognizer in resizeGestures) {
        [sharedScreenView addGestureRecognizer:recognizer];
    }
    [self applyResizeControls];
    _helpView.hidden = NO;
}

- (IBAction)endChoosingCustomSizeUI:(id)sender {
    self.keyboardVisible = NO;
    [self setKeyboardGesturesEnabled:YES];
    [resizeControlsView removeFromSuperview];
    resizeControlsView = nil;
    resizeAreaControl = nil;
    resizeScaleControl = nil;
    resizeModeControl = nil;
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
        resizeAreaControl.selectedSegmentIndex = UISegmentedControlNoSegment;
        resizeScaleControl.selectedSegmentIndex = UISegmentedControlNoSegment;
        resizeModeControl.selectedSegmentIndex = 1;
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

- (void)installResizeControls {
    [resizeControlsView removeFromSuperview];
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    resizeControlsView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    resizeControlsView.translatesAutoresizingMaskIntoConstraints = NO;
    resizeControlsView.layer.cornerRadius = 8.0;
    resizeControlsView.clipsToBounds = YES;
    
    resizeAreaControl = [[UISegmentedControl alloc] initWithItems:@[L(@"settings.gfx.size.customize.edge"), L(@"settings.gfx.size.customize.safe")]];
    resizeAreaControl.selectedSegmentIndex = resizeAreaMode;
    [resizeAreaControl addTarget:self action:@selector(resizeAreaChanged:) forControlEvents:UIControlEventValueChanged];
    
    resizeScaleControl = [[UISegmentedControl alloc] initWithItems:@[@"1×", @"2×", @"4×"]];
    resizeScaleControl.selectedSegmentIndex = resizeScaleMode;
    [resizeScaleControl addTarget:self action:@selector(resizeScaleChanged:) forControlEvents:UIControlEventValueChanged];
    
    resizeModeControl = [[UISegmentedControl alloc] initWithItems:@[L(@"settings.gfx.size.customize.input"), L(@"settings.gfx.size.customize.manual")]];
    resizeModeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    [resizeModeControl addTarget:self action:@selector(resizeModeChanged:) forControlEvents:UIControlEventValueChanged];
    
    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[resizeAreaControl, resizeScaleControl, resizeModeControl]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.spacing = 8.0;
    stackView.layoutMargins = UIEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
    stackView.layoutMarginsRelativeArrangement = YES;
    
    [resizeControlsView.contentView addSubview:stackView];
    [self.view addSubview:resizeControlsView];
    
    NSLayoutYAxisAnchor *bottomAnchor = self.view.bottomAnchor;
    if (@available(iOS 11, *)) {
        bottomAnchor = self.view.safeAreaLayoutGuide.bottomAnchor;
    }
    [NSLayoutConstraint activateConstraints:@[
        [stackView.leadingAnchor constraintEqualToAnchor:resizeControlsView.contentView.leadingAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:resizeControlsView.contentView.trailingAnchor],
        [stackView.topAnchor constraintEqualToAnchor:resizeControlsView.contentView.topAnchor],
        [stackView.bottomAnchor constraintEqualToAnchor:resizeControlsView.contentView.bottomAnchor],
        [resizeControlsView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [resizeControlsView.bottomAnchor constraintEqualToAnchor:bottomAnchor constant:-16.0],
        [resizeControlsView.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-32.0],
    ]];
}

- (void)resizeAreaChanged:(UISegmentedControl*)sender {
    resizeAreaMode = (B2ResizeAreaMode)sender.selectedSegmentIndex;
    resizeScaleControl.selectedSegmentIndex = resizeScaleMode;
    resizeModeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    [self applyResizeControls];
}

- (void)resizeScaleChanged:(UISegmentedControl*)sender {
    resizeScaleMode = (B2ResizeScaleMode)sender.selectedSegmentIndex;
    resizeAreaControl.selectedSegmentIndex = resizeAreaMode;
    resizeModeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    [self applyResizeControls];
}

- (void)resizeModeChanged:(UISegmentedControl*)sender {
    resizeAreaControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    resizeScaleControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    if (sender.selectedSegmentIndex == 0) {
        [self showResizeInputDialog];
    }
}

- (void)applyResizeControls {
    [self updateInteractiveScreenResize:[self screenSizeForResizeControls]];
}

- (CGSize)screenSizeForResizeControls {
    CGSize baseSize = [self baseSizeForResizeAreaMode:resizeAreaMode];
    CGFloat divisor = [self divisorForResizeScaleMode:resizeScaleMode];
    return CGSizeMake(baseSize.width / divisor, baseSize.height / divisor);
}

- (CGSize)baseSizeForResizeAreaMode:(B2ResizeAreaMode)areaMode {
    CGRect bounds = self.view.bounds;
    if (areaMode == B2ResizeAreaModeSafeArea) {
        UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
        if (@available(iOS 11, *)) {
            safeAreaInsets = self.view.safeAreaInsets;
        }
        CGFloat safeInset = MAX(MAX(safeAreaInsets.top, safeAreaInsets.bottom), MAX(safeAreaInsets.left, safeAreaInsets.right));
        bounds = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safeInset, safeInset, safeInset, safeInset));
    }
    
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    if (nativeScale <= 0.0) {
        nativeScale = [UIScreen mainScreen].scale;
    }
    return CGSizeMake(bounds.size.width * nativeScale, bounds.size.height * nativeScale);
}

- (CGFloat)divisorForResizeScaleMode:(B2ResizeScaleMode)scaleMode {
    switch (scaleMode) {
        case B2ResizeScaleMode1x:
            return 1.0;
        case B2ResizeScaleMode2x:
            return 2.0;
        case B2ResizeScaleMode4x:
            return 4.0;
    }
    return 2.0;
}

- (void)showResizeInputDialog {
    self.keyboardVisible = NO;
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"settings.gfx.size.customize.title")
                                                                             message:L(@"settings.gfx.size.customize.message")
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    __block UITextField *widthField;
    __block UITextField *heightField;
    CGSize screenSize = sharedScreenView.screenSize;
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = L(@"settings.gfx.size.customize.width");
        textField.text = [NSString stringWithFormat:@"%d", (int)screenSize.width];
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.delegate = self;
        widthField = textField;
    }];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = L(@"settings.gfx.size.customize.height");
        textField.text = [NSString stringWithFormat:@"%d", (int)screenSize.height];
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.delegate = self;
        heightField = textField;
    }];
    
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        self->resizeModeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        CGSize inputSize = CGSizeMake(widthField.text.integerValue, heightField.text.integerValue);
        if (![self updateInteractiveScreenResize:inputSize]) {
            self->resizeModeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
        }
    }]];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (BOOL)updateInteractiveScreenResize:(CGSize)size {
    uint32_t w = (uint32_t)size.width &~ 1;
    uint32_t h = (uint32_t)size.height &~ 1;
    if (w < 240 || h < 240 || w * h > 3840 * 2160) {
        // invalid size
        return NO;
    }
    size = CGSizeMake(w, h);
    [sharedScreenView setScreenSize:size];
    UIGraphicsBeginImageContext(size);
    [[UIImage imageNamed:@"desktop"] drawInRect:CGRectMake(0, 0, size.width, size.height)];
    [sharedScreenView updateImage:UIGraphicsGetImageFromCurrentImageContext().CGImage];
    UIGraphicsPopContext();
    _helpLabel.text = [NSString stringWithFormat:L(@"settings.gfx.size.customize.help"), (int)size.width, (int)size.height];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [string rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

#pragma mark - Keyboard

- (void)setKeyboardGesturesEnabled:(BOOL)enabled {
    showKeyboardGesture.enabled = enabled;
    showKeyboardLeftEdgeGesture.enabled = enabled;
    showKeyboardRightEdgeGesture.enabled = enabled;
    hideKeyboardGesture.enabled = enabled;
}

- (void)installKeyboardGestures {
    showKeyboardGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(showKeyboard:)];
    showKeyboardGesture.direction = UISwipeGestureRecognizerDirectionUp;
    showKeyboardGesture.numberOfTouchesRequired = 2;
    [self.view addGestureRecognizer:showKeyboardGesture];

    showKeyboardLeftEdgeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(showKeyboard:)];
    showKeyboardLeftEdgeGesture.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:showKeyboardLeftEdgeGesture];

    showKeyboardRightEdgeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(showKeyboard:)];
    showKeyboardRightEdgeGesture.edges = UIRectEdgeRight;
    [self.view addGestureRecognizer:showKeyboardRightEdgeGesture];
    
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
                self->keyboardView.frame = finalFrame;
            } completion:nil];
        } else {
            keyboardView.frame = finalFrame;
        }
    } else {
        [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"keyboardLayout"];
        if (animated) {
            CGRect finalFrame = CGRectMake(0.0, self.view.bounds.size.height, keyboardView.bounds.size.width, keyboardView.bounds.size.height);
            [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self->keyboardView.frame = finalFrame;
            } completion:^(BOOL finished) {
                if (finished) {
                    self->keyboardView.hidden = YES;
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
