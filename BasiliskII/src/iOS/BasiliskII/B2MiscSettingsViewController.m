//
//  B2MiscSettingsViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 11/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2MiscSettingsViewController.h"
#import "B2FileChooser.h"
#import "B2AppDelegate.h"

typedef enum : NSInteger {
    B2MiscSettingsSectionMacModel,
    B2MiscSettingsSectionCPU,
    B2MiscSettingsSectionMemory
} B2MiscSettingsSection;

@interface B2MiscSettingsViewController () <UITextFieldDelegate, B2FileChooserDelegate>

@end

@implementation B2MiscSettingsViewController
{
    UISwitch *fpuSwitch;
    __block UITextField *modelField;
    UIAlertAction *modelSaveAction;
    __block UITextField *ramSizeField;
    UIAlertAction *ramSizeSaveAction;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case B2MiscSettingsSectionMacModel:
            return 3;
        case B2MiscSettingsSectionCPU:
            return 4;
        case B2MiscSettingsSectionMemory:
            return 2;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case B2MiscSettingsSectionMacModel:
            return L(@"settings.misc.modelid");
        case B2MiscSettingsSectionCPU:
            return L(@"settings.misc.cpu");
        case B2MiscSettingsSectionMemory:
            return L(@"settings.misc.memory");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *cellIdentifier = @"basic";
    NSString *cellText = nil, *cellDetail = nil;
    UITableViewCellAccessoryType cellAccessory = UITableViewCellAccessoryNone;
    
    if (indexPath.section == B2MiscSettingsSectionMacModel) {
        cellIdentifier = @"detail";
        NSInteger currentValue = [defaults integerForKey:@"modelid"];
        if (indexPath.row < 2) {
            NSInteger cellValue = [self modelValueAtIndex:indexPath.row];
            cellAccessory = (currentValue == cellValue) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cellText = L(@"settings.misc.modelid.%d", (int)cellValue);
            cellDetail = [NSString stringWithFormat:@"%d", (int)cellValue];
        } else {
            // custom model
            cellText = L(@"settings.misc.modelid.custom");
            BOOL cellSelected = (currentValue != 5 && currentValue != 14);
            cellDetail = cellSelected ? [NSString stringWithFormat:@"%d", (int)currentValue] : nil;
            cellAccessory = cellSelected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else if (indexPath.section == B2MiscSettingsSectionCPU && indexPath.row < 3) {
        // CPU type
        NSInteger currentValue = [defaults integerForKey:@"cpu"];
        NSInteger cellValue = [self cpuValueAtIndex:indexPath.row];
        cellAccessory = (currentValue == cellValue) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cellText = L(@"settings.misc.cpu.%d", (int)cellValue);
    } else if (indexPath.section == B2MiscSettingsSectionCPU && indexPath.row == 3) {
        // FPU
        cellText = L(@"settings.misc.fpu");
        cellAccessory = ([defaults boolForKey:@"fpu"] || ([defaults integerForKey:@"cpu"] == 4)) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cellIdentifier = @"switch";
    } else if (indexPath.section == B2MiscSettingsSectionMemory) {
        cellIdentifier = @"detail";
        if (indexPath.row == 0) {
            cellText = L(@"settings.misc.ramsize");
            NSInteger value = [defaults integerForKey:@"ramsize"] / (1024 * 1024);
            cellDetail = LX(@"settings.misc.ramsize.value", (int)value);
        } else if (indexPath.row == 1) {
            cellText = L(@"settings.misc.rom");
            cellDetail = [defaults stringForKey:@"rom"];
            cellAccessory = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    cell.textLabel.text = cellText;
    cell.detailTextLabel.text = cellDetail;
    if ([cellIdentifier isEqualToString:@"switch"]) {
        if (cell.accessoryView == nil) {
            cell.accessoryView = [[UISwitch alloc] initWithFrame:CGRectZero];
        }
        UISwitch *cellSwitch = (UISwitch*)cell.accessoryView;
        cellSwitch.on = (cellAccessory != UITableViewCellAccessoryNone);
        fpuSwitch = cellSwitch;
        [cellSwitch addTarget:self action:@selector(toggleFPU:) forControlEvents:UIControlEventValueChanged];
    } else {
        cell.accessoryType = cellAccessory;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (indexPath.section == B2MiscSettingsSectionMacModel) {
        if (indexPath.row < 2) {
            // selected model
            [defaults setInteger:[self modelValueAtIndex:indexPath.row] forKey:@"modelid"];
        } else {
            // custom model (ask)
            [self askForCustomModel];
        }
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:B2MiscSettingsSectionMacModel] withRowAnimation:UITableViewRowAnimationAutomatic];
    } else if (indexPath.section == B2MiscSettingsSectionCPU && indexPath.row < 3) {
        NSInteger cpuValue = [self cpuValueAtIndex:indexPath.row];
        [defaults setInteger:[self cpuValueAtIndex:indexPath.row] forKey:@"cpu"];
        fpuSwitch.on = (cpuValue == 4) || [defaults boolForKey:@"fpu"];
        fpuSwitch.enabled = (cpuValue != 4);
        NSArray *cpuOptionsIndexPaths = @[[NSIndexPath indexPathForRow:0 inSection:B2MiscSettingsSectionCPU],
                                          [NSIndexPath indexPathForRow:1 inSection:B2MiscSettingsSectionCPU],
                                          [NSIndexPath indexPathForRow:2 inSection:B2MiscSettingsSectionCPU]];
        [tableView reloadRowsAtIndexPaths:cpuOptionsIndexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    } else if (indexPath.section == B2MiscSettingsSectionMemory) {
        if (indexPath.row == 0) {
            [self askForRAMSize];
        } else if (indexPath.row == 1) {
            B2FileChooser *fileChooser = [[B2FileChooser alloc] initWithStyle:UITableViewStylePlain];
            fileChooser.path = [B2AppDelegate sharedInstance].documentsPath;
            fileChooser.navigationItem.prompt = L(@"settings.misc.rom.prompt");
            fileChooser.delegate = self;
            fileChooser.showDirectories = NO;
            [self.navigationController pushViewController:fileChooser animated:YES];
        }
    }
}

- (NSInteger)modelValueAtIndex:(NSInteger)index {
    NSInteger values[] = {5,14};
    return values[index];
}

- (NSInteger)cpuValueAtIndex:(NSInteger)index {
    NSInteger values[] = {2,3,4};
    return values[index];
}

- (void)toggleFPU:(id)sender {
    if ([sender isKindOfClass:[UISwitch class]]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:fpuSwitch.on forKey:@"fpu"];
    }
}

#pragma mark - File Chooser Delegate

- (void)fileChooser:(B2FileChooser *)fileChooser didChooseFile:(NSString *)path {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *relativePath = path;
    NSString *documentsPath = [[B2AppDelegate sharedInstance].documentsPath stringByAppendingString:@"/"];
    if ([relativePath hasPrefix:documentsPath]) {
        relativePath = [relativePath substringFromIndex:documentsPath.length];
    }
    [defaults setObject:relativePath forKey:@"rom"];
    NSIndexPath *romRowIndexPath = [NSIndexPath indexPathForRow:1 inSection:B2MiscSettingsSectionMemory];
    [self.tableView reloadRowsAtIndexPaths:@[romRowIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self.navigationController popToViewController:self animated:YES];
    [self.navigationItem performSelector:@selector(setPrompt:) withObject:nil afterDelay:0.1];
    [self.tableView scrollToRowAtIndexPath:romRowIndexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
}

- (BOOL)fileChooser:(B2FileChooser *)fileChooser shouldShowFile:(nonnull NSString *)path {
    #define kRomVersionClassic 0x0276
    #define kRomVersion32 0x067c
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *romHeader = [fh readDataOfLength:10];
    [fh closeFile];
    uint16_t romVersion = romHeader.length >= 10 ? OSReadBigInt16(romHeader.bytes, 8) : 0;
    #if REAL_ADDRESSING || DIRECT_ADDRESSING
        return romVersion == kRomVersion32;
    #else
        return (romVersion == kRomVersionClassic) || (romVersion == kRomVersion32);
    #endif
}

#pragma mark - Custom Model Dialog

- (void)askForCustomModel {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"settings.misc.modelid.customize.title") message:L(@"settings.misc.modelid.customize.message") preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"modelid";
        textField.text = [NSString stringWithFormat:@"%d", (int)[defaults integerForKey:@"modelid"]];
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.delegate = self;
        [textField addTarget:self action:@selector(validateModelInput:) forControlEvents:UIControlEventAllEditingEvents];
        modelField = textField;
    }];
    
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:nil]];
    modelSaveAction = [UIAlertAction actionWithTitle:L(@"misc.ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSInteger value = modelField.text.integerValue;
        [defaults setInteger:value forKey:@"modelid"];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:B2MiscSettingsSectionMacModel] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    [alertController addAction:modelSaveAction];
    modelSaveAction.enabled = YES;
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)validateModelInput:(id)sender {
    NSInteger value = modelField.text.integerValue;
    modelSaveAction.enabled = modelField.text.length > 0 && value >= 0 && value <= 255;
}

#pragma mark - RAM Size Dialog

- (void)askForRAMSize {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"settings.misc.ramsize.customize.title") message:L(@"settings.misc.ramsize.customize.message") preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = L(@"settings.misc.ramsize.customize.placeholder");
        textField.text = [NSString stringWithFormat:@"%d", (int)[defaults integerForKey:@"ramsize"] / (1024 * 1024)];
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.delegate = self;
        [textField addTarget:self action:@selector(validateRAMSizeInput:) forControlEvents:UIControlEventAllEditingEvents];
        ramSizeField = textField;
    }];
    
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:nil]];
    ramSizeSaveAction = [UIAlertAction actionWithTitle:L(@"misc.ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSInteger value = ramSizeField.text.integerValue * 1024 * 1024;
        [defaults setInteger:value forKey:@"ramsize"];
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:B2MiscSettingsSectionMemory]] withRowAnimation:UITableViewRowAnimationNone];
    }];
    [alertController addAction:ramSizeSaveAction];
    ramSizeSaveAction.enabled = YES;
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)validateRAMSizeInput:(id)sender {
    NSInteger value = ramSizeField.text.integerValue;
    ramSizeSaveAction.enabled = value >= 1 && value <= 128;
}

#pragma mark - Field Delegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == modelField || textField == ramSizeField) {
        if (string.length == 0) {
            return YES;
        } else {
            NSString *newString = [textField.text stringByReplacingCharactersInRange:range withString:string];
            NSScanner *scanner = [NSScanner scannerWithString:newString];
            NSInteger value;
            return [scanner scanInteger:&value] && scanner.isAtEnd && value >= 0;
        }
    }
    return YES;
}

@end
