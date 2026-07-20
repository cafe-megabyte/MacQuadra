//
//  B2AppDelegate.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 08/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import "B2AppDelegate.h"
#import "B2ViewController.h"
#import "B2SettingsViewController.h"
#import "B2ScreenView.h"
#import "B2DocumentsSettingsController.h"
#import "B2PrivateResources.h"
#import "B2DiskImageSnapshots.h"
#import "KBKeyboardView.h"

#include "sysdeps.h"
#include "sys.h"
#include "main.h"

#include "cpu_emulation.h"
#include "macos_util_ios.h"
#include "prefs.h"
#include "rom_patches.h"
#include "timer.h"
#include "xpram.h"
#include "video.h"

#include <mach/mach.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <sys/xattr.h>

extern bool quit_program;

static NSMutableSet *hiddenExtFSFiles = nil;
static NSString * const B2KeyboardLayoutsReadmeFileName = @"README.txt";
static NSString * const B2FileSharingDirectoryName = @"File Sharing";
static NSString * const B2FileSharingDirectoryBookmarkDefaultsKey = @"fileSharingDirectoryBookmark";
static NSString * const B2FileSharingDirectoryDisplayNameDefaultsKey = @"fileSharingDirectoryDisplayName";
static NSString * const B2CustomIconFileName = @"Icon\r";
static BOOL coldRestartRequestedForMacReset = NO;

static NSData *B2DefaultFileSharingIconResourceFork(void)
{
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"FileSharingIcon" withExtension:@"rfork"];
    return url ? [NSData dataWithContentsOfURL:url] : nil;
}

static void B2SetFinderFlagsAtPath(NSString *path, uint16_t flags)
{
    uint8_t finderInfo[32] = {0};
    getxattr(path.fileSystemRepresentation, XATTR_FINDERINFO_NAME, finderInfo, sizeof(finderInfo), 0, 0);
    finderInfo[8] |= (flags >> 8) & 0xff;
    finderInfo[9] |= flags & 0xff;
    setxattr(path.fileSystemRepresentation, XATTR_FINDERINFO_NAME, finderInfo, sizeof(finderInfo), 0, 0);
    setxattr(path.fileSystemRepresentation, "org.BasiliskII.FinderInfo", finderInfo, 16, 0, 0);
}

static void B2HideIconFileAtPath(NSString *iconPath)
{
    B2SetFinderFlagsAtPath(iconPath, 0x4000);
    [[NSURL fileURLWithPath:iconPath] setResourceValue:@YES forKey:NSURLIsHiddenKey error:nil];
}

static void B2InstallDefaultFileSharingIconAtPath(NSString *fileSharingPath)
{
    NSString *iconPath = [fileSharingPath stringByAppendingPathComponent:B2CustomIconFileName];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:iconPath error:nil];
    [fileManager createFileAtPath:iconPath contents:nil attributes:nil];

    NSData *resourceFork = B2DefaultFileSharingIconResourceFork();
    if (resourceFork.length > 0) {
        setxattr(iconPath.fileSystemRepresentation, XATTR_RESOURCEFORK_NAME, resourceFork.bytes, resourceFork.length, 0, 0);
    }

    B2HideIconFileAtPath(iconPath);
    B2SetFinderFlagsAtPath(fileSharingPath, 0x0500);
}

static uint8_t B2AppleModeForConfiguredVideoDepth(void)
{
    switch ([[NSUserDefaults standardUserDefaults] integerForKey:@"videoDepth"]) {
        case 1:
            return 0x80;
        case 2:
            return 0x81;
        case 4:
            return 0x82;
        case 8:
            return 0x83;
        case 16:
            return 0x84;
        case 32:
        default:
            return 0x85;
    }
}

static void B2SyncDisplayXPRAMToConfiguredVideoDepth(void)
{
    // Keep display PRAM aligned with the emulator setting across Mac OS restarts.
    XPRAM[0x56] = 0x42; // 'B'
    XPRAM[0x57] = 0x32; // '2'
    XPRAM[0x58] = B2AppleModeForConfiguredVideoDepth();
    XPRAM[0x59] = 0;
}

