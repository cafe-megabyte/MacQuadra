//
//  B2VolumesSettingsViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 06/07/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import "B2VolumesSettingsViewController.h"
#import "B2VolumeInfoViewController.h"
#import "NSUserDefaults+B2Accessors.h"
#import "B2AppDelegate.h"

NSString* NSStringFromB2VolumeType(B2VolumeType volumeType) {
    switch (volumeType) {
        case B2VolumeTypeHardDisk:
            return @"disk";
        case B2VolumeTypeFloppy:
            return @"floppy";
        case B2VolumeTypeCDROM:
            return @"cdrom";
        case B2VolumeTypeUnused:
            return @"unused";
    }
}

@interface B2SizeTextFieldDelegate : NSObject <UITextFieldDelegate>

@end

@implementation B2VolumesSettingsViewController
{
    NSMutableArray *diskVolumes, *floppyVolumes, *cdromVolumes, *availableVolumes;
    UIAlertController *createDiskImageController;
    __block B2SizeTextFieldDelegate *sizeTextFieldDelegate;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSections:nil animated:NO];
}

- (void)reloadSections:(NSIndexSet*)sections animated:(BOOL)animated {
    BOOL hasAllSections = (sections == nil || sections.count == 4);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (hasAllSections || [sections containsIndex:B2VolumeTypeHardDisk]) {
        diskVolumes = [defaults b2MutableArrayForKey:@"disk"];
    }
    if (hasAllSections || [sections containsIndex:B2VolumeTypeFloppy]) {
        floppyVolumes = [defaults b2MutableArrayForKey:@"floppy"];
    }
    if (hasAllSections || [sections containsIndex:B2VolumeTypeCDROM]) {
        cdromVolumes = [defaults b2MutableArrayForKey:@"cdrom"];
    }
    if (hasAllSections || [sections containsIndex:B2VolumeTypeUnused]) {
        availableVolumes = [self availableDiskImages];
    }
    
    if (hasAllSections && !animated) {
        [self.tableView reloadData];
    } else {
        UITableViewRowAnimation animation = animated ? UITableViewRowAnimationAutomatic : UITableViewRowAnimationNone;
        [self.tableView reloadSections:sections withRowAnimation:animation];
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    NSIndexPath *createDiskIndexPath = [NSIndexPath indexPathForRow:diskVolumes.count inSection:0];
    UITableViewRowAnimation animation = animated ? UITableViewRowAnimationAutomatic : UITableViewRowAnimationNone;
    [self.tableView beginUpdates];
    if (editing) {
        availableVolumes = [self availableDiskImages];
        [self.tableView insertRowsAtIndexPaths:@[createDiskIndexPath] withRowAnimation:animation];
        [self.tableView insertSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:animation];
    } else {
        [self.tableView deleteRowsAtIndexPaths:@[createDiskIndexPath] withRowAnimation:animation];
        [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:animation];
    }
    [self.tableView endUpdates];
}

- (NSString*)titleForVolume:(NSString*)path withType:(B2VolumeType)type {
    if (type != B2VolumeTypeCDROM && [path hasPrefix:@"*"]) {
        path = [path substringFromIndex:1];
    }
    return path;
}

- (NSString*)detailForVolume:(NSString*)path withType:(B2VolumeType)type {
    BOOL locked = NO;
    if (type != B2VolumeTypeCDROM && [path hasPrefix:@"*"]) {
        locked = YES;
        path = [path substringFromIndex:1];
    }
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (attributes && [attributes[NSFileSize] isKindOfClass:[NSNumber class]]) {
        NSString *sizeString = [NSByteCountFormatter stringFromByteCount:[attributes[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        if (locked) {
            sizeString = [sizeString stringByAppendingString:@" 🔒"];
        }
        return sizeString;
    } else {
        return L(@"settings.volumes.error");
    }
}

- (NSMutableArray*)volumesOfType:(B2VolumeType)type {
    switch (type) {
        case B2VolumeTypeHardDisk:
            return diskVolumes;
        case B2VolumeTypeFloppy:
            return floppyVolumes;
        case B2VolumeTypeCDROM:
            return cdromVolumes;
        case B2VolumeTypeUnused:
            return availableVolumes;
    }
}

- (void)createDiskImage {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"settings.volumes.new.title") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = L(@"settings.volumes.new.name");
        [textField addTarget:self action:@selector(validateCreateDiskImageInput:) forControlEvents:UIControlEventAllEditingEvents];
    }];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = L(@"settings.volumes.new.size");
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        UILabel *unitLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60.0, 32.0)];
        textField.rightViewMode = UITextFieldViewModeAlways;
        textField.rightView = unitLabel;
        unitLabel.textAlignment = NSTextAlignmentRight;
        UISegmentedControl *unitsControl = [[UISegmentedControl alloc] initWithFrame:CGRectMake(0, 0, 80.0, 16.0)];
        NSArray *units = @[L(@"settings.volumes.new.size.k"), L(@"settings.volumes.new.size.m")];
        [units enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL * _Nonnull stop) {
            [unitsControl insertSegmentWithTitle:title atIndex:idx animated:NO];
        }];
        unitsControl.selectedSegmentIndex = 0;
        textField.rightView = unitsControl;
        sizeTextFieldDelegate = [B2SizeTextFieldDelegate new];
        textField.delegate = sizeTextFieldDelegate;
        [textField addTarget:self action:@selector(validateCreateDiskImageInput:) forControlEvents:UIControlEventAllEditingEvents];
        [unitsControl addTarget:self action:@selector(validateCreateDiskImageInput:) forControlEvents:UIControlEventValueChanged];
        unitLabel.text = [unitsControl titleForSegmentAtIndex:unitsControl.selectedSegmentIndex];
    }];
    
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *createAction = [UIAlertAction actionWithTitle:L(@"settings.volumes.new.size.create") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *name = [self _newDiskImageName];
        off_t size = [self _newDiskImageSize];
        createDiskImageController = nil;
        [self createDiskImageWithName:name size:size];
    }];
    [alertController addAction:createAction];
    createAction.enabled = NO;
    [self presentViewController:alertController animated:YES completion:nil];
    createDiskImageController = alertController;
}

