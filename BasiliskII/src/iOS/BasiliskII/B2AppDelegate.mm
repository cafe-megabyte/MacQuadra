//
//  B2AppDelegate.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 08/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import "B2AppDelegate.h"
#import "B2ViewController.h"
#import "B2ScreenView.h"
#import "B2DocumentsSettingsController.h"
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

static NSMutableSet *hiddenExtFSFiles = nil;

bool ShouldHideExtFSFile(const char *path) {
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

@implementation B2AppDelegate
{
    NSTimer *redrawTimer, *pramTimer;
    NSThread *emulThread, *tickThread;
    NSTimeInterval redrawDelay;
    NSData *lastPRAM;
    NSMutableArray *videoModes;
}

+ (instancetype)sharedInstance {
    if (sharedDelegate == nil) {
        return (B2AppDelegate*)[UIApplication sharedApplication].delegate;
    }
    return sharedDelegate;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    sharedDelegate = self;
    [application setStatusBarHidden:YES];
    [self initEmulator];
    
    // populate documents directory so it shows up in Files
    [[NSFileManager defaultManager] createDirectoryAtPath:self.userKeyboardLayoutsPath withIntermediateDirectories:YES attributes:nil error:nil];

    return YES;
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
    
    // Show settings if emulator is not running
    if (self.emulatorRunning == NO && self.window.rootViewController.presentedViewController == nil) {
        [self.window.rootViewController performSelector:@selector(showSettings:) withObject:self afterDelay:0.0];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithCapacity:2];
    if (sourceApplication) {
        options[UIApplicationOpenURLOptionsSourceApplicationKey] = sourceApplication;
    }
    if (annotation) {
        options[UIApplicationOpenURLOptionsAnnotationKey] = annotation;
    }
    return [self application:application openURL:url options:options];
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
    if ([shortcutItem.type isEqualToString:@"settings"] && self.window.rootViewController.presentedViewController == nil) {
        [self.window.rootViewController performSelector:@selector(showSettings:) withObject:self afterDelay:0.0];
        success = YES;
    }
    completionHandler(success);
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
    // hide some files from extfs
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    hiddenExtFSFiles = [NSMutableSet setWithCapacity:8];
    [self addHiddenFiles:[defaults objectForKey:@"rom"] relativeToPath:baseDir];
    [self addHiddenFiles:[defaults objectForKey:@"disk"] relativeToPath:baseDir];
    [self addHiddenFiles:[defaults objectForKey:@"floppy"] relativeToPath:baseDir];
    [self addHiddenFiles:[defaults objectForKey:@"cdrom"] relativeToPath:baseDir];
    [self addHiddenFiles:[self.documentsPath stringByAppendingPathComponent:@"Inbox"] relativeToPath:baseDir];
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
    chdir(documentsPath.fileSystemRepresentation);
    
    // init things
    int argc = 0;
    char **argv = NULL;
    PrefsInit(documentsPath.fileSystemRepresentation, argc, argv);
    SysInit();
}

- (void)startEmulator {
    // create threads and timer
    if (emulThread == nil) {
        [self initExtFS:self.documentsPath];
        emulThread = [[NSThread alloc] initWithTarget:self selector:@selector(emulThread) object:nil];
        tickThread = [[NSThread alloc] initWithTarget:self selector:@selector(tickThread) object:nil];
        pramTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(pramBackup:) userInfo:nil repeats:YES];
        [emulThread performSelector:@selector(start) withObject:nil afterDelay:1.0];
    }
}

- (void)deinitEmulator {
    SysExit();
    PrefsExit();
}

- (void)emulThread {
    @autoreleasepool {
        if (!InitEmulator()) {
            NSLog(@"Could not init emulator");
            return;
        }
        
        [self pramBackup:nil];
        _emulatorRunning = YES;
        [tickThread start];
        
        Start680x0();
        _emulatorRunning = NO;
        NSLog(@"Emulator exited normally");
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
    if (lastPRAM == nil || (lastPRAM.length == XPRAM_SIZE && memcmp(XPRAM, lastPRAM.bytes, XPRAM_SIZE) != 0)) {
        lastPRAM = [NSData dataWithBytes:XPRAM length:XPRAM_SIZE];
        SaveXPRAM();
    }
}

@end
