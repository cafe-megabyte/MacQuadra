//
//  DefaultSceneDelegate.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 2024-02-09.
//  Copyright © 2024 namedfork. All rights reserved.
//

#import "DefaultSceneDelegate.h"
#import "B2AppDelegate.h"
#import "B2ScreenView.h"
#import "B2ViewController.h"

API_AVAILABLE(ios(13.0))
@interface DefaultSceneDelegate ()

- (void)destroyOtherSessionsExceptSession:(UISceneSession *)session;

@end

@implementation DefaultSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) {
        [NSException raise:NSInternalInconsistencyException format:@"Expected scene of type UIWindowScene but got an unexpected type"];
    }

    B2AppDelegate *appDelegate = B2AppDelegate.sharedInstance;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window = window;

    appDelegate.window = window;
    window.rootViewController = [[UIStoryboard storyboardWithName:@"Main" bundle:NSBundle.mainBundle] instantiateInitialViewController];
    [window makeKeyAndVisible];

    UIApplicationShortcutItem *shortcutItem = connectionOptions.shortcutItem;
    if (shortcutItem != nil) {
        [appDelegate application:UIApplication.sharedApplication performActionForShortcutItem:shortcutItem completionHandler:^(__unused BOOL succeeded) {}];
    }

    [self destroyOtherSessionsExceptSession:session];
}

- (void)destroyOtherSessionsExceptSession:(UISceneSession *)session {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindowSceneDestructionRequestOptions *options = [[UIWindowSceneDestructionRequestOptions alloc] init];
    options.windowDismissalAnimation = UIWindowSceneDismissalAnimationDecline;

    for (UISceneSession *otherSession in app.openSessions) {
        if ([otherSession isEqual:session] || ![otherSession.configuration.name isEqualToString:@"Default"]) {
            continue;
        }

        UIScene *scene = otherSession.scene;
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            UIWindow *window = windowScene.windows.firstObject;
            if (window != nil) {
                [window.rootViewController.view removeFromSuperview];
                window.backgroundColor = UIColor.darkGrayColor;
                [app requestSceneSessionRefresh:otherSession];
            }
        }

        [app requestSceneSessionDestruction:otherSession options:options errorHandler:nil];
        // window will remain visible until window switcher is dismissed!
    }
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    [sharedScreenView restoreActiveLayoutFrameIfNeeded];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [sharedScreenView restoreActiveLayoutFrameIfNeeded];
    dispatch_async(dispatch_get_main_queue(), ^{
        [B2AppDelegate.sharedInstance activateMainScreen];
    });
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler {
    [B2AppDelegate.sharedInstance application:UIApplication.sharedApplication performActionForShortcutItem:shortcutItem completionHandler:completionHandler];
}

- (void)windowScene:(UIWindowScene *)windowScene didUpdateEffectiveGeometry:(UIWindowSceneGeometry *)previousEffectiveGeometry API_AVAILABLE(ios(16.0)) {
    (void)windowScene;
    (void)previousEffectiveGeometry;
    [[B2ViewController sharedViewController] emulatorStartGeometryDidChange];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    for (UIOpenURLContext *context in URLContexts) {
        [B2AppDelegate.sharedInstance application:UIApplication.sharedApplication openURL:context.URL options:@{}];
    }
}

@end
