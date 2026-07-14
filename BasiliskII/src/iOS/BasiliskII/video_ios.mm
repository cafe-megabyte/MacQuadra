#include "sysdeps.h"

#include <pthread.h>
#include "adb.h"
#include "cpu_emulation.h"
#include "main.h"
#include "prefs.h"
#include "user_strings.h"
#include "video.h"
#include "debug.h"
#import "B2ScreenView.h"

#define DEBUG 0

// Mac Screen Width and Height
uint32 MacScreenWidth;
uint32 MacScreenHeight;

static uint8 bits_from_depth(const video_depth depth)
{
	return 1 << depth;
}

// Supported video modes
static vector<video_mode> VideoModes;

// Add mode to list of supported modes
static void
add_mode(const uint16 width, const uint16 height,
		 const uint32 resolution_id, const uint32 bytes_per_row,
		 const uint32 user_data,
		 const video_depth depth)
{
	vector<video_mode>::const_iterator	i,
    end = VideoModes.end();
    
	for (i = VideoModes.begin(); i != end; ++i)
		if ( i->x == width && i->y == height &&
            i->bytes_per_row == bytes_per_row && i->depth == depth )
		{
			D(NSLog(@"Duplicate mode (%hdx%hdx%u, ID %02x, new ID %02x)\n",
                    width, height, depth, i->resolution_id, resolution_id));
			return;
		}
    
	video_mode mode;
    
	mode.x = width;
	mode.y = height;
	mode.resolution_id = resolution_id;
	mode.bytes_per_row = bytes_per_row;
	mode.user_data = user_data;
	mode.depth = depth;
    
	D(bug("Added video mode: w=%d  h=%d  d=%d(%d bits)\n",
          width, height, depth, bits_from_depth(depth) ));
    
	VideoModes.push_back(mode);
}

// Add standard list of windowed modes for given color depth
static void add_standard_modes(const video_depth depth)
{
	int mode = 0x80;
    for (NSValue *modeValue in sharedScreenView.videoModes) {
        CGSize modeSize = modeValue.CGSizeValue;
        uint16 width = modeSize.width;
        uint16 height = modeSize.height;
        add_mode(width,  height,  mode++, TrivialBytesPerRow(width,  depth), 0, depth);
    }
}

class IOS_monitor : public monitor_desc
{
public:
    IOS_monitor(const vector<video_mode>	&available_modes,
                video_depth					default_depth,
                uint32						default_id);
    
    virtual void set_palette(uint8 *pal, int num);
    virtual void switch_to_current_mode(void);
    
    void set_mac_frame_buffer(const video_mode mode);
    
    void video_close(void);
    bool video_open (const video_mode &mode);
    bool update_image(void);
    
private:
    CGColorSpaceRef		colorSpace;
    uint8 				*colorTable;
    CGDataProviderRef	provider;
    short				x, y, bpc, bpp, bpr;
    uint8_t				*the_buffer;
    size_t              the_buffer_size;
};

IOS_monitor::IOS_monitor (const	vector<video_mode>	&available_modes,
                            video_depth			default_depth,
                            uint32				default_id)
: monitor_desc (available_modes, default_depth, default_id)
{
	colorSpace = nil;
	colorTable = (uint8 *) malloc(256 * 3);
	provider = nil;
	the_buffer = NULL;
};

bool IOS_monitor::video_open(const video_mode &mode)
{
    video_mode current_mode = mode;
    
    the_buffer_size = current_mode.bytes_per_row * (current_mode.y + 2);
    the_buffer = (uint8_t*)calloc(the_buffer_size, 1);
    if (the_buffer == NULL)
	{
		NSLog(@"calloc(%zu) failed", the_buffer_size);
		ErrorAlert(STR_NO_MEM_ERR);
		return false;
	}
    
    x = current_mode.x;
    y = current_mode.y;
    MacScreenWidth = x;
    MacScreenHeight = y;
    bpr = current_mode.bytes_per_row;
    
	colorSpace = CGColorSpaceCreateDeviceRGB();
    
	if ( current_mode.depth < VDEPTH_16BIT )
	{
		CGColorSpaceRef	oldColorSpace = colorSpace;
		colorSpace = CGColorSpaceCreateIndexed(colorSpace, 255, colorTable);
		CGColorSpaceRelease(oldColorSpace);
	}
    
	if (colorSpace == NULL)
	{
		ErrorAlert("No valid color space");
		return false;
	}
    
	provider = CGDataProviderCreateWithData(NULL, the_buffer, the_buffer_size, NULL);
	if (provider == NULL)
	{
		ErrorAlert("Could not create CGDataProvider from buffer data");
		return false;
	}

    sharedScreenView.screenSize = CGSizeMake(mode.x, mode.y);
    
    update_image();
    
	return true;
}