bool ShouldHideExtFSFile(const char *path) {
    NSString *fileName = @(path).lastPathComponent;
    if ([fileName hasPrefix:@"."]) {
        return true;
    }
    return [hiddenExtFSFiles containsObject:@(path)] ? true : false;
}

bool GetTypeAndCreatorForFileName(const char *path, uint32_t *type, uint32_t *creator) {
    NSString *ext = @(path).pathExtension;
    if (ext == nil || ext.length == 0)
        return false;
    
    // built-in ext2type table
    static dispatch_once_t onceToken;
    static NSDictionary *ext2type;
    dispatch_once(&onceToken, ^{
        ext2type = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ext2type" ofType:@"plist"]];
    });
    
    // user ext2type table
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *userExt2type = [defaults objectForKey:@"ext2type"];
    if (![userExt2type isKindOfClass:[NSDictionary class]])
        userExt2type = nil;
    
    // value should be 8-byte data or string containing big-endian type and creator (ex: TEXTttxt)
    id data = userExt2type[ext] ?: ext2type[ext];
    if ([data isKindOfClass:[NSString class]]) {
        data = [data dataUsingEncoding:NSMacOSRomanStringEncoding];
    }
    if ([data isKindOfClass:[NSData class]] && [data length] == 8) {
        if (type) {
            *type = OSReadBigInt32([data bytes], 0);
        }
        if (creator) {
            *creator = OSReadBigInt32([data bytes], 4);
        }
        return true;
    }
    return false;
}

static B2AppDelegate *sharedDelegate = nil;

extern "C" void B2RequestColdRestartOnMacReset(void)
{
    coldRestartRequestedForMacReset = YES;
}

extern "C" bool B2ConsumeColdRestartOnMacReset(void)
{
    BOOL requested = coldRestartRequestedForMacReset;
    coldRestartRequestedForMacReset = NO;
    return requested;
}

@interface B2AppDelegate ()

- (void)requestSettingsPresentation;
- (void)showBasiliskSettings:(id)sender;
- (void)updateSettingsModalInPresentation;
- (BOOL)hasConfiguredFileSharingDirectory;
- (NSString *)prepareFileSharingDirectoryForEmulator;
- (NSURL *)resolvedConfiguredFileSharingDirectoryURLAndReturnError:(NSError **)error;
- (BOOL)configuredFileSharingDirectoryIsAvailable;
- (BOOL)directoryExistsAtURL:(NSURL *)url;
- (NSString *)displayNameForFileSharingDirectoryURL:(NSURL *)url;
- (void)stopAccessingFileSharingDirectory;

@end

@implementation B2AppDelegate
{
    NSTimer *redrawTimer, *pramTimer;
    NSThread *emulThread, *tickThread;
    thread_t emulMachThread;
    NSTimeInterval redrawDelay;
    NSData *lastPRAM;
    NSMutableArray *videoModes;
    BOOL settingsRequested;
    BOOL settingsPresentationScheduled;
    BOOL activationInProgress;
    BOOL snapshotPreparationInProgress;
    NSURL *activeFileSharingDirectoryURL;
    BOOL activeFileSharingDirectoryIsSecurityScoped;
}

+ (instancetype)sharedInstance {
    if (sharedDelegate == nil) {
        return (B2AppDelegate*)[UIApplication sharedApplication].delegate;
    }
    return sharedDelegate;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    sharedDelegate = self;
    [self updateSettingsBundleVersionInfo];
    
    // populate documents directory so it shows up in Files
    [self populateDocumentsDirectory];
    [self initEmulator];

    return YES;
}

- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder {
    [super buildMenuWithBuilder:builder];

    if (@available(iOS 13.0, *)) {
        if (builder.system != UIMenuSystem.mainSystem) {
            return;
        }

        UICommand *settingsCommand = [UICommand commandWithTitle:L(@"settings.root.title")
                                                           image:nil
                                                          action:@selector(showBasiliskSettings:)
                                                    propertyList:nil];
        UIMenu *settingsMenu = [UIMenu menuWithTitle:@""
                                               image:nil
                                          identifier:nil
                                             options:UIMenuOptionsDisplayInline
                                            children:@[settingsCommand]];
        [builder insertSiblingMenu:settingsMenu afterMenuForIdentifier:UIMenuPreferences];
    }
}

