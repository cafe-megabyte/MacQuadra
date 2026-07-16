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
#include <algorithm>
#include <vector>
#include "prefs.h"
#include "main.h"
#include "audio.h"
#include "audio_defs.h"
#include "audio_ios_impl.h"

#undef DEBUG
#undef DEBUG
#define DEBUG 0
#include "debug.h"


// The currently selected audio parameters (indices in
// audio_sample_rates[] etc. vectors)
static int audio_sample_rate_index = 0;
static int audio_sample_size_index = 0;
static int audio_channel_count_index = 0;

static bool main_mute = false;
static bool speaker_mute = false;

static uint16 read_be16(const uint8 *p)
{
	return (uint16)((p[0] << 8) | p[1]);
}

static uint32 read_be32(const uint8 *p)
{
	return ((uint32)p[0] << 24) | ((uint32)p[1] << 16) | ((uint32)p[2] << 8) | p[3];
}

static void append_be_int16(std::vector<uint8> &out, int16 value)
{
	out.push_back((uint8)((value >> 8) & 0xff));
	out.push_back((uint8)(value & 0xff));
}

static int16 clamp_to_int16(int32 value)
{
	if (value > INT16_MAX) return INT16_MAX;
	if (value < INT16_MIN) return INT16_MIN;
	return (int16)value;
}

static void append_resampled_pcm16(const std::vector<int16> &source, uint32 sourceRate, std::vector<uint8> &out)
{
	const uint32 outputRate = AudioStatus.sample_rate >> 16;
	const uint32 outputChannels = AudioStatus.channels;
	if (source.empty() || sourceRate == 0 || outputRate == 0 || outputChannels == 0)
		return;

	const uint32 outputSamples = std::max<uint32>(1, (uint32)(((uint64)source.size() * outputRate) / sourceRate));
	out.clear();
	out.reserve((size_t)outputSamples * outputChannels * sizeof(int16));

	for (uint32 i = 0; i < outputSamples; i++) {
		const uint32 sourceIndex = std::min<uint32>((uint32)(((uint64)i * sourceRate) / outputRate), (uint32)source.size() - 1);
		const int16 sample = source[sourceIndex];
		for (uint32 channel = 0; channel < outputChannels; channel++)
			append_be_int16(out, sample);
	}
}

static const uint8 *find_easc_startup_sound_header(uint32 *soundSize)
{
	static const uint8 soundResourcePrefix[] = {
		0x00, 0x01, 0x00, 0x01,
		0x00, 0x05,
		0x00, 0x00, 0x00, 0x80,
		0x00, 0x01,
		0x80, 0x51,
		0x00, 0x00,
		0x00, 0x00, 0x00, 0x14
	};

	const uint8 *normalStartupSound = NULL;
	uint32 normalStartupSoundSize = 0;
	uint32 compressedSoundCount = 0;

	for (uint32 offset = 0; offset + sizeof(soundResourcePrefix) + 0x54 < ROMSize; offset++) {
		if (memcmp(ROMBaseHost + offset, soundResourcePrefix, sizeof(soundResourcePrefix)) != 0)
			continue;

		const uint8 *header = ROMBaseHost + offset + 0x14;
		if (header[20] != 0xfe || read_be16(header + 56) != 6 || read_be16(header + 58) != 120 || read_be16(header + 62) != 16)
			continue;

		const uint32 packetCount = read_be32(header + 22);
		const uint32 dataSize = packetCount * 15;
		if (packetCount == 0 || header + 64 + dataSize > ROMBaseHost + ROMSize)
			continue;

		compressedSoundCount++;
		normalStartupSound = header;
		normalStartupSoundSize = dataSize;
		if (compressedSoundCount == 2)
			break;
	}

	if (soundSize != NULL)
		*soundSize = normalStartupSoundSize;
	return normalStartupSound;
}

