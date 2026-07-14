//
//  B2FileChooser.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 14/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2FileChooser.h"
#import "B2AppDelegate.h"
#import "B2FileChooserTableViewCell.h"

@interface B2FileChooser ()

@end

@implementation B2FileChooser
{
    NSArray *directoryContents;
}

+ (void)initialize {
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    menuController.menuItems = @[[[UIMenuItem alloc] initWithTitle:L(@"file.action.rename") action:@selector(rename:)],
                                 [[UIMenuItem alloc] initWithTitle:L(@"file.action.share") action:@selector(share:)]];
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    if ((self = [super initWithStyle:style])) {
        self.sortOptions = NSCaseInsensitiveSearch | NSNumericSearch | NSForcedOrderingSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch;
        self.showDirectories = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.refreshControl = [[UIRefreshControl alloc] initWithFrame:CGRectZero];
    [self.refreshControl addTarget:self action:@selector(refresh:) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadDirectoryContents];
    [self.tableView reloadData];
}

- (void)loadDirectoryContents {
    self.title = self.path.lastPathComponent;
    directoryContents = [self filteredContentsOfDirectory:self.path];
}

- (NSArray*)filteredContentsOfDirectory:(NSString*)path {
    NSPredicate *showFilePredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *_Nonnull fileName, NSDictionary<NSString *,id> * _Nullable bindings) {
        NSString *filePath = [path stringByAppendingPathComponent:fileName];
        if (self.showHiddenFiles == NO && [self fileIsInvisible:filePath]) {
            return NO;
        }
        if (self.showDirectories == NO) {
            BOOL isDirectory;
            [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
            if (isDirectory == YES) {
                return NO;
            }
        }
        if ([self.delegate respondsToSelector:@selector(fileChooser:shouldShowFile:)]) {
            return [self.delegate fileChooser:self shouldShowFile:filePath];
        } else {
            return YES;
        }
    }];
    return [[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil] filteredArrayUsingPredicate:showFilePredicate] sortedArrayUsingComparator:^NSComparisonResult(NSString *s1, NSString *s2) {
        return [s1 compare:s2 options:self.sortOptions];
    }];
}

- (void)refresh:(id)sender {
    if ([self.delegate respondsToSelector:@selector(fileChooserWillRefresh:)]) {
        [self.delegate fileChooserWillRefresh:self];
    }
    [self loadDirectoryContents];
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
    if ([self.delegate respondsToSelector:@selector(fileChooserDidRefresh:)]) {
        [self.delegate fileChooserDidRefresh:self];
    }
}

- (void)selectItem:(NSString *)path {
    if ([self.path isEqualToString:path.stringByDeletingLastPathComponent]) {
        NSUInteger index = [directoryContents indexOfObject:path.lastPathComponent];
        if (index != NSNotFound) {
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:YES scrollPosition:UITableViewScrollPositionMiddle];
        }
    }
}

- (NSString*)filePathAtIndex:(NSUInteger)index {
    NSString *fileName = directoryContents[index];
    return [self.path stringByAppendingPathComponent:fileName];
}

- (BOOL)fileIsInvisible:(NSString*)filePath {
    if ([filePath.lastPathComponent hasPrefix:@"."]) {
        return YES;
    }
    NSDictionary *values = [[NSURL fileURLWithPath:filePath] resourceValuesForKeys:@[NSURLIsHiddenKey] error:NULL];
    if ([values[NSURLIsHiddenKey] boolValue]) {
        return YES;
    }
    return NO;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return directoryContents.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellIdentifier = @"cell";
    B2FileChooserTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[B2FileChooserTableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
        cell.fileChooser = self;
    }
    
    cell.filePath = [self filePathAtIndex:indexPath.row];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.delegate respondsToSelector:@selector(fileChooser:canDeletePath:)]) {
        return [self.delegate fileChooser:self canDeletePath:[self filePathAtIndex:indexPath.row]];
    } else {
        return NO;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *filePath = [self filePathAtIndex:indexPath.row];
        [self askDeleteFile:filePath];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *filePath = [self filePathAtIndex:indexPath.row];
    BOOL isDirectory;
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory]) {
        if (isDirectory && [self.delegate respondsToSelector:@selector(fileChooser:didChooseDirectory:)]) {
            [self.delegate fileChooser:self didChooseDirectory:filePath];
        } else if (!isDirectory && [self.delegate respondsToSelector:@selector(fileChooser:didChooseFile:)]) {
            [self.delegate fileChooser:self didChooseFile:filePath];
        }
    }
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray<UITableViewRowAction *> *actions = [NSMutableArray arrayWithCapacity:2];
    NSString *filePath = [self filePathAtIndex:indexPath.row];
    if ([self.delegate respondsToSelector:@selector(fileChooser:canDeletePath:)] && [self.delegate fileChooser:self canDeletePath:filePath]) {
        UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:L(@"file.action.delete") handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            [self tableView:tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:indexPath];
        }];
        [actions addObject:deleteAction];
    }
    if ([self.delegate respondsToSelector:@selector(fileChooser:canMovePath:)] && [self.delegate fileChooser:self canMovePath:filePath]) {
        UITableViewRowAction *moveAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:L(@"file.action.move") handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            // TODO: show paste button in nav bar or toolbar
        }];
        [actions addObject:moveAction];
    }
    return actions;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return (action == @selector(share:) || action == @selector(rename:) || action == @selector(delete:));
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    // menu will not be shown if this item doesn't exist
}

#pragma mark - File Actions

- (void)askDeleteFile:(NSString*)filePath {
    NSString *fileName = filePath.lastPathComponent;
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"dir.delete.confirmation.title") message:LX(@"dir.delete.confirmation.message", fileName) preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"dir.delete.confirmation.delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSError *error = nil;
        if ([[NSFileManager defaultManager] removeItemAtPath:filePath error:&error]) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[directoryContents indexOfObject:fileName] inSection:0];
            [self loadDirectoryContents];
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        } else {
            [[B2AppDelegate sharedInstance] showAlertWithTitle:LX(@"dir.delete.error", fileName) message:error.localizedDescription];
        }
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)askRenameFile:(NSString*)filePath {
    NSString *fileName = filePath.lastPathComponent;
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:fileName message:L(@"dir.rename.message") preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = fileName;
        textField.text = fileName;
    }];
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"dir.rename.rename") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSError *error = nil;
        NSString *newName = alertController.textFields.firstObject.text;
        NSString *newPath = [filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:newName];
        if ([[NSFileManager defaultManager] moveItemAtPath:filePath toPath:newPath error:&error]) {
            NSIndexPath *oldIndexPath = [NSIndexPath indexPathForRow:[directoryContents indexOfObject:fileName] inSection:0];
            [self loadDirectoryContents];
            NSUInteger newIndex = [directoryContents indexOfObject:newName];
            if (newIndex == NSNotFound) {
                [self.tableView deleteRowsAtIndexPaths:@[oldIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            } else {
                NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:newIndex inSection:0];
                [self.tableView moveRowAtIndexPath:oldIndexPath toIndexPath:newIndexPath];
                [self.tableView reloadRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationNone];
            }
        } else {
            [[B2AppDelegate sharedInstance] showAlertWithTitle:LX(@"dir.rename.error", fileName) message:error.localizedDescription];
        }
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)shareFile:(NSString*)filePath {
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:filePath]] applicationActivities:nil];
    [self presentViewController:avc animated:YES completion:nil];
}

@end
