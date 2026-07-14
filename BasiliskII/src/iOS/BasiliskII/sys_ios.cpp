/*
 *  sys_unix.cpp - System dependent routines, Unix implementation
 *
 *  Basilisk II (C) Christian Bauer
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

#include <sys/ioctl.h>
#include <sys/stat.h>
#include <errno.h>

#ifdef HAVE_AVAILABILITYMACROS_H
#include <AvailabilityMacros.h>
#endif

#ifdef __linux__
#include <sys/mount.h>
#include <linux/cdrom.h>
#include <linux/fd.h>
#include <linux/major.h>
#include <linux/kdev_t.h>
#include <dirent.h>
#include <limits.h>
#endif

#if defined(__FreeBSD__) || defined(__NetBSD__)
#include <sys/cdio.h>
#endif

#include "main.h"
#include "macos_util.h"
#include "prefs.h"
#include "user_strings.h"
#include "sys.h"
#include "../Unix/disk_unix.h"

#if defined(BINCUE)
#include "bincue_unix.h"
#endif



#define DEBUG 0
#include "debug.h"

static disk_factory *disk_factories[] = {
#ifndef STANDALONE_GUI
	//disk_sparsebundle_factory,
#if defined(HAVE_LIBVHD)
	disk_vhd_factory,
#endif
#endif
	NULL
};

// File handles are pointers to these structures
struct mac_file_handle {
	char *name;	        // Copy of device/file name
	int fd;

	bool is_file;		// Flag: plain file or /dev/something?
	bool is_floppy;		// Flag: floppy device
	bool is_cdrom;		// Flag: CD-ROM device
	bool read_only;		// Copy of Sys_open() flag

	loff_t start_byte;	// Size of file header (if any)
	loff_t file_size;	// Size of file data (only valid if is_file is true)

	bool is_media_present;		// Flag: media is inserted and available
	disk_generic *generic_disk;

#if defined(__linux__)
	int cdrom_cap;		// CD-ROM capability flags (only valid if is_cdrom is true)
#elif defined(__FreeBSD__)
	struct ioc_capability cdrom_cap;
#elif defined(__APPLE__) && defined(__MACH__)
	char *ioctl_name;	// For CDs on OS X - a device for special ioctls
	int ioctl_fd;
#endif

#if defined(BINCUE)
	bool is_bincue;		// Flag: BIN CUE file
	void *bincue_fd;
#endif
};

// Open file handles
struct open_mac_file_handle {
	mac_file_handle *fh;
	open_mac_file_handle *next;
};
static open_mac_file_handle *open_mac_file_handles = NULL;

// File handle of first floppy drive (for SysMountFirstFloppy())
static mac_file_handle *first_floppy = NULL;

// Prototypes
static void cdrom_close(mac_file_handle *fh);
static bool cdrom_open(mac_file_handle *fh, const char *path = NULL);


/*
 *  Initialization
 */

void SysInit(void)
{

}


/*
 *  Deinitialization
 */

void SysExit(void)
{

}


/*
 *  Manage open file handles
 */

static void sys_add_mac_file_handle(mac_file_handle *fh)
{
	open_mac_file_handle *p = new open_mac_file_handle;
	p->fh = fh;
	p->next = open_mac_file_handles;
	open_mac_file_handles = p;
}

static void sys_remove_mac_file_handle(mac_file_handle *fh)
{
	open_mac_file_handle *p = open_mac_file_handles;
	open_mac_file_handle *q = NULL;

	while (p) {
		if (p->fh == fh) {
			if (q)
				q->next = p->next;
			else
				open_mac_file_handles = p->next;
			delete p;
			break;
		}
		q = p;
		p = p->next;
	}
}

/*
 *  This gets called when no "floppy" prefs items are found
 *  It scans for available floppy drives and adds appropriate prefs items
 */

void SysAddFloppyPrefs(void)
{

}


/*
 *  This gets called when no "disk" prefs items are found
 *  It scans for available HFS volumes and adds appropriate prefs items
 *	On OS X, we could do the same, but on an OS X machine I think it is
 *	very unlikely that any mounted volumes would contain a system which
 *	is old enough to boot a 68k Mac, so we just do nothing here for now.
 */

void SysAddDiskPrefs(void)
{

}


/*
 *  This gets called when no "cdrom" prefs items are found
 *  It scans for available CD-ROM drives and adds appropriate prefs items
 */

void SysAddCDROMPrefs(void)
{

}


/*
 *  Add default serial prefs (must be added, even if no ports present)
 */

void SysAddSerialPrefs(void)
{

}


