/*
 *  xpram_ios.mm - XPRAM handling through NSUserDefaults
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

#include "xpram.h"


// XPRAM defaults key
static NSString * XPRAM_KEY = @"xpram_data";

/*
 *  Load XPRAM from user defaults
 */

void LoadXPRAM(const char *vmdir) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *xpramData = [defaults objectForKey:XPRAM_KEY];
    if ([xpramData isKindOfClass:[NSData class]] && xpramData.length == XPRAM_SIZE)
        memcpy(XPRAM, xpramData.bytes, XPRAM_SIZE);
}


/*
 *  Save XPRAM to user defaults
 */

void SaveXPRAM(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *xpramData = [NSData dataWithBytes:XPRAM length:XPRAM_SIZE];
    [defaults setObject:xpramData forKey:XPRAM_KEY];
}


/*
 *  Delete PRAM file
 */

void ZapPRAM(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:XPRAM_KEY];
}