- (BOOL)validateCreateDiskImageInput:(id)sender {
    BOOL valid = NO;
    if (self.presentedViewController == createDiskImageController) {
        NSString *name = [self _newDiskImageName];
        BOOL nameIsValid = (name.length > 0) && ![name hasPrefix:@"."] && ![name containsString:@"/"] && ![name containsString:@"*"];
        
        off_t size = [self _newDiskImageSize];
        BOOL sizeIsValid = (size >= 400 * 1024) && (size <= 2LL * 1024 * 1024 * 1024);
        
        valid = nameIsValid && sizeIsValid;
        UIAlertAction *createAction = createDiskImageController.actions[1];
        createAction.enabled = valid;
    }
    return valid;
}

- (NSString*)_newDiskImageName {
    return createDiskImageController ? createDiskImageController.textFields[0].text : nil;
}

- (off_t)_newDiskImageSize {
    if (createDiskImageController == nil) {
        return 0;
    }
    UISegmentedControl *unitsControl = (UISegmentedControl*)createDiskImageController.textFields[1].rightView;
    off_t unitsMultiplier = (unitsControl.selectedSegmentIndex == 0) ? 1024 : 1024 * 1024;
    off_t size = createDiskImageController.textFields[1].text.floatValue * unitsMultiplier;
    return size;
}