/*
 *  Close a CD-ROM device
 */

void cdrom_close(mac_file_handle *fh)
{

	if (fh->fd >= 0) {
		close(fh->fd);
		fh->fd = -1;
	}
	if (fh->name) {
		free(fh->name);
		fh->name = NULL;
	}
#if defined __MACOSX__
	if (fh->ioctl_fd >= 0) {
		close(fh->ioctl_fd);
		fh->ioctl_fd = -1;
	}
	if (fh->ioctl_name) {
		free(fh->ioctl_name);
		fh->ioctl_name = NULL;
	}
#endif
}

/*
 *  Open file/device, create new file handle (returns NULL on error)
 */
 
static mac_file_handle *open_filehandle(const char *name)
{
		mac_file_handle *fh = new mac_file_handle;
		memset(fh, 0, sizeof(mac_file_handle));
		fh->name = strdup(name);
		fh->fd = -1;
		fh->generic_disk = NULL;
#if defined __MACOSX__
		fh->ioctl_fd = -1;
		fh->ioctl_name = NULL;
#endif
		return fh;
}

void *Sys_open(const char *name, bool read_only)
{
    // is it a cdrom?
    bool is_cdrom = false;
	{
		int index = 0;
		const char *str;
		while ((str = PrefsFindString("cdrom", index++)) != NULL) {
			if (strcmp(str, name) == 0) {
				is_cdrom = true;
				read_only = true;
				break;
			}
		}
	}
    
	D(bug("Sys_open(%s, %s)\n", name, read_only ? "read-only" : "read/write"));

	// Check if write access is allowed, set read-only flag if not
	if (!read_only && access(name, W_OK))
		read_only = true;

	// Open file/device

#if defined(BINCUE)
	void *binfd = open_bincue(name);
	if (binfd) {
		mac_file_handle *fh = open_filehandle(name);
		D(bug("opening %s as bincue\n", name));
		fh->bincue_fd = binfd;
		fh->is_bincue = true;
		fh->read_only = true;
		fh->is_media_present = true;
		sys_add_mac_file_handle(fh);
		return fh;
	}
#endif


	for (int i = 0; disk_factories[i]; ++i) {
		disk_factory *f = disk_factories[i];
		disk_generic *generic;
		disk_generic::status st = f(name, read_only, &generic);
		if (st == disk_generic::DISK_INVALID)
			return NULL;
		if (st == disk_generic::DISK_VALID) {
			mac_file_handle *fh = open_filehandle(name);
			fh->generic_disk = generic;
			fh->file_size = generic->size();
			fh->read_only = generic->is_read_only();
			fh->is_media_present = true;
			sys_add_mac_file_handle(fh);
			return fh;
		}
	}

	int open_flags = O_EXLOCK | O_NONBLOCK | (read_only ? O_RDONLY : O_RDWR);
	int fd = open(name, open_flags);
	if (fd < 0 && (open_flags & O_EXLOCK)) {
		if (errno == EOPNOTSUPP) {
			// File system does not support locking. Try again without.
			open_flags &= ~O_EXLOCK;
			fd = open(name, open_flags);
		} else if (errno == EAGAIN) {
			// File is likely already locked by another process.
			printf("WARNING: Cannot open %s (%s)\n", name, strerror(errno));
			return NULL;
        } else {
            printf("WARNING: Cannot open %s (%s)\n", name, strerror(errno));
            return NULL;
        }
	}
    
	if (fd < 0 && !read_only) {
		// Read-write failed, try read-only
		read_only = true;
		fd = open(name, O_RDONLY);
	}
	if (fd >= 0) {
		mac_file_handle *fh = open_filehandle(name);
		fh->fd = fd;
		fh->is_file = true;
		fh->read_only = read_only;
		fh->is_floppy = false;
		fh->is_cdrom = is_cdrom;
        fh->is_media_present = true;
        // Detect disk image file layout
        loff_t size = 0;
        size = lseek(fd, 0, SEEK_END);
        uint8 data[256];
        lseek(fd, 0, SEEK_SET);
        read(fd, data, 256);
        FileDiskLayout(size, data, fh->start_byte, fh->file_size);
		sys_add_mac_file_handle(fh);
		return fh;
	} else {
		printf("WARNING: Cannot open %s (%s)\n", name, strerror(errno));
		return NULL;
	}
}


/*
 *  Close file/device, delete file handle
 */

