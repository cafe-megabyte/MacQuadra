/*
 *  clip_dummy.cpp - Clipboard handling, dummy implementation
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

#import <MobileCoreServices/MobileCoreServices.h>

#include "sysdeps.h"

#include "clip.h"
#include "cpu_emulation.h"
#include "main.h"
#include "emul_op.h"
#include "rom_patches.h"

#define noErr basilisk_noErr
#include "macos_util.h"
#undef noErr

#define DEBUG 0
#include "debug.h"

static bool in_getscrap = false;

/*
 *  Initialization
 */

void ClipInit(void)
{
}


/*
 *  Deinitialization
 */

void ClipExit(void)
{
}


/*
 *  Mac application reads clipboard
 */

void GetScrap(void **handle, uint32 type, int32 offset)
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    
    if (type == 'TEXT' && pasteboard.string != nil) {
        NSData *data = [[pasteboard.string stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"] dataUsingEncoding:NSMacOSRomanStringEncoding allowLossyConversion:YES];
        // Allocate space for new scrap in MacOS side
        M68kRegisters r;
        r.d[0] = (uint32)data.length;
        Execute68kTrap(0xa71e, &r);				// NewPtrSysClear()
        uint32 scrap_area = r.a[0];
        
        // Get the native clipboard data
        if (scrap_area) {
            // Add new data to clipboard
            static uint8 proc[] = {
                0x59, 0x8f,					// subq.l	#4,sp
                0xa9, 0xfc,					// ZeroScrap()
                0x2f, 0x3c, 0, 0, 0, 0,		// move.l	#length,-(sp)
                0x2f, 0x3c, 0, 0, 0, 0,		// move.l	#type,-(sp)
                0x2f, 0x3c, 0, 0, 0, 0,		// move.l	#outbuf,-(sp)
                0xa9, 0xfe,					// PutScrap()
                0x58, 0x8f,					// addq.l	#4,sp
                M68K_RTS >> 8, M68K_RTS & 0xff
            };
            r.d[0] = sizeof(proc);
            Execute68kTrap(0xa71e, &r);		// NewPtrSysClear()
            uint32 proc_area = r.a[0];
            
            if (proc_area) {
                Host2Mac_memcpy(scrap_area, data.bytes, data.length);
                Host2Mac_memcpy(proc_area, proc, sizeof(proc));
                WriteMacInt32(proc_area +  6, (uint32)data.length);
                WriteMacInt32(proc_area + 12, type);
                WriteMacInt32(proc_area + 18, scrap_area);
                in_getscrap = true;
                Execute68k(proc_area, &r);
                
                r.a[0] = proc_area;
                Execute68kTrap(0xa01f, &r);	// DisposePtr
            }
            
            r.a[0] = scrap_area;
            Execute68kTrap(0xa01f, &r);			// DisposePtr
            in_getscrap = false;
        }
    }
}

/*
 * ZeroScrap() is called before a Mac application writes to the clipboard; clears out the previous contents
 */

void ZeroScrap()
{
    
}

/*
 *  Mac application wrote to clipboard
 */

void PutScrap(uint32 type, void *scrap, int32 length)
{
    if (in_getscrap) return;
    if (type == 'TEXT') {
        [UIPasteboard generalPasteboard].string = [[[NSString alloc] initWithBytes:scrap length:length encoding:NSMacOSRomanStringEncoding] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    }
}