- (void)updateSettingsBundleVersionInfo {
    NSBundle *bundle = [NSBundle mainBundle];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    id version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([version isKindOfClass:[NSString class]]) {
        [defaults setObject:version forKey:@"app_version"];
    }

    id buildNumber = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if ([buildNumber isKindOfClass:[NSString class]]) {
        [defaults setObject:buildNumber forKey:@"app_build_number"];
    }
}

- (void)populateDocumentsDirectory {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *keyboardLayoutsPath = self.userKeyboardLayoutsPath;
    [fileManager createDirectoryAtPath:keyboardLayoutsPath withIntermediateDirectories:YES attributes:nil error:nil];
    if (![self hasConfiguredFileSharingDirectory]) {
        [fileManager createDirectoryAtPath:self.defaultFileSharingPath withIntermediateDirectories:YES attributes:nil error:nil];
        B2InstallDefaultFileSharingIconAtPath(self.defaultFileSharingPath);
    }

    NSString *readmePath = [keyboardLayoutsPath stringByAppendingPathComponent:B2KeyboardLayoutsReadmeFileName];
    if ([fileManager fileExistsAtPath:readmePath]) {
        return;
    }

    NSString *readme = @"Basilisk II Keyboard Layouts\n"
                       @"============================\n"
                       @"\n"
                       @"This folder is for additional on-screen keyboard layouts.\n"
                       @"\n"
                       @"Put custom keyboard layout files in this folder and make sure their file names end with:\n"
                       @".nfkeyboardlayout\n"
                       @"\n"
                       @"The app will list these files in Settings > Keyboard & Mouse > Keyboard Layout.\n"
                       @"\n"
                       @"You can find compatible layout files here:\n"
                       @"https://github.com/gingerbeardman/artworks-keyboard\n";
    [readme writeToFile:readmePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [self activateMainScreen];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if (url.fileURL) {
        // opening file
        NSString *inboxPath = [self.documentsPath stringByAppendingPathComponent:@"Inbox"];
        if ([url.path.stringByStandardizingPath hasPrefix:inboxPath]) {
            // pre-iOS 11 import through inbox
            [url startAccessingSecurityScopedResource];
            [self importFileToDocuments:url copy:NO];
            [url stopAccessingSecurityScopedResource];
        } else if ([url.path.stringByStandardizingPath hasPrefix:self.documentsPath]) {
            // I'm not sure what to do with this file, pretend nothing happened
        } else if ([options[UIApplicationOpenURLOptionsOpenInPlaceKey] boolValue]) {
            // not in documents - copy
            [url startAccessingSecurityScopedResource];
            [self importFileToDocuments:url copy:YES];
            [url stopAccessingSecurityScopedResource];
        } else {
            return [self importFileToDocuments:url copy:NO];
        }
    }
    return YES;
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    BOOL success = NO;
    if ([shortcutItem.type isEqualToString:@"settings"]) {
        [self requestSettingsPresentation];
        success = YES;
    }
    completionHandler(success);
}

- (void)showBasiliskSettings:(id)sender {
    [self requestSettingsPresentation];
}

- (void)requestSettingsPresentation {
    [[B2ViewController sharedViewController] cancelPendingEmulatorStart];
    settingsRequested = YES;
    settingsPresentationScheduled = YES;
    [self activateMainScreen];
}

- (void)settingsPresentationDidBegin {
    settingsPresentationScheduled = NO;
    [self updateSettingsModalInPresentation];
}

- (void)updateSettingsModalInPresentation {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateSettingsModalInPresentation];
        });
        return;
    }

    if (@available(iOS 13.0, *)) {
        UIViewController *controller = self.window.rootViewController.presentedViewController;
        while (controller != nil) {
            if ([controller isKindOfClass:[B2SettingsViewController class]]) {
                controller.modalInPresentation = !self.emulatorRunning;
                return;
            }
            controller = controller.presentedViewController;
        }
    }
}