void Sys_close(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return;

	sys_remove_mac_file_handle(fh);

#if defined(BINCUE)
	if (fh->is_bincue)
		close_bincue(fh->bincue_fd);
#endif
	if (fh->generic_disk)
		delete fh->generic_disk;

	if (fh->is_cdrom)
		cdrom_close(fh);
	if (fh->fd >= 0)
		close(fh->fd);
	if (fh->name)
		free(fh->name);
	delete fh;
}


/*
 *  Read "length" bytes from file/device, starting at "offset", to "buffer",
 *  returns number of bytes read (or 0)
 */

size_t Sys_read(void *arg, void *buffer, loff_t offset, size_t length)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return 0;

#if defined(BINCUE)
	if (fh->is_bincue)
		return read_bincue(fh->bincue_fd, buffer, offset, length);
#endif

	if (fh->generic_disk)
		return fh->generic_disk->read(buffer, offset, length);
	
	// Seek to position
	if (lseek(fh->fd, offset + fh->start_byte, SEEK_SET) < 0)
		return 0;

	// Read data
	return read(fh->fd, buffer, length);
}


/*
 *  Write "length" bytes from "buffer" to file/device, starting at "offset",
 *  returns number of bytes written (or 0)
 */

size_t Sys_write(void *arg, void *buffer, loff_t offset, size_t length)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return 0;

	if (fh->generic_disk)
		return fh->generic_disk->write(buffer, offset, length);

	// Seek to position
	if (lseek(fh->fd, offset + fh->start_byte, SEEK_SET) < 0)
		return 0;

	// Write data
	return write(fh->fd, buffer, length);
}


/*
 *  Return size of file/device (minus header)
 */

loff_t SysGetFileSize(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return true;

#if defined(BINCUE)
	if (fh->is_bincue)
		return size_bincue(fh->bincue_fd);
#endif 

	if (fh->generic_disk)
		return fh->file_size;

	if (fh->is_file)
		return fh->file_size;
	else {
#if defined(__linux__)
		long blocks;
		if (ioctl(fh->fd, BLKGETSIZE, &blocks) < 0)
			return 0;
		D(bug(" BLKGETSIZE returns %d blocks\n", blocks));
		return (loff_t)blocks * 512;
#elif defined __MACOSX__
		uint32 block_size;
		if (ioctl(fh->ioctl_fd, DKIOCGETBLOCKSIZE, &block_size) < 0)
			return 0;
		D(bug(" DKIOCGETBLOCKSIZE returns %lu bytes\n", (unsigned long)block_size));
		uint64 block_count;
		if (ioctl(fh->ioctl_fd, DKIOCGETBLOCKCOUNT, &block_count) < 0)
			return 0;
		D(bug(" DKIOCGETBLOCKCOUNT returns %llu blocks\n", (unsigned long long)block_count));
		return block_count * block_size;
#else
		return lseek(fh->fd, 0, SEEK_END) - fh->start_byte;
#endif
	}
}


/*
 *  Eject volume (if applicable)
 */

void SysEject(void *arg)
{

}


/*
 *  Format volume (if applicable)
 */

bool SysFormat(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

	//!!
	return true;
}


/*
 *  Check if file/device is read-only (this includes the read-only flag on Sys_open())
 */

bool SysIsReadOnly(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return true;

#if defined(__linux__)
	if (fh->is_floppy) {
		if (fh->fd >= 0) {
			struct floppy_drive_struct stat;
			ioctl(fh->fd, FDGETDRVSTAT, &stat);
			return !(stat.flags & FD_DISK_WRITABLE);
		} else
			return true;
	} else
#endif
		return fh->read_only;
}


/*
 *  Check if the given file handle refers to a fixed or a removable disk
 */

bool SysIsFixedDisk(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return true;

	if (fh->generic_disk)
		return true;

	if (fh->is_file)
		return true;
	else if (fh->is_floppy || fh->is_cdrom)
		return false;
	else
		return true;
}


/*
 *  Check if a disk is inserted in the drive (always true for files)
 */

