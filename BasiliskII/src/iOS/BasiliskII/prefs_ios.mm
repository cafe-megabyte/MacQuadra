/*
 *  prefs_ios.mm - Preferences handling through NSUserDefaults
 *
 *  Basilisk II (C) 1997-2008 Christian Bauer
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "sysdeps.h"

#include <stdio.h>
#include <stdlib.h>

#include "prefs.h"

static NSUserDefaults *defaults = nil;
static NSMutableDictionary *defaultPrefs = nil;
static NSMutableDictionary *cachedPrefsStrings = nil;

void PrefsInit(const char *vmdir, int &argc, char **&argv)
{
    @autoreleasepool {
        defaults = [NSUserDefaults standardUserDefaults];
        cachedPrefsStrings = [NSMutableDictionary dictionaryWithCapacity:4];
        defaultPrefs = [NSMutableDictionary dictionaryWithCapacity:32];
        
        // Add defaults
        AddPrefsDefaults();
        
        // override defaults
        NSDictionary *layoutForLanguage = @{@"en": @"British.nfkeyboardlayout",
                                            @"es": @"Spanish (ISO).nfkeyboardlayout",
                                            @"en-US": @"US.nfkeyboardlayout"};
        NSString *firstLanguage = [NSBundle preferredLocalizationsFromArray:layoutForLanguage.allKeys].firstObject;
        [defaultPrefs addEntriesFromDictionary:@{@"extfs": @(vmdir),
                                                 @"idlewait": @YES,
                                                 @"ether": @"slirp",
                                                 @"rom": @"ROM",
                                                 @"frameskip": @2,
                                                 @"trackpad": @([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad),
                                                 @"keyboardLayout": layoutForLanguage[firstLanguage],
                                                 @"videoDepth": @(8),
                                                 @"screenFilter": kCAFilterLinear,
                                                 }];
        [defaults registerDefaults:defaultPrefs];
        defaultPrefs = nil;
    }

#ifdef SHEEPSHAVER
    // System specific initialization
    prefs_init();
#endif
}


/*
 *  Deinitialize preferences
 */

void PrefsExit(void)
{
#ifdef SHEEPSHAVER
    // System specific deinitialization
    prefs_exit();
#endif
    @autoreleasepool {
        defaults = nil;
        cachedPrefsStrings = nil;
    }
}


/*
 *  Set prefs items (only done during init)
 */

void PrefsAddBool(const char *name, bool b)
{
    @autoreleasepool {
        if (defaultPrefs) {
            [defaultPrefs setObject:@(b) forKey:@(name)];
        } else {
            [defaults setBool:b forKey:@(name)];
        }
    }
}

void PrefsAddInt32(const char *name, int32 val)
{
    @autoreleasepool {
        if (defaultPrefs) {
            [defaultPrefs setObject:@(val) forKey:@(name)];
        } else {
            [defaults setInteger:(NSInteger)val forKey:@(name)];
        }
    }
}

/*
 *  Get prefs items
 */

const char *PrefsFindString(const char *name, int index)
{
    @autoreleasepool {
        // cache in prefsStrings
        id value = cachedPrefsStrings[@(name)];
        if (value == nil) {
            value = [defaults valueForKey:@(name)];
            if (value != nil) {
                cachedPrefsStrings[@(name)] = value;
            }
        }
        
        if ([value isKindOfClass:[NSArray class]]) {
            if (index < [value count])
                return [[value objectAtIndex:index] UTF8String];
            else
                return NULL;
        } else if (index > 0) {
            return NULL;
        } else {
            if (![value isKindOfClass:[NSString class]])
                value = [value stringValue];
            return [value UTF8String];
        }
    }
}

bool PrefsFindBool(const char *name)
{
    @autoreleasepool {
        return [defaults boolForKey:@(name)];
    }
}

int32 PrefsFindInt32(const char *name)
{
    @autoreleasepool {
        return (int32)[defaults integerForKey:@(name)];
    }
}