- (void)createDiskImageWithName:(NSString*)name size:(off_t)size {
    NSString *imageFileName = [name.pathExtension.lowercaseString isEqualToString:@"img"] ? name : [name stringByAppendingPathExtension:@"img"];
    NSString *imagePath = [[B2AppDelegate sharedInstance].documentsPath stringByAppendingPathComponent:imageFileName];
    
    int fd = open(imagePath.fileSystemRepresentation, O_CREAT | O_TRUNC | O_EXCL | O_WRONLY, 0666);
    if (fd == -1) {
        [[B2AppDelegate sharedInstance] showAlertWithTitle:L(@"settings.volumes.new.error.title") message:[[NSString alloc] initWithUTF8String:strerror(errno)]];
        return;
    }
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"settings.volumes.progress.title") message:@"\n\n\n" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alertController animated:true completion:^{
        UIView *alertView = alertController.view;
        UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        activityView.color = [UIColor blackColor];
        activityView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        activityView.center = CGPointMake(alertView.bounds.size.width / 2.0, alertView.bounds.size.height / 2.0 + 32.0);
        [alertView addSubview:activityView];
        [activityView startAnimating];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            int error = 0;
            if (ftruncate(fd, size)) {
                error = errno;
            }
            close(fd);
            dispatch_async(dispatch_get_main_queue(), ^{
                [activityView stopAnimating];
                [self dismissViewControllerAnimated:YES completion:^{
                    if (error) {
                        [[B2AppDelegate sharedInstance] showAlertWithTitle:L(@"settings.volumes.new.error.title") message:[[NSString alloc] initWithUTF8String:strerror(error)]];
                    }
                }];
                [diskVolumes addObject:imageFileName];
                [[NSUserDefaults standardUserDefaults] setObject:diskVolumes forKey:@"disk"];
                [self reloadSections:[NSIndexSet indexSetWithIndex:B2VolumeTypeHardDisk] animated:YES];
            });
        });
    }];
}

- (void)askDeleteDiskImage:(NSString*)imageName {
    NSString *imageFileName = [imageName hasPrefix:@"*"] ? [imageName substringFromIndex:1] : imageName;
    NSString *imagePath = [[B2AppDelegate sharedInstance].documentsPath stringByAppendingPathComponent:imageFileName];
    BOOL imageExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
    if (imageExists) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"settings.volumes.delete.confirmation.title") message:LX(@"settings.volumes.delete.confirmation.message", imageFileName) preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:L(@"settings.volumes.delete.confirmation.delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self deleteDiskImage:imageName];
        }]];
        [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
    } else {
        [self deleteDiskImage:imageName];
    }
}

- (void)deleteDiskImage:(NSString*)imageName {
    NSString *imageFileName = [imageName hasPrefix:@"*"] ? [imageName substringFromIndex:1] : imageName;
    NSString *imagePath = [[B2AppDelegate sharedInstance].documentsPath stringByAppendingPathComponent:imageFileName];
    NSError *error = nil;
    BOOL imageExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
    if (imageExists == NO || [[NSFileManager defaultManager] removeItemAtPath:imagePath error:&error]) {
        [diskVolumes removeObject:imageName];
        [floppyVolumes removeObject:imageName];
        [cdromVolumes removeObject:imageName];
        [self updateDefaults];
        [self reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tableView.numberOfSections)] animated:YES];
    } else {
        [[B2AppDelegate sharedInstance] showAlertWithTitle:error.localizedDescription message:error.localizedFailureReason];
    }
}

- (NSMutableArray*)availableDiskImages {
    NSMutableArray *availableDiskImages = [B2AppDelegate sharedInstance].availableDiskImages.mutableCopy;
    NSMutableArray *usedDiskImages = diskVolumes.mutableCopy;
    [usedDiskImages addObjectsFromArray:floppyVolumes];
    [usedDiskImages addObjectsFromArray:cdromVolumes];
    for (NSUInteger i = 0; i < usedDiskImages.count; i++) {
        if ([usedDiskImages[i] hasPrefix:@"*"]) {
            usedDiskImages[i] = [usedDiskImages[i] substringFromIndex:1];
        }
    }
    [availableDiskImages removeObjectsInArray:usedDiskImages];
    return availableDiskImages;
}

- (UIImage*)imageForVolumeType:(B2VolumeType)volumeType {
    switch (volumeType) {
        case B2VolumeTypeHardDisk:
            return [UIImage imageNamed:@"DiskHD"];
        case B2VolumeTypeFloppy:
            return [UIImage imageNamed:@"DiskFloppy"];
        case B2VolumeTypeCDROM:
            return [UIImage imageNamed:@"DiskCD"];
        case B2VolumeTypeUnused:
            return nil;
    }
}

