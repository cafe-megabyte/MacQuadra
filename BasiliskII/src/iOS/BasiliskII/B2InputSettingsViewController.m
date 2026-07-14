//
//  B2InputSettingsViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 10/04/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2InputSettingsViewController.h"
#import "B2AppDelegate.h"

typedef enum : NSInteger {
    B2InputSectionMouse,
    B2InputSectionKeyboardLayout
} B2InputSection;

@interface B2InputSettingsViewController ()

@end

@implementation B2InputSettingsViewController
{
    NSArray *keyboardLayouts;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    keyboardLayouts = [B2AppDelegate sharedInstance].availableKeyboardLayouts;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case B2InputSectionMouse:
            return 1;
        case B2InputSectionKeyboardLayout:
            return keyboardLayouts.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case B2InputSectionMouse:
            return L(@"settings.input.mouse");
        case B2InputSectionKeyboardLayout:
            return L(@"settings.input.keyboard.layout.header");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case B2InputSectionKeyboardLayout:
            return L(@"settings.input.keyboard.layout.footer");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"basic" forIndexPath:indexPath];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if (indexPath.section == B2InputSectionMouse) {
        cell.textLabel.text = L(@"settings.input.mouse.type");
        UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:@[L(@"settings.input.mouse.type.touchscreen"), L(@"settings.input.mouse.type.trackpad")]];
        [segmentedControl addTarget:self action:@selector(changeMouseType:) forControlEvents:UIControlEventValueChanged];
        segmentedControl.selectedSegmentIndex = [defaults boolForKey:@"trackpad"] ? 1 : 0;
        cell.accessoryView = segmentedControl;
    } else if (indexPath.section == B2InputSectionKeyboardLayout) {
        NSString *layout = keyboardLayouts[indexPath.row];
        cell.textLabel.text = layout.lastPathComponent.stringByDeletingPathExtension;
        BOOL selected = [[defaults stringForKey:@"keyboardLayout"] isEqualToString:layout.lastPathComponent];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (indexPath.section == B2InputSectionKeyboardLayout) {
        NSString *layout = keyboardLayouts[indexPath.row];
        [defaults setValue:layout.lastPathComponent forKey:@"keyboardLayout"];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)changeMouseType:(UISegmentedControl*)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(sender.selectedSegmentIndex == 1) forKey:@"trackpad"];
}

@end