bool SysIsDiskInserted(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

	if (fh->generic_disk)
		return true;
	
	if (fh->is_file) {
		return true;

#if defined(__linux__)
	} else if (fh->is_floppy) {
		char block[512];
		lseek(fh->fd, 0, SEEK_SET);
		ssize_t actual = read(fh->fd, block, 512);
		if (actual < 0) {
			close(fh->fd);	// Close and reopen so the driver will see the media change
			fh->fd = open(fh->name, fh->read_only ? O_RDONLY : O_RDWR);
			actual = read(fh->fd, block, 512);
		}
		return actual == 512;
	} else if (fh->is_cdrom) {
#ifdef CDROM_MEDIA_CHANGED
		if (fh->cdrom_cap & CDC_MEDIA_CHANGED) {
			// If we don't do this, all attempts to read from a disc fail
			// once the tray has been opened (altough the TOC reads fine).
			// Can somebody explain this to me?
			if (ioctl(fh->fd, CDROM_MEDIA_CHANGED) == 1) {
				close(fh->fd);
				fh->fd = open(fh->name, O_RDONLY | O_NONBLOCK);
			}
		}
#endif
#ifdef CDROM_DRIVE_STATUS
		if (fh->cdrom_cap & CDC_DRIVE_STATUS) {
			return ioctl(fh->fd, CDROM_DRIVE_STATUS, CDSL_CURRENT) == CDS_DISC_OK;
		}
#endif
		cdrom_tochdr header;
		return ioctl(fh->fd, CDROMREADTOCHDR, &header) == 0;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
	} else if (fh->is_floppy) {
		return false;	//!!
	} else if (fh->is_cdrom) {
		struct ioc_toc_header header;
		return ioctl(fh->fd, CDIOREADTOCHEADER, &header) == 0;
#elif defined __MACOSX__
	} else if (fh->is_cdrom || fh->is_floppy) {
		return fh->is_media_present;
#endif

	} else
		return true;
}


/*
 *  Prevent medium removal (if applicable)
 */

void SysPreventRemoval(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return;

#if defined(__linux__) && defined(CDROM_LOCKDOOR)
	if (fh->is_cdrom)
		ioctl(fh->fd, CDROM_LOCKDOOR, 1);	
#endif
}


/*
 *  Allow medium removal (if applicable)
 */

void SysAllowRemoval(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return;

#if defined(__linux__) && defined(CDROM_LOCKDOOR)
	if (fh->is_cdrom)
		ioctl(fh->fd, CDROM_LOCKDOOR, 0);	
#endif
}


/*
 *  Read CD-ROM TOC (binary MSF format, 804 bytes max.)
 */

bool SysCDReadTOC(void *arg, uint8 *toc)
{
	return false;
}


/*
 *  Read CD-ROM position data (Sub-Q Channel, 16 bytes, see SCSI standard)
 */

bool SysCDGetPosition(void *arg, uint8 *pos)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

#if defined(BINCUE)
	if (fh->is_bincue)
		return GetPosition_bincue(fh->bincue_fd, pos);
#endif

	if (fh->is_cdrom) {
#if defined(__linux__)
		cdrom_subchnl chan;
		chan.cdsc_format = CDROM_MSF;
		if (ioctl(fh->fd, CDROMSUBCHNL, &chan) < 0)
			return false;
		*pos++ = 0;
		*pos++ = chan.cdsc_audiostatus;
		*pos++ = 0;
		*pos++ = 12;	// Sub-Q data length
		*pos++ = 0;
		*pos++ = (chan.cdsc_adr << 4) | chan.cdsc_ctrl;
		*pos++ = chan.cdsc_trk;
		*pos++ = chan.cdsc_ind;
		*pos++ = 0;
		*pos++ = chan.cdsc_absaddr.msf.minute;
		*pos++ = chan.cdsc_absaddr.msf.second;
		*pos++ = chan.cdsc_absaddr.msf.frame;
		*pos++ = 0;
		*pos++ = chan.cdsc_reladdr.msf.minute;
		*pos++ = chan.cdsc_reladdr.msf.second;
		*pos++ = chan.cdsc_reladdr.msf.frame;
		return true;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
		struct ioc_read_subchannel chan;
		chan.data_format = CD_MSF_FORMAT;
		chan.address_format = CD_MSF_FORMAT;
		chan.track = CD_CURRENT_POSITION;
		if (ioctl(fh->fd, CDIOCREADSUBCHANNEL, &chan) < 0)
			return false;
		*pos++ = 0;
		*pos++ = chan.data->header.audio_status;
		*pos++ = 0;
		*pos++ = 12;	// Sub-Q data length
		*pos++ = 0;
		*pos++ = (chan.data->what.position.addr_type << 4) | chan.data->what.position.control;
		*pos++ = chan.data->what.position.track_number;
		*pos++ = chan.data->what.position.index_number;
		*pos++ = 0;
		*pos++ = chan.data->what.position.absaddr.msf.minute;
		*pos++ = chan.data->what.position.absaddr.msf.second;
		*pos++ = chan.data->what.position.absaddr.msf.frame;
		*pos++ = 0;
		*pos++ = chan.data->what.position.reladdr.msf.minute;
		*pos++ = chan.data->what.position.reladdr.msf.second;
		*pos++ = chan.data->what.position.reladdr.msf.frame;
		return true;
#else
		return false;
#endif
	} else
		return false;
}


