/*
 *  audio_dummy.cpp - Audio support, dummy implementation
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
#include "prefs.h"
#include "main.h"
#include "audio.h"
#include "audio_defs.h"
#include "audio_ios_impl.h"

#define DEBUG 0
#include "debug.h"


// The currently selected audio parameters (indices in
// audio_sample_rates[] etc. vectors)
static int audio_sample_rate_index = 0;
static int audio_sample_size_index = 0;
static int audio_channel_count_index = 0;

static bool main_mute = false;
static bool speaker_mute = false;


/*
 *  Initialization
 */

void AudioInit(void)
{
	// Sound disabled in prefs? Then do nothing
	if (PrefsFindBool("nosound"))
		return;
    
	//audio_sample_sizes.push_back(8);
	audio_sample_sizes.push_back(16);
    
	audio_channel_counts.push_back(1);
	audio_channel_counts.push_back(2);
	
	audio_sample_rates.push_back(11025 << 16);
	audio_sample_rates.push_back(22050 << 16);
	audio_sample_rates.push_back(44100 << 16);
    
	// Default to highest supported values
	audio_sample_rate_index   = audio_sample_rates.size() - 1;
	audio_sample_size_index   = audio_sample_sizes.size() - 1;
	audio_channel_count_index = audio_channel_counts.size() - 1;
    
	AudioStatus.mixer = 0;
	AudioStatus.num_sources = 0;
	audio_component_flags = cmpWantsRegisterMessage | kStereoOut | k16BitOut;
	audio_component_flags = 0;
    
    AudioStatus.sample_rate = audio_sample_rates[audio_sample_rate_index];
	AudioStatus.sample_size = audio_sample_sizes[audio_sample_size_index];
	AudioStatus.channels = audio_channel_counts[audio_channel_count_index];
    audio_frames_per_block = 4096;
    
	open_audio(AudioStatus.sample_rate >> 16, AudioStatus.sample_size, AudioStatus.channels);
}


/*
 *  Deinitialization
 */

void AudioExit(void)
{
	// Close audio device
	close_audio();
}


/*
 *  First source added, start audio stream
 */

void audio_enter_stream()
{
	// Streaming thread is always running to avoid clicking noises
}


/*
 *  Last source removed, stop audio stream
 */

void audio_exit_stream()
{
	// Streaming thread is always running to avoid clicking noises
}


/*
 *  MacOS audio interrupt, read next data block
 */

void AudioInterrupt(void)
{
	D(bug("AudioInterrupt\n"));
	uint32 apple_stream_info;
	uint32 numSamples;
	int16 *p = nullptr;
	M68kRegisters r;
    
	if (!AudioStatus.mixer) {
		audio_output(NULL, 0);
		D(bug("AudioInterrupt done\n"));
        
		return;
	}
    
	// Get data from apple mixer
	r.a[0] = audio_data + adatStreamInfo;
	r.a[1] = AudioStatus.mixer;
	Execute68k(audio_data + adatGetSourceData, &r);
	D(bug(" GetSourceData() returns %08lx\n", r.d[0]));
    
	apple_stream_info = ReadMacInt32(audio_data + adatStreamInfo);
	if (apple_stream_info && (main_mute == false) && (speaker_mute == false)) {
		numSamples = ReadMacInt32(apple_stream_info + scd_sampleCount);
		p = (int16 *)Mac2HostAddr(ReadMacInt32(apple_stream_info + scd_buffer));
	} else {
		numSamples = 0;
		p = NULL;
	}
    
    audio_output(p, numSamples);
	D(bug("AudioInterrupt done\n"));
}


/*
 *  Set sampling parameters
 *  "index" is an index into the audio_sample_rates[] etc. vectors
 *  It is guaranteed that AudioStatus.num_sources == 0
 */

bool audio_set_sample_rate(int index)
{
	close_audio();
	audio_sample_rate_index = index;
    AudioStatus.sample_rate = audio_sample_rates[audio_sample_rate_index];
	return open_audio(AudioStatus.sample_rate >> 16, AudioStatus.sample_size, AudioStatus.channels);
}

bool audio_set_sample_size(int index)
{
	close_audio();
	audio_sample_size_index = index;
    AudioStatus.sample_size = audio_sample_sizes[audio_sample_size_index];
	return open_audio(AudioStatus.sample_rate >> 16, AudioStatus.sample_size, AudioStatus.channels);
}

bool audio_set_channels(int index)
{
	close_audio();
	audio_channel_count_index = index;
	AudioStatus.channels = audio_channel_counts[audio_channel_count_index];
	return open_audio(AudioStatus.sample_rate >> 16, AudioStatus.sample_size, AudioStatus.channels);
}

/*
 *  Get/set volume controls (volume values received/returned have the
 *  left channel volume in the upper 16 bits and the right channel
 *  volume in the lower 16 bits; both volumes are 8.8 fixed point
 *  values with 0x0100 meaning "maximum volume"))
 */
bool audio_get_main_mute(void)
{
	return main_mute;
}

uint32 audio_get_main_volume(void)
{
	return 0x01000100;
}

bool audio_get_speaker_mute(void)
{
	return speaker_mute;
}

uint32 audio_get_speaker_volume(void)
{
	return 0x01000100;
}

void audio_set_main_mute(bool mute)
{
	main_mute = mute;
}

void audio_set_main_volume(uint32 vol)
{
    
}

void audio_set_speaker_mute(bool mute)
{
	speaker_mute = mute;
}

void audio_set_speaker_volume(uint32 vol)
{
    
}

int audioInt(void)
{
	SetInterruptFlag(INTFLAG_AUDIO);
	TriggerInterrupt();
	return 0;
}