- (void)activateMainScreen {
    if (self.window.rootViewController == nil) {
        return;
    }

    UIViewController *rootViewController = self.window.rootViewController;
    if (rootViewController.presentedViewController != nil) {
        return;
    }

    if (settingsRequested) {
        settingsRequested = NO;
        [rootViewController performSelector:@selector(showSettings:) withObject:self afterDelay:0.0];
        return;
    }

    if (settingsPresentationScheduled) {
        return;
    }

    if (activationInProgress || self.emulatorRunning) {
        if (self.emulatorRunning) {
            [sharedScreenView refreshLayout];
        }
        return;
    }

    activationInProgress = YES;
    BOOL preparingResources = [[B2PrivateResources sharedInstance] prepareResourcesIfNeededFromViewController:rootViewController completion:^{
        self->activationInProgress = NO;
        [self bootOrShowSettingsIfNeeded];
    }];
    if (!preparingResources) {
        activationInProgress = NO;
        [self bootOrShowSettingsIfNeeded];
    }
}

- (void)bootOrShowSettingsIfNeeded {
    if (self.emulatorRunning || settingsPresentationScheduled || self.window.rootViewController.presentedViewController != nil) {
        return;
    }

    B2ViewController *viewController = [B2ViewController sharedViewController];
    if (viewController != nil && ![viewController canAutomaticallyStartEmulator]) {
        return;
    }

    if ([[B2PrivateResources sharedInstance] allRequiredResourcesConfigured]) {
        [self startEmulator];
    } else {
        settingsPresentationScheduled = YES;
        [self.window.rootViewController performSelector:@selector(showSettings:) withObject:self afterDelay:0.0];
    }
}

- (BOOL)importFileToDocuments:(NSURL *)url copy:(BOOL)copy {
    if (url.fileURL) {
        // opening file
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *fileName = url.path.lastPathComponent;
        NSString *destinationPath = [self.documentsPath stringByAppendingPathComponent:fileName];
        NSError *error = NULL;
        NSInteger tries = 1;
        while ([fileManager fileExistsAtPath:destinationPath]) {
            NSString *newFileName;
            if (fileName.pathExtension.length > 0) {
                newFileName = [NSString stringWithFormat:@"%@ %d.%@", fileName.stringByDeletingPathExtension, (int)tries, fileName.pathExtension];
            } else {
                newFileName = [NSString stringWithFormat:@"%@ %d", fileName, (int)tries];
            }
            destinationPath = [self.documentsPath stringByAppendingPathComponent:newFileName];
            tries++;
        }
        if (copy) {
            [fileManager copyItemAtPath:url.path toPath:destinationPath error:&error];
        } else {
            [fileManager moveItemAtPath:url.path toPath:destinationPath error:&error];
        }
        if (error) {
            [self showAlertWithTitle:fileName message:error.localizedFailureReason];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:B2DidImportFileNotificationName object:self userInfo:@{@"path": destinationPath}];
    }
    return YES;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlertWithTitle:title message:message];
        });
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:L(@"misc.ok") style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *controller = self.window.rootViewController;
    while (controller.presentedViewController != nil) {
        if ([controller.presentedViewController isKindOfClass:NSClassFromString(@"SFSafariViewController")]) {
            break;
        }
        controller = controller.presentedViewController;
    }
    [controller presentViewController:alert animated:YES completion:nil];
}

- (void)initExtFS:(NSString*)baseDir {
    hiddenExtFSFiles = [NSMutableSet setWithCapacity:8];
}

- (void)addHiddenFiles:(id)paths relativeToPath:(NSString*)baseDir {
    if (paths == nil) return;
    if (![paths isKindOfClass:[NSArray class]]) paths = @[paths];
    [paths enumerateObjectsUsingBlock:^(NSString *path, NSUInteger idx, BOOL *stop) {
        if (![path isKindOfClass:[NSString class]]) return;
        if ([path hasPrefix:@"*"]) path = [path substringFromIndex:1];
        if (![path hasPrefix:@"/"])
            path = [baseDir stringByAppendingPathComponent:path];
        [hiddenExtFSFiles addObject:path.stringByStandardizingPath];
    }];
}