static int8 sign_extend_nibble(uint8 nibble)
{
	return (nibble & 0x08) ? (int8)(nibble | 0xf0) : (int8)nibble;
}

static void decode_easc_sample(int type, int32 raster, int32 &envelope, int32 &delta, std::vector<int16> &samples)
{
	switch (type) {
		case 0x00:
			envelope = raster;
			delta = 0;
			break;

		case 0x10:
			delta = -raster;
			envelope -= delta;
			samples.push_back(clamp_to_int16(envelope));
			envelope -= envelope / 16;
			return;

		case 0x20:
			delta -= raster;
			envelope -= delta;
			delta -= delta / 8;
			samples.push_back(clamp_to_int16(envelope));
			envelope -= envelope / 8;
			return;

		case 0x30:
			delta -= raster;
			delta += (envelope * 3) / 8;
			envelope = (envelope - delta) - (envelope - delta) / 8;
			break;

		default:
			return;
	}

	samples.push_back(clamp_to_int16(envelope));
}

static bool decode_easc_compressed_sound(const uint8 *header, uint32 dataSize, std::vector<uint8> &out)
{
	if (header == NULL || dataSize < 15 || dataSize % 15 != 0)
		return false;

	const uint32 sampleRate = read_be32(header + 8) >> 16;
	const uint8 *packet = header + 64;
	const uint8 *packetEnd = packet + dataSize;
	std::vector<int16> sourceSamples;
	sourceSamples.reserve((dataSize / 15) * 28);

	int32 envelope = 0;
	int32 delta = 0;
	while (packet < packetEnd) {
		const int type = packet[0] & 0x30;
		const int scale = packet[0] & 0x0f;
		if (scale > 14)
			return false;

		for (int i = 1; i < 15; i++) {
			const int8 nibble1 = sign_extend_nibble(packet[i] & 0x0f);
			const int8 nibble2 = sign_extend_nibble((packet[i] >> 4) & 0x0f);
			const int32 raster1 = ((int32)nibble1 * 4096) / (1 << scale);
			const int32 raster2 = ((int32)nibble2 * 4096) / (1 << scale);
			decode_easc_sample(type, raster1, envelope, delta, sourceSamples);
			decode_easc_sample(type, raster2, envelope, delta, sourceSamples);
		}

		packet += 15;
	}

	append_resampled_pcm16(sourceSamples, sampleRate, out);
	return !out.empty();
}

void audio_play_rom_startup_sound(void)
{
	if (!audio_open || AudioStatus.sample_size == 0 || AudioStatus.channels == 0)
		return;

	uint32 eascDataSize = 0;
	const uint8 *eascHeader = find_easc_startup_sound_header(&eascDataSize);
	std::vector<uint8> pcm;
	if (decode_easc_compressed_sound(eascHeader, eascDataSize, pcm))
		audio_play_startup_sound(pcm.data(), (int)(pcm.size() / ((AudioStatus.sample_size / 8) * AudioStatus.channels)));
}


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
	audio_sample_rate_index   = static_cast<int>(audio_sample_rates.size() - 1);
	audio_sample_size_index   = static_cast<int>(audio_sample_sizes.size() - 1);
	audio_channel_count_index = static_cast<int>(audio_channel_counts.size() - 1);
    
	AudioStatus.mixer = 0;
	AudioStatus.num_sources = 0;
	audio_component_flags = cmpWantsRegisterMessage | kStereoOut | k16BitOut;
	audio_component_flags = 0;
    
    AudioStatus.sample_rate = audio_sample_rates[audio_sample_rate_index];
	AudioStatus.sample_size = audio_sample_sizes[audio_sample_size_index];
	AudioStatus.channels = audio_channel_counts[audio_channel_count_index];
	audio_frames_per_block = 4096;
    
	open_audio(AudioStatus.sample_rate >> 16, AudioStatus.sample_size, AudioStatus.channels);
	audio_play_rom_startup_sound();
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