- (void)updateDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:diskVolumes forKey:@"disk"];
    [defaults setObject:floppyVolumes forKey:@"floppy"];
    [defaults setObject:cdromVolumes forKey:@"cdrom"];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return tableView.editing ? 4 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    B2VolumeType volumeType = (B2VolumeType)section;
    NSInteger baseCount = [self volumesOfType:volumeType].count;
    if (tableView.editing && section == B2VolumeTypeHardDisk) {
        baseCount += 1;
    }
    return baseCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    B2VolumeType volumeType = (B2VolumeType)indexPath.section;
    NSMutableArray *source = [self volumesOfType:volumeType];
    UITableViewCell *cell = nil;
    
    if (indexPath.row < source.count) {
        // disk image
        cell = [tableView dequeueReusableCellWithIdentifier:@"disk" forIndexPath:indexPath];
        cell.textLabel.text = [self titleForVolume:source[indexPath.row] withType:volumeType];
        cell.detailTextLabel.text = [self detailForVolume:source[indexPath.row] withType:volumeType];
        cell.imageView.image = [self imageForVolumeType:volumeType];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"default" forIndexPath:indexPath];
        cell.textLabel.text = L(@"settings.volumes.create");
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == B2VolumeTypeUnused) {
        return L(@"settings.volumes.available");
    } else {
        return L(@"settings.volumes.type.%@", NSStringFromB2VolumeType(section));
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.editing == NO) {
        return UITableViewCellEditingStyleNone;
    } else if (indexPath.row < [self volumesOfType:indexPath.section].count) {
        return UITableViewCellEditingStyleDelete;
    } else if (indexPath.section == B2VolumeTypeHardDisk && indexPath.row == diskVolumes.count) {
        return UITableViewCellEditingStyleInsert;
    } else {
        return UITableViewCellEditingStyleNone;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    B2VolumeType volumeType = (B2VolumeType)indexPath.section;
    NSMutableArray *source = [self volumesOfType:volumeType];
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *imageFileName = source[indexPath.row];
        [self askDeleteDiskImage:imageFileName];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        [self createDiskImage];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row < [self volumesOfType:indexPath.section].count;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section == B2VolumeTypeHardDisk && proposedDestinationIndexPath.row >= diskVolumes.count) {
        NSUInteger destinationRow = sourceIndexPath.section == B2VolumeTypeHardDisk ? diskVolumes.count - 1 : diskVolumes.count;
        return [NSIndexPath indexPathForRow:destinationRow inSection:B2VolumeTypeHardDisk];
    } else {
        return proposedDestinationIndexPath;
    }
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
    NSMutableArray *source = [self volumesOfType:fromIndexPath.section];
    NSMutableArray *destination = [self volumesOfType:toIndexPath.section];
    NSString *item = source[fromIndexPath.row];
    [source removeObjectAtIndex:fromIndexPath.row];
    [destination insertObject:item atIndex:toIndexPath.row];
    dispatch_async(dispatch_get_main_queue(), ^{
        [tableView reloadRowsAtIndexPaths:@[toIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    });
    [self updateDefaults];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[B2VolumeInfoViewController class]] && [sender isKindOfClass:[UITableViewCell class]]) {
        NSIndexPath *indexPath = [self.tableView indexPathForCell:sender];
        B2VolumeInfoViewController *destination = segue.destinationViewController;
        destination.volumePath = [[self volumesOfType:indexPath.section] objectAtIndex:indexPath.row];
        destination.volumeType = indexPath.section;
        destination.volumeIndex = indexPath.row;
    }
}

@end

@implementation B2SizeTextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    UISegmentedControl *unitsControl = (UISegmentedControl*)textField.rightView;
    NSArray *unitShortcuts = @[@"k", @"m"];
    if (string.length == 0) {
        return YES;
    } else if (string.length == 1 && [unitShortcuts indexOfObject:string.lowercaseString] != NSNotFound) {
        unitsControl.selectedSegmentIndex = [unitShortcuts indexOfObject:string.lowercaseString];
        [unitsControl sendActionsForControlEvents:UIControlEventValueChanged];
        return NO;
    } else {
        NSString *newString = [textField.text stringByReplacingCharactersInRange:range withString:string];
        NSScanner *scanner = [NSScanner scannerWithString:newString];
        double value;
        return [scanner scanDouble:&value] && scanner.isAtEnd && value >= 0;
    }
}

@end
