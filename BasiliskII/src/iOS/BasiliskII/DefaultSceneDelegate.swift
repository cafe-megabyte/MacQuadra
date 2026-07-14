//
//  DefaultSceneDelegate.swift
//  Mini vMac
//
//  Created by Jesús A. Álvarez on 2024-02-09.
//  Copyright © 2024 namedfork. All rights reserved.
//

import UIKit


@available(iOS 13.0, *)
class DefaultSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow? // keep window reference to be able to set background colour before destroying

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            fatalError("Expected scene of type UIWindowScene but got an unexpected type")
        }
        let appDelegate = B2AppDelegate.shared

        window = UIWindow(windowScene: windowScene)
        if let window {
            appDelegate.window = window
            window.rootViewController = UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController()
            window.makeKeyAndVisible()
        }
        self.destroyOtherSessions(not: session)
    }

    private func destroyOtherSessions(not session: UISceneSession) {
        let app = UIApplication.shared
        let options = UIWindowSceneDestructionRequestOptions()
        options.windowDismissalAnimation = .decline
        for otherSession in app.openSessions.filter({ $0 != session && $0.configuration.name == "Default"}) {
            if let window = (otherSession.scene as? UIWindowScene)?.windows.first {
                window.rootViewController?.view.removeFromSuperview()
                window.backgroundColor = .darkGray
                app.requestSceneSessionRefresh(otherSession)
            }
            app.requestSceneSessionDestruction(otherSession, options: options)
            // window will remain visible until window switcher is dismissed!
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {

    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // show settings if emulator is not running
        let appDelegate = B2AppDelegate.shared
        guard let rootViewController = appDelegate.window.rootViewController as? B2ViewController else {
            return
        }
        if !appDelegate.emulatorRunning && rootViewController.presentedViewController == nil {
            rootViewController.perform(#selector(B2ViewController.showSettings(_:)), with: appDelegate, afterDelay: 0.0)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        B2AppDelegate.shared.application(UIApplication.shared, performActionFor: shortcutItem, completionHandler: completionHandler)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for ctx in URLContexts {
            B2AppDelegate.shared.application(UIApplication.shared, open: ctx.url, options: [:])
        }
    }
}
