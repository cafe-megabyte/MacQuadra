//
//  B2NetworkSettingsViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 11/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2NetworkSettingsViewController.h"

@interface B2NetworkSettingsViewController () <UITextFieldDelegate>

@end

@implementation B2NetworkSettingsViewController
{
    __block UITextField *udpPortField;
    UIAlertAction *udpPortSaveAction;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return L(@"settings.net.interface");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return L(@"settings.net.interface.help");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellIdentifier = indexPath.row == 1 ? @"detail" : @"basic";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL cellChecked = NO;
    
    switch (indexPath.row) {
        case 0:
            cell.textLabel.text = L(@"settings.net.interface.slirp");
            cellChecked = [[defaults stringForKey:@"ether"] isEqualToString:@"slirp"];
            break;
        case 1:
            cell.textLabel.text = L(@"settings.net.interface.udptunnel");
            cellChecked = [defaults boolForKey:@"udptunnel"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)[defaults integerForKey:@"udpport"]];
            break;
        case 2:
            cell.textLabel.text = L(@"settings.net.interface.none");
            cellChecked = !([[defaults stringForKey:@"ether"] isEqualToString:@"slirp"] || [defaults boolForKey:@"udptunnel"]);
            break;
        default:
            break;
    }
    cell.accessoryType = cellChecked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    switch (indexPath.row) {
        case 0:
            [defaults setValue:@"slirp" forKey:@"ether"];
            [defaults setBool:NO forKey:@"udptunnel"];
            break;
        case 1:
            if ([defaults boolForKey:@"udptunnel"]) {
                [self askForUDPPort];
            } else {
                [defaults setValue:@"none" forKey:@"ether"];
                [defaults setBool:YES forKey:@"udptunnel"];
            }
            break;
        case 2:
            [defaults setValue:@"none" forKey:@"ether"];
            [defaults setBool:NO forKey:@"udptunnel"];
            break;
        default:
            break;
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UDP Port Dialog

- (void)askForUDPPort {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:L(@"settings.net.udpport.title") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"udpport";
        textField.text = [NSString stringWithFormat:@"%d", (int)[defaults integerForKey:@"udpport"]];
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.delegate = self;
        [textField addTarget:self action:@selector(validateUDPPortInput:) forControlEvents:UIControlEventAllEditingEvents];
        udpPortField = textField;
    }];
    
    [alertController addAction:[UIAlertAction actionWithTitle:L(@"misc.cancel") style:UIAlertActionStyleCancel handler:nil]];
    udpPortSaveAction = [UIAlertAction actionWithTitle:L(@"misc.ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSInteger port = udpPortField.text.integerValue;
        [defaults setInteger:port forKey:@"udpport"];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    [alertController addAction:udpPortSaveAction];
    udpPortSaveAction.enabled = YES;
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)validateUDPPortInput:(id)sender {
    NSInteger value = udpPortField.text.integerValue;
    udpPortSaveAction.enabled = value > 1024 && value < 65536;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == udpPortField) {
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