bool IOS_monitor::update_image()
{
    video_mode current_mode = get_current_mode();
    CGBitmapInfo options = 0;
    switch ( current_mode.depth )
	{
        case VDEPTH_1BIT:	bpc = 1; bpp = 1; options = kCGImageAlphaNone; break;
		case VDEPTH_2BIT:	bpc = 2; bpp = 2; options = kCGImageAlphaNone; break;
		case VDEPTH_4BIT:	bpc = 4; bpp = 4; options = kCGImageAlphaNone; break;
		case VDEPTH_8BIT:	bpc = 8; bpp = 8; options = kCGImageAlphaNone; break;
		case VDEPTH_16BIT:	bpc = 5; bpp = 16; options = kCGBitmapByteOrder16Little | kCGImageAlphaNoneSkipFirst; break;
		case VDEPTH_32BIT:	bpc = 8; bpp = 32; options = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst; break;
	}
    
	CGImageRef imageRef = CGImageCreate(x, y, bpc, bpp, bpr, colorSpace,
							 options,
							 provider,
							 NULL, 	// colorMap translation table
							 NO,	// shouldInterpolate colors?
							 kCGRenderingIntentDefault);
	if (imageRef == NULL)
	{
		ErrorAlert("Could not create CGImage from CGDataProvider");
		return false;
	}
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [sharedScreenView updateImage:imageRef];
        CGImageRelease(imageRef);
    });
    
    
    return true;
}

void IOS_monitor::video_close()
{
	D(bug("video_close()\n"));
    
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    free(the_buffer);
    colorSpace = nil;
    provider = nil;
    the_buffer = NULL;
}

// Set Mac frame layout and base address (uses the_buffer/MacFrameBaseMac)
void IOS_monitor::set_mac_frame_buffer(const video_mode mode)
{
#if !REAL_ADDRESSING && !DIRECT_ADDRESSING
	switch ( mode.depth )
	{
            //	case VDEPTH_15BIT:
		case VDEPTH_16BIT: MacFrameLayout = FLAYOUT_HOST_555; break;
            //	case VDEPTH_24BIT:
		case VDEPTH_32BIT: MacFrameLayout = FLAYOUT_HOST_888; break;
		default			 : MacFrameLayout = FLAYOUT_DIRECT;
	}
	set_mac_frame_base(MacFrameBaseMac);
    
	// Set variables used by UAE memory banking
	MacFrameBaseHost = (uint8 *) the_buffer;
	MacFrameSize = mode.bytes_per_row * mode.y;
	InitFrameBufferMapping();
#else
	set_mac_frame_base((unsigned int)Host2MacAddr((uint8 *)the_buffer));
#endif
	D(bug("mac_frame_base = %08x\n", get_mac_frame_base()));
}

void IOS_monitor::set_palette(uint8 *pal, int num)
{
	// To change the palette, we have to regenerate
	// the CGImageRef with the new color space.
    
	CGColorSpaceRef oldColorSpace = CGColorSpaceRetain(colorSpace);
    
	colorSpace = CGColorSpaceCreateDeviceRGB();
    
	if ( bpp < 16 )
	{
		CGColorSpaceRef		tempColorSpace = colorSpace;
        
		colorSpace = CGColorSpaceCreateIndexed(colorSpace, 255, pal);
		CGColorSpaceRelease(tempColorSpace);
	}
    
	if ( ! colorSpace )
	{
		ErrorAlert("No valid color space");
		return;
	}
    
	CGColorSpaceRelease(oldColorSpace);
    
    update_image();
}


void IOS_monitor::switch_to_current_mode(void)
{
	video_mode mode = get_current_mode();
    
	D(bug("switch_to_current_mode(): width=%d  height=%d  depth=%d  bytes_per_row=%d\n", mode.x, mode.y, bits_from_depth(mode.depth), mode.bytes_per_row));
	
    sharedScreenView.screenSize = CGSizeMake(mode.x, mode.y);
    
    CGColorSpaceRef		oldColorSpace	= colorSpace;
    CGDataProviderRef	oldProvider		= provider;
    void				*oldBuffer		= the_buffer;
    
    if (video_open(mode))
    {
        CGColorSpaceRelease(oldColorSpace);
        CGDataProviderRelease(oldProvider);
        free(oldBuffer);
        set_mac_frame_buffer(mode);
    }
    else
    {
        NSLog(@"Could not open video mode");
    }
    
    update_image();
}

static IOS_monitor *mainMonitor;
static int32 frame_skip;

bool VideoInit(bool classic)
{
    frame_skip = PrefsFindInt32("frameskip");
    add_standard_modes(VDEPTH_1BIT);
    add_standard_modes(VDEPTH_2BIT);
    add_standard_modes(VDEPTH_4BIT);
    add_standard_modes(VDEPTH_8BIT);
    add_standard_modes(VDEPTH_16BIT);
    add_standard_modes(VDEPTH_32BIT);

    video_mode init_mode = VideoModes[0];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    video_depth init_depth = DepthModeForPixelDepth([defaults integerForKey:@"videoDepth"]);
    CGSize init_size = CGSizeFromString([defaults stringForKey:@"videoSize"]);
    if (VideoModes.size() > 0)
	{
		std::vector<video_mode>::const_iterator i, end = VideoModes.end();
		for (i = VideoModes.begin(); i != end; ++i)
		{
            if (i->depth == init_depth && i->x == (uint32)init_size.width && i->y == (uint32)init_size.height)
            {
                init_mode = *i;
                break;
            }
		}
	}
    
    mainMonitor = new IOS_monitor(VideoModes, init_mode.depth, init_mode.resolution_id);
    if (mainMonitor->video_open(init_mode))
    {
        mainMonitor->set_mac_frame_buffer(init_mode);
        VideoMonitors.push_back(mainMonitor);
    }
    
    return true;
}

void VideoInterrupt(void)
{
    static int tick_counter = 0;
    if (++tick_counter >= frame_skip) {
        mainMonitor->update_image();
        tick_counter = 0;
    }
}

void VideoExit(void)
{
}

void VideoQuitFullScreen(void)
{
}