- (BOOL)getFileType:(OSType *)type andCreator:(OSType *)creator forFileName:(NSString *)fileName {
    return GetTypeAndCreatorForFileName(fileName.fileSystemRepresentation, (uint32_t*)type, (uint32_t*)creator);
}

- (BOOL)isSandboxed {
#if TARGET_IPHONE_SIMULATOR
    return YES;
#else
    static dispatch_once_t onceToken;
    static BOOL sandboxed;
    dispatch_once(&onceToken, ^{
        // not sandboxed if parent of documents directory is "mobile"
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject.stringByStandardizingPath;
        sandboxed = ![documentsPath.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"mobile"];
    });
    return sandboxed;
#endif
}

- (NSString *)documentsPath {
    static dispatch_once_t onceToken;
    static NSString *documentsPath;
    dispatch_once(&onceToken, ^{
        documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        if (!self.sandboxed) {
            documentsPath = [documentsPath stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]].stringByStandardizingPath;
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:documentsPath withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    return documentsPath;
}

- (NSString *)defaultFileSharingPath {
    static dispatch_once_t onceToken;
    static NSString *defaultFileSharingPath;
    dispatch_once(&onceToken, ^{
        defaultFileSharingPath = [self.documentsPath stringByAppendingPathComponent:B2FileSharingDirectoryName];
    });
    return defaultFileSharingPath;
}

- (BOOL)hasConfiguredFileSharingDirectory {
    return [[[NSUserDefaults standardUserDefaults] objectForKey:B2FileSharingDirectoryBookmarkDefaultsKey] isKindOfClass:[NSData class]];
}

- (NSString *)fileSharingPath {
    NSURL *url = [self resolvedConfiguredFileSharingDirectoryURLAndReturnError:nil];
    if (url != nil && [self configuredFileSharingDirectoryIsAvailable]) {
        return url.path;
    }
    return self.defaultFileSharingPath;
}

- (BOOL)usingDefaultFileSharingPath {
    return ![self hasConfiguredFileSharingDirectory] || ![self configuredFileSharingDirectoryIsAvailable];
}

- (NSString *)fileSharingDisplayName {
    if (self.usingDefaultFileSharingPath) {
        return self.defaultFileSharingPath.lastPathComponent;
    }

    NSString *displayName = [[NSUserDefaults standardUserDefaults] stringForKey:B2FileSharingDirectoryDisplayNameDefaultsKey];
    if (displayName.length > 0) {
        return displayName;
    }
    return self.fileSharingPath.lastPathComponent;
}

- (NSString *)prepareFileSharingDirectoryForEmulator {
    [self stopAccessingFileSharingDirectory];

    NSError *error = nil;
    NSURL *configuredURL = [self resolvedConfiguredFileSharingDirectoryURLAndReturnError:&error];
    if (configuredURL != nil) {
        BOOL accessing = [configuredURL startAccessingSecurityScopedResource];
        if ([self directoryExistsAtURL:configuredURL]) {
            activeFileSharingDirectoryURL = configuredURL;
            activeFileSharingDirectoryIsSecurityScoped = accessing;
            return activeFileSharingDirectoryURL.path;
        }
        if (accessing) {
            [configuredURL stopAccessingSecurityScopedResource];
        }
    }

    [[NSFileManager defaultManager] createDirectoryAtPath:self.defaultFileSharingPath withIntermediateDirectories:YES attributes:nil error:nil];
    B2InstallDefaultFileSharingIconAtPath(self.defaultFileSharingPath);
    activeFileSharingDirectoryURL = [NSURL fileURLWithPath:self.defaultFileSharingPath isDirectory:YES];
    activeFileSharingDirectoryIsSecurityScoped = NO;
    return self.defaultFileSharingPath;
}

- (BOOL)configuredFileSharingDirectoryIsAvailable {
    NSURL *url = [self resolvedConfiguredFileSharingDirectoryURLAndReturnError:nil];
    if (url == nil) {
        return NO;
    }

    BOOL accessing = [url startAccessingSecurityScopedResource];
    BOOL available = [self directoryExistsAtURL:url];
    if (accessing) {
        [url stopAccessingSecurityScopedResource];
    }
    return available;
}

- (BOOL)setFileSharingDirectoryURL:(NSURL *)url error:(NSError **)error {
    BOOL accessing = [url startAccessingSecurityScopedResource];
    BOOL validDirectory = url.fileURL && [self directoryExistsAtURL:url];
    if (!validDirectory) {
        if (accessing) {
            [url stopAccessingSecurityScopedResource];
        }
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
        }
        return NO;
    }

    NSString *displayName = [self displayNameForFileSharingDirectoryURL:url];
    NSData *bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:error];
    if (accessing) {
        [url stopAccessingSecurityScopedResource];
    }
    if (bookmark == nil) {
        return NO;
    }

    [[NSUserDefaults standardUserDefaults] setObject:bookmark forKey:B2FileSharingDirectoryBookmarkDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setObject:displayName forKey:B2FileSharingDirectoryDisplayNameDefaultsKey];
    [self initEmulator];
    return YES;
}

