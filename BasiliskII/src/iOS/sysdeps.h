/*
 *  sysdeps.h - System dependent definitions for Unix
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

#ifndef SYSDEPS_H
#define SYSDEPS_H

#include "config.h"
#include "../Unix/user_strings_unix.h"

#include <sys/types.h>
#include <unistd.h>
#include <libkern/OSAtomic.h>
#include <libkern/OSByteOrder.h>
#include <netinet/in.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <fcntl.h>
#include <sys/time.h>
#include <time.h>
#include <mach/clock.h>

/* Mac and host address space are distinct */
#define REAL_ADDRESSING 0
#define DIRECT_ADDRESSING 0

/* Using 68k emulator */
#define EMULATED_68K 1

/* The m68k emulator uses a prefetch buffer ? */
#define USE_PREFETCH_BUFFER 0

/* Mac ROM is write protected when banked memory is used */
#if REAL_ADDRESSING || DIRECT_ADDRESSING
# define ROM_IS_WRITE_PROTECTED 0
# define USE_SCRATCHMEM_SUBTERFUGE 1
#else
# define ROM_IS_WRITE_PROTECTED 1
#endif

/* ExtFS is supported */
#define SUPPORTS_EXTFS 1

/* BSD socket API supported */
#define SUPPORTS_UDP_TUNNEL 1

/* Use the CPU emulator to check for periodic tasks? */
#define USE_PTHREADS_SERVICES

/* Data types */
typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;
typedef uintptr_t uintptr;
typedef int8_t int8;
typedef int16_t int16;
typedef int32_t int32;
typedef int64_t int64;
typedef intptr_t intptr;
typedef off_t loff_t;
typedef char * caddr_t;
#define VAL64(a) (a ## LL)
#define UVAL64(a) (a ## uLL)

/* Time data type for Time Manager emulation */
typedef mach_timespec_t tm_time_t;

/* Define codes for all the float formats that we know of.
 * Though we only handle IEEE format.  */
#define UNKNOWN_FLOAT_FORMAT 0
#define IEEE_FLOAT_FORMAT 1
#define VAX_FLOAT_FORMAT 2
#define IBM_FLOAT_FORMAT 3
#define C4X_FLOAT_FORMAT 4

/* UAE CPU data types */
#define uae_s8 int8
#define uae_u8 uint8
#define uae_s16 int16
#define uae_u16 uint16
#define uae_s32 int32
#define uae_u32 uint32
#define uae_s64 int64
#define uae_u64 uint64
typedef uae_u32 uaecptr;

/* Timing functions */
extern uint64 GetTicks_usec(void);
extern void Delay_usec(uint32 usec);

/* Spinlocks */
typedef OSSpinLock spinlock_t;
static const spinlock_t SPIN_LOCK_UNLOCKED = OS_SPINLOCK_INIT;

#define HAVE_SPINLOCKS 1
#define spin_lock(lock) OSSpinLockLock(lock)
#define spin_unlock(lock) OSSpinLockUnlock(lock)
#define spin_trylock(lock) OSSpinLockTry(lock)

/* Centralized pthread attribute setup */
void Set_pthread_attr(pthread_attr_t *attr, int priority);

/* UAE CPU defines */
#define do_get_mem_long(a) OSReadBigInt32((a), 0)
#define do_put_mem_long(a,v) OSWriteBigInt32((a), 0, (v))

#define do_get_mem_word(a) OSReadBigInt16((a), 0)
#define do_put_mem_word(a,v) OSWriteBigInt16((a), 0, (v))

#define do_get_mem_byte(a) ((uae_u32)*((uae_u8 *)(a)))
#define do_put_mem_byte(a, v) (*(uae_u8 *)(a) = (v))

#define do_byteswap_32(v) _OSSwapInt32((v))
#define do_byteswap_16(v) _OSSwapInt16((int16_t)(v))

#define call_mem_get_func(func, addr) ((*func)(addr))
#define call_mem_put_func(func, addr, v) ((*func)(addr, v))
#define __inline__ inline
#define CPU_EMU_SIZE 0
#undef NO_INLINE_MEMORY_ACCESS
#undef MD_HAVE_MEM_1_FUNCS
#define ENUMDECL typedef enum
#define ENUMNAME(name) name
#define write_log printf

#if defined(X86_ASSEMBLY) || defined(X86_64_ASSEMBLY)
#define ASM_SYM(a) __asm__(a)
#else
#define ASM_SYM(a)
#endif

#ifndef REGPARAM
# define REGPARAM
#endif
#define REGPARAM2

#endif