/*
 *  Play CD audio
 */

bool SysCDPlay(void *arg, uint8 start_m, uint8 start_s, uint8 start_f, uint8 end_m, uint8 end_s, uint8 end_f)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

#if defined(BINCUE)
	if (fh->is_bincue)
		return CDPlay_bincue(fh->bincue_fd, start_m, start_s, start_f, end_m, end_s, end_f);
#endif

	if (fh->is_cdrom) {
#if defined(__linux__)
		cdrom_msf play;
		play.cdmsf_min0 = start_m;
		play.cdmsf_sec0 = start_s;
		play.cdmsf_frame0 = start_f;
		play.cdmsf_min1 = end_m;
		play.cdmsf_sec1 = end_s;
		play.cdmsf_frame1 = end_f;
		return ioctl(fh->fd, CDROMPLAYMSF, &play) == 0;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
		struct ioc_play_msf play;
		play.start_m = start_m;
		play.start_s = start_s;
		play.start_f = start_f;
		play.end_m = end_m;
		play.end_s = end_s;
		play.end_f = end_f;
		return ioctl(fh->fd, CDIOCPLAYMSF, &play) == 0;
#else
		return false;
#endif
	} else
		return false;
}


/*
 *  Pause CD audio
 */

bool SysCDPause(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

#if defined(BINCUE)
	if (fh->is_bincue)
		return CDPause_bincue(fh->bincue_fd);
#endif

	if (fh->is_cdrom) {
#if defined(__linux__)
		return ioctl(fh->fd, CDROMPAUSE) == 0;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
		return ioctl(fh->fd, CDIOCPAUSE) == 0;
#else
		return false;
#endif
	} else
		return false;
}


/*
 *  Resume paused CD audio
 */

bool SysCDResume(void *arg)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

#if defined(BINCUE)
	if (fh->is_bincue)
		return CDResume_bincue(fh->bincue_fd);
#endif


	if (fh->is_cdrom) {
#if defined(__linux__)
		return ioctl(fh->fd, CDROMRESUME) == 0;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
		return ioctl(fh->fd, CDIOCRESUME) == 0;
#else
		return false;
#endif
	} else
		return false;
}


/*
 *  Stop CD audio
 */

bool SysCDStop(void *arg, uint8 lead_out_m, uint8 lead_out_s, uint8 lead_out_f)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

#if defined(BINCUE)
	if (fh->is_bincue)
		return CDStop_bincue(fh->bincue_fd);
#endif


	if (fh->is_cdrom) {
#if defined(__linux__)
		return ioctl(fh->fd, CDROMSTOP) == 0;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
		return ioctl(fh->fd, CDIOCSTOP) == 0;
#else
		return false;
#endif
	} else
		return false;
}


/*
 *  Perform CD audio fast-forward/fast-reverse operation starting from specified address
 */

bool SysCDScan(void *arg, uint8 start_m, uint8 start_s, uint8 start_f, bool reverse)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return false;

	// Not supported under Linux
	return false;
}


/*
 *  Set CD audio volume (0..255 each channel)
 */

void SysCDSetVolume(void *arg, uint8 left, uint8 right)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return;

	if (fh->is_cdrom) {
#if defined(__linux__)
		cdrom_volctrl vol;
		vol.channel0 = vol.channel2 = left;
		vol.channel1 = vol.channel3 = right;
		ioctl(fh->fd, CDROMVOLCTRL, &vol);
#elif defined(__FreeBSD__) || defined(__NetBSD__)
		struct ioc_vol vol;
		vol.vol[0] = vol.vol[2] = left;
		vol.vol[1] = vol.vol[3] = right;
		ioctl(fh->fd, CDIOCSETVOL, &vol);
#endif
	}
}


/*
 *  Get CD audio volume (0..255 each channel)
 */

void SysCDGetVolume(void *arg, uint8 &left, uint8 &right)
{
	mac_file_handle *fh = (mac_file_handle *)arg;
	if (!fh)
		return;

	left = right = 0;
	if (fh->is_cdrom) {
#if defined(__linux__)
		cdrom_volctrl vol;
		ioctl(fh->fd, CDROMVOLREAD, &vol);
		left = vol.channel0;
		right = vol.channel1;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
		struct ioc_vol vol;
		ioctl(fh->fd, CDIOCGETVOL, &vol);
		left = vol.vol[0];
		right = vol.vol[1];
#endif
	}
}
