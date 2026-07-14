//
//  B2Application.mm
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 20/04/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2Application.h"
#import "B2AppDelegate.h"
#import "sysdeps.h"
#import "adb.h"

static int8_t usb_to_adb_scancode[] = {
    -1, -1, -1, -1, 0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37,
    46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6, 18, 19,
    20, 21, 23, 22, 26, 28, 25, 29, 36, 53, 51, 48, 49, 27, 24, 33,
    30, 42, 42, 41, 39, 10, 43, 47, 44, 57, 122, 120, 99, 118, 96, 97,
    98, 100, 101, 109, 103, 111, 105, 107, 113, 114, 115, 116, 117, 119, 121, 60,
    59, 61, 62, 71, 75, 67, 78, 69, 76, 83, 84, 85, 86, 87, 88, 89,
    91, 92, 82, 65, 50, 55, 126, 81, 105, 107, 113, 106, 64, 79, 80, 90,
    -1, -1, -1, -1, -1, 114, -1, -1, -1, -1, -1, -1, -1, -1, -1, 74,
    72, 73, -1, -1, -1, 95, -1, 94, -1, 93, -1, -1, -1, -1, -1, -1,
    104, 102, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    54, 56, 58, 55, 54, 56, 58, 55, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
};

@implementation B2Application
{
    BOOL physicalCapsLocked;
}

- (BOOL)handleKeyboardPress:(UIPress *)press keyDown:(BOOL)keyDown API_AVAILABLE(ios(13.4)) {
    UIKey *key = press.key;
    if (key == nil || ![B2AppDelegate sharedInstance].emulatorRunning) {
        return NO;
    }

    long keycode = key.keyCode;
    int scancode = -1;
    
    if (keycode >= 0 && keycode < sizeof(usb_to_adb_scancode)) {
        scancode = usb_to_adb_scancode[keycode];
    }
    
    if (scancode == 57) {
        // caps lock
        if (keyDown && !physicalCapsLocked) {
            ADBKeyDown(scancode);
            physicalCapsLocked = YES;
        } else if (keyDown && physicalCapsLocked) {
            ADBKeyUp(scancode);
            physicalCapsLocked = NO;
        }
        return YES;
    } else if (scancode >= 0) {
        if (keyDown) {
            [self updateCapsLockStatusForKey:key];
            ADBKeyDown(scancode);
        } else {
            ADBKeyUp(scancode);
        }
        return YES;
    }

    return NO;
}

- (void)updateCapsLockStatusForKey:(UIKey *)key API_AVAILABLE(ios(13.4)) {
    NSString *unmodifiedInput = key.charactersIgnoringModifiers;
    NSString *modifiedInput = key.characters;

    if (key.modifierFlags == 0 && unmodifiedInput.length == 1 && modifiedInput.length == 1) {
        unichar unmodifiedChar = [unmodifiedInput characterAtIndex:0];
        unichar modifiedChar = [modifiedInput characterAtIndex:0];
        if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:unmodifiedChar]) {
            BOOL currentCapsLock = [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:modifiedChar];
            if (currentCapsLock != physicalCapsLocked) {
                physicalCapsLocked = currentCapsLock;
                if (physicalCapsLocked) {
                    NSLog(@"locking caps");
                    ADBKeyDown(57);
                } else {
                    NSLog(@"unlocking caps");
                    ADBKeyUp(57);
                }
            }
        }
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;

    if (@available(iOS 13.4, *)) {
        for (UIPress *press in presses) {
            handled = [self handleKeyboardPress:press keyDown:YES] || handled;
        }
    }

    if (!handled) {
        [super pressesBegan:presses withEvent:event];
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;

    if (@available(iOS 13.4, *)) {
        for (UIPress *press in presses) {
            handled = [self handleKeyboardPress:press keyDown:NO] || handled;
        }
    }

    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

@end
