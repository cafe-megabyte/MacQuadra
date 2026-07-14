//
//  B2DocumentsSettingsController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 28/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2DocumentsSettingsController.h"
#import "B2AppDelegate.h"
#import "B2FileChooser.h"
#import "B2DesktopDatabase.h"

NSString *B2DidImportFileNotificationName = @"B2DidImportFileNotification";

@interface B2DocumentsSettingsController () <B2FileChooserDelegate>
@property (nonatomic, readonly) B2FileChooser *topFileChooser;
@end

@implementation B2DocumentsSettingsController
{
    B2FileChooser *baseFileChooser;
    NSString *baseFilePath;
    B2DesktopDatabase *desktop;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    baseFilePath = [B2AppDelegate sharedInstance].documentsPath;
    baseFileChooser = [[B2FileChooser alloc] initWithStyle:UITableViewStylePlain];
    baseFileChooser.path = baseFilePath;
    baseFileChooser.delegate = self;
    self.viewControllers = @[baseFileChooser];
    [self loadDesktopFile];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didImportFile:) name:B2DidImportFileNotificationName object:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}

- (void)didImportFile:(NSNotification*)notification {
    NSString *path = notification.userInfo[@"path"];
    B2FileChooser *topFileChooser = self.topFileChooser;
    if ([topFileChooser.path isEqualToString:path.stringByDeletingLastPathComponent]) {
        [topFileChooser refresh:self];
        [topFileChooser selectItem:path];
    }
}

- (B2FileChooser*)topFileChooser {
    __block B2FileChooser *topFileChooser = nil;
    [self.viewControllers enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(__kindof UIViewController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:[B2FileChooser class]]) {
            *stop = YES;
            topFileChooser = obj;
        }
    }];
    return topFileChooser;
}

#pragma mark - Desktop

- (void)loadDesktopFile {
    NSString *desktopPath = [baseFilePath stringByAppendingPathComponent:@"Desktop"];
    desktop = [[B2DesktopDatabase alloc] initWithDesktopFile:desktopPath];
    desktop.delegate = [B2AppDelegate sharedInstance];
    desktop.imageScale = 1.5;
}

#pragma mark - File Chooser Delegate

- (void)fileChooserWillRefresh:(B2FileChooser *)fileChooser {
    [self loadDesktopFile];
    [fileChooser.tableView reloadData];
}

- (void)fileChooser:(B2FileChooser *)fileChooser didChooseDirectory:(NSString *)path {
    B2FileChooser *newFileChooser = [[B2FileChooser alloc] initWithStyle:UITableViewStylePlain];
    newFileChooser.path = path;
    newFileChooser.delegate = self;
    [self pushViewController:newFileChooser animated:YES];
}

- (BOOL)fileChooser:(B2FileChooser *)fileChooser canDeletePath:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // isDeletableFileAtPath returns NO for items in inbox, but they are deletable
    return [fileManager isDeletableFileAtPath:path] || [path.stringByDeletingLastPathComponent hasSuffix:@"/Documents/Inbox"];
}

- (UIImage*)fileChooser:(B2FileChooser *)fileChooser iconForFile:(NSString *)path isDirectory:(BOOL)isDirectory {
    UIImage *icon = [desktop iconForFile:path];
    if (icon == nil) {
        icon = [UIImage imageNamed:isDirectory ? @"DefaultFolder" : @"DefaultDocument"];
    }
    return icon;
}

- (BOOL)fileChooser:(B2FileChooser *)fileChooser shouldShowFile:(NSString *)path {
    NSString *inboxPath = [baseFilePath stringByAppendingPathComponent:@"Inbox"];
    if ([path isEqualToString:inboxPath]) {
        return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:inboxPath error:NULL].count > 0;
    } else {
        return YES;
    }
}

@end