- (void)resetFileSharingDirectory {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:B2FileSharingDirectoryBookmarkDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:B2FileSharingDirectoryDisplayNameDefaultsKey];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.defaultFileSharingPath withIntermediateDirectories:YES attributes:nil error:nil];
    B2InstallDefaultFileSharingIconAtPath(self.defaultFileSharingPath);
    [self initEmulator];
}

- (NSURL *)resolvedConfiguredFileSharingDirectoryURLAndReturnError:(NSError **)error {
    NSData *bookmark = [[NSUserDefaults standardUserDefaults] objectForKey:B2FileSharingDirectoryBookmarkDefaultsKey];
    if (![bookmark isKindOfClass:[NSData class]]) {
        return nil;
    }

    BOOL stale = NO;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:error];
    if (url == nil || stale) {
        return nil;
    }
    return url;
}

- (BOOL)directoryExistsAtURL:(NSURL *)url {
    NSNumber *isDirectory = nil;
    if ([url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil]) {
        return isDirectory.boolValue;
    }

    BOOL directory = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&directory] && directory;
}

- (NSString *)displayNameForFileSharingDirectoryURL:(NSURL *)url {
    NSString *displayName = nil;
    [url getResourceValue:&displayName forKey:NSURLLocalizedNameKey error:nil];
    if (displayName.length == 0) {
        [url getResourceValue:&displayName forKey:NSURLNameKey error:nil];
    }
    if (displayName.length == 0) {
        displayName = url.lastPathComponent;
    }
    return displayName ?: B2FileSharingDirectoryName;
}

- (void)stopAccessingFileSharingDirectory {
    if (activeFileSharingDirectoryIsSecurityScoped) {
        [activeFileSharingDirectoryURL stopAccessingSecurityScopedResource];
    }
    activeFileSharingDirectoryURL = nil;
    activeFileSharingDirectoryIsSecurityScoped = NO;
}

- (NSString *)userKeyboardLayoutsPath {
    static dispatch_once_t onceToken;
    static NSString *userKeyboardLayoutsPath;
    dispatch_once(&onceToken, ^{
        userKeyboardLayoutsPath = [self.documentsPath stringByAppendingPathComponent:@"Keyboard Layouts"];
    });
    return userKeyboardLayoutsPath;
}

- (NSArray *)availableDiskImages {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *diskImageExtensions = @[@"img", @"dsk", @"dc42", @"diskcopy42", @"iso", @"cdr", @"toast"];
    NSPredicate *diskImagePredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *filename, NSDictionary<NSString *,id> * _Nullable bindings) {
        return [diskImageExtensions containsObject:filename.pathExtension.lowercaseString];
    }];
    return [[fm contentsOfDirectoryAtPath:self.documentsPath error:nil] filteredArrayUsingPredicate:diskImagePredicate];
}

- (NSArray *)availableKeyboardLayouts {
    NSMutableArray<NSString*> *keyboardLayouts = [[NSBundle mainBundle] pathsForResourcesOfType:@"nfkeyboardlayout" inDirectory:@"Keyboard Layouts"].mutableCopy;
    NSArray<NSString*> *userKeyboardLayouts = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self userKeyboardLayoutsPath] error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension.lowercaseString = %@", @"nfkeyboardlayout"]];
    for (NSString *keyboardLayout in userKeyboardLayouts) {
        if (![keyboardLayouts containsObject:keyboardLayout]) {
            [keyboardLayouts addObject:keyboardLayout];
        }
    }
    return keyboardLayouts;
}

- (void)initEmulator {
    NSString *documentsPath = [self documentsPath];
    NSString *fileSharingPath = [self prepareFileSharingDirectoryForEmulator];
    chdir(documentsPath.fileSystemRepresentation);
    
    // init things
    int argc = 0;
    char **argv = NULL;
    PrefsInit(fileSharingPath.fileSystemRepresentation, argc, argv);
    SysInit();
}

- (void)startEmulator {
    if (emulThread != nil || snapshotPreparationInProgress) {
        return;
    }

    [self prepareForEmulatorStartWithCompletion:^{
        [self prepareSnapshotsAndStartEmulator];
    }];
}

- (void)terminateEmulator {
    if (!_emulatorRunning || emulMachThread == THREAD_NULL) {
        return;
    }

    kern_return_t error = thread_suspend(emulMachThread);
    if (error != KERN_SUCCESS) {
        NSLog(@"%s - thread_suspend() failed, returned %d", __PRETTY_FUNCTION__, error);
    }

    _emulatorRunning = NO;
    [self updateSettingsModalInPresentation];

    error = thread_terminate(emulMachThread);
    if (error != KERN_SUCCESS) {
        NSLog(@"%s - thread_terminate() failed, returned %d", __PRETTY_FUNCTION__, error);
    }

    [self pramBackup:nil];
    QuitEmuNoExit();
    [self initEmulator];
    dispatch_async(dispatch_get_main_queue(), ^{
        [sharedScreenView updateImage:nil];
    });

    emulThread = nil;
    emulMachThread = THREAD_NULL;
    [pramTimer invalidate];
    pramTimer = nil;
}

- (void)prepareSnapshotsAndStartEmulator {
    if (emulThread != nil || snapshotPreparationInProgress) {
        return;
    }

    snapshotPreparationInProgress = YES;
    __block BOOL snapshotCompletionHandled = NO;
    void (^finishSnapshotPreparation)(BOOL, NSError *) = ^(BOOL success, NSError * _Nullable error) {
        if (snapshotCompletionHandled) {
            return;
        }
        snapshotCompletionHandled = YES;
        self->snapshotPreparationInProgress = NO;
        if (success) {
            [self startEmulatorAfterSnapshotPreparation];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showAlertWithTitle:L(@"settings.volumes.snapshot.prepare.error.title") message:error.localizedDescription];
            });
        }
    };

    [B2DiskImageSnapshots ensureSnapshotsForConfiguredVolumesInDocumentsPath:self.documentsPath completion:^(BOOL success, NSError * _Nullable error) {
        finishSnapshotPreparation(success, error);
    }];
}

- (void)prepareForEmulatorStartWithCompletion:(void (^)(void))completion {
    B2ViewController *viewController = [B2ViewController sharedViewController];
    if (viewController == nil) {
        completion();
        return;
    }

    [viewController prepareForEmulatorStartWithCompletion:^(BOOL ready) {
        if (ready) {
            completion();
        }
    }];
}

- (void)prepareForEmulatorRestartSynchronously {
    if ([NSThread isMainThread]) {
        return;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self prepareForEmulatorStartWithCompletion:^{
            dispatch_semaphore_signal(semaphore);
        }];
    });
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)startEmulatorAfterSnapshotPreparation {
    // create threads and timer
    if (emulThread == nil) {
        [self initExtFS:self.fileSharingPath];
        emulThread = [[NSThread alloc] initWithTarget:self selector:@selector(emulThread) object:nil];
        if (tickThread == nil || [tickThread isFinished]) {
            tickThread = [[NSThread alloc] initWithTarget:self selector:@selector(tickThread) object:nil];
        }
        pramTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(pramBackup:) userInfo:nil repeats:YES];
        NSThread *threadToStart = emulThread;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (self->emulThread == threadToStart && ![threadToStart isCancelled]) {
                [threadToStart start];
            }
        });
    }
}

- (void)deinitEmulator {
    [self stopAccessingFileSharingDirectory];
    SysExit();
    PrefsExit();
}

- (void)emulThread {
    @autoreleasepool {
        emulMachThread = mach_thread_self();
        BOOL tickThreadStarted = NO;

        for (;;) {
            if (!InitEmulator()) {
                NSLog(@"Could not init emulator");
                emulThread = nil;
                tickThread = nil;
                [pramTimer invalidate];
                pramTimer = nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.window.rootViewController.presentedViewController == nil) {
                        [self.window.rootViewController performSelector:@selector(showSettings:) withObject:self afterDelay:0.0];
                    }
                });
                return;
            }

            [self pramBackup:nil];
            _emulatorRunning = YES;
            [self updateSettingsModalInPresentation];
            if (!tickThreadStarted) {
                tickThreadStarted = YES;
                if (![tickThread isExecuting]) {
                    [tickThread start];
                }
            }

            quit_program = false;
            Start680x0();
            _emulatorRunning = NO;
            [self updateSettingsModalInPresentation];

            if (B2ConsumeColdRestartOnMacReset()) {
                [self pramBackup:nil];
                QuitEmuNoExit();
                [self prepareForEmulatorRestartSynchronously];
                [self initEmulator];
                continue;
            }

            NSLog(@"Emulator exited normally");
            break;
        }
    }
}

- (void)tickThread {
    mach_timebase_info_data_t timebase_info;
    mach_timebase_info(&timebase_info);
    
    const uint64_t NANOS_PER_MSEC = 1000000ULL;
    double clock2abs = ((double)timebase_info.denom / (double)timebase_info.numer) * NANOS_PER_MSEC;
    
    thread_time_constraint_policy_data_t policy;
    policy.period      = 0;
    policy.computation = (uint32_t)(5 * clock2abs); // 5 ms of work
    policy.constraint  = (uint32_t)(10 * clock2abs);
    policy.preemptible = FALSE;
    
    int kr = thread_policy_set(pthread_mach_thread_np(pthread_self()),
                               THREAD_TIME_CONSTRAINT_POLICY,
                               (thread_policy_t)&policy,
                               THREAD_TIME_CONSTRAINT_POLICY_COUNT);
    if (kr != KERN_SUCCESS) {
        mach_error("thread_policy_set:", kr);
        exit(1);
    }
    
    uint64_t tick_time = 16666667ULL * timebase_info.denom / timebase_info.numer;
    int ticks = 0;
    for (;;) {
        if (!self.emulatorRunning) {
            mach_wait_until(mach_absolute_time() + tick_time);
            continue;
        }

        if (ROMVersion != ROM_VERSION_CLASSIC || HasMacStarted() ) {
            SetInterruptFlag(INTFLAG_60HZ);
            TriggerInterrupt();
        }
        
        if (ticks++ == 60) {
            ticks = 0;
            WriteMacInt32(0x20c, TimerDateTime());
            
            SetInterruptFlag(INTFLAG_1HZ);
            TriggerInterrupt();
        }
        
        mach_wait_until(mach_absolute_time() + tick_time);
    }
}

- (void)pramBackup:(NSTimer*)timer {
    B2SyncDisplayXPRAMToConfiguredVideoDepth();
    if (lastPRAM == nil || (lastPRAM.length == XPRAM_SIZE && memcmp(XPRAM, lastPRAM.bytes, XPRAM_SIZE) != 0)) {
        lastPRAM = [NSData dataWithBytes:XPRAM length:XPRAM_SIZE];
        SaveXPRAM();
    }
}

@end
