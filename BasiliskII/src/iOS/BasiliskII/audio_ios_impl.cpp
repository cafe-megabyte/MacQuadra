//
//  audio_ios_impl.cpp
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 14/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#include <os/lock.h>
#include <algorithm>
#include <cstdint>
#include <vector>
#include "audio_ios_impl.h"

extern bool audio_open;					// Flag: audio is open and ready
extern int audio_frames_per_block;		// Number of audio frames per block

#define NUM_BUFFERS 2

static int curFillBuffer = 0;
static int curReadBuffer = 0;
static int numFullBuffers = 0;
static int sndBufferSize;
static char *sndBuffer[NUM_BUFFERS];
static int sndBufferUsed[NUM_BUFFERS];
static AudioQueueBufferRef aqBuffer[NUM_BUFFERS];
static AudioQueueRef audioQueue;
static AudioStreamBasicDescription outputFormat;
static os_unfair_lock audioBufferLock = OS_UNFAIR_LOCK_INIT;
static std::vector<uint8_t> startupSoundBuffer;
static size_t startupSoundOffset = 0;

static int16_t read_be_int16(const uint8_t *p)
{
    return (int16_t)((p[0] << 8) | p[1]);
}

static void write_be_int16(uint8_t *p, int16_t value)
{
    p[0] = (uint8_t)((value >> 8) & 0xff);
    p[1] = (uint8_t)(value & 0xff);
}

static int16_t clamp_sample(int value)
{
    if (value > INT16_MAX) return INT16_MAX;
    if (value < INT16_MIN) return INT16_MIN;
    return (int16_t)value;
}

static void mix_startup_sound(AudioQueueBufferRef mBuffer)
{
    if (startupSoundOffset >= startupSoundBuffer.size()) return;

    uint8_t *out = (uint8_t *)mBuffer->mAudioData;
    const size_t outputBytes = mBuffer->mAudioDataByteSize;
    const size_t bytesToMix = std::min(outputBytes, startupSoundBuffer.size() - startupSoundOffset);

    for (size_t offset = 0; offset + 1 < bytesToMix; offset += 2) {
        const int mixed = read_be_int16(out + offset) + read_be_int16(&startupSoundBuffer[startupSoundOffset + offset]);
        write_be_int16(out + offset, clamp_sample(mixed));
    }

    startupSoundOffset += bytesToMix;
    if (startupSoundOffset >= startupSoundBuffer.size()) {
        startupSoundBuffer.clear();
        startupSoundOffset = 0;
    }
}

void audio_callback (void *data, AudioQueueRef mQueue, AudioQueueBufferRef mBuffer)
{
    os_unfair_lock_lock(&audioBufferLock);
    mBuffer->mAudioDataByteSize = sndBufferSize;
    if (numFullBuffers == 0) {
        bzero(mBuffer->mAudioData, sndBufferSize);
    } else {
        memcpy(mBuffer->mAudioData, sndBuffer[curReadBuffer], sndBufferSize);
        numFullBuffers--;
        curReadBuffer = curReadBuffer ? 0 : 1;
    }
    mix_startup_sound(mBuffer);
    os_unfair_lock_unlock(&audioBufferLock);
    AudioQueueEnqueueBuffer(mQueue, mBuffer, 0, NULL);
    audioInt();
}

void close_audio(void)
{
    if (audioQueue == NULL) return;
    AudioQueueStop(audioQueue, true);
    
    for (int i=0; i<NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(audioQueue, aqBuffer[i]);
        free(sndBuffer[i]);
    }
    
    AudioQueueFlush(audioQueue);
    AudioQueueDispose(audioQueue, true);
    audioQueue = NULL;
    startupSoundBuffer.clear();
    startupSoundOffset = 0;
    audio_open = false;
}

bool open_audio(int sampleRate, int sampleSize, int channels)
{
    close_audio();
	
    curReadBuffer = curFillBuffer = numFullBuffers = 0;
    
    // create queue
    outputFormat.mSampleRate = sampleRate;
    outputFormat.mFormatID = kAudioFormatLinearPCM;
    outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger |
    kAudioFormatFlagIsBigEndian |
    kAudioFormatFlagIsPacked;
    outputFormat.mChannelsPerFrame = channels;
    outputFormat.mBitsPerChannel = sampleSize;
    outputFormat.mFramesPerPacket = 1;
    outputFormat.mBytesPerFrame = (outputFormat.mBitsPerChannel / 8) * outputFormat.mChannelsPerFrame;
    outputFormat.mBytesPerPacket = outputFormat.mBytesPerFrame * outputFormat.mFramesPerPacket;
    outputFormat.mReserved = 0;
    OSStatus err = AudioQueueNewOutput(&outputFormat, audio_callback, NULL, CFRunLoopGetMain(), kCFRunLoopCommonModes, 0, &audioQueue);
    if (err != noErr) return false;
    
    // create buffers
    sndBufferSize = outputFormat.mBytesPerFrame * audio_frames_per_block;
    for (int i=0; i<NUM_BUFFERS; i++) {
        AudioQueueAllocateBuffer(audioQueue, sndBufferSize, &aqBuffer[i]);
        audio_callback(NULL, audioQueue, aqBuffer[i]);
        sndBuffer[i] = (char*)malloc(sndBufferSize);
    }
    
    err = AudioQueueStart(audioQueue, NULL);
    if (err != noErr) return false;
    audio_open = true;
	return true;
}

void audio_output(void *p, int numSamples)
{
    if (numFullBuffers == NUM_BUFFERS || p == NULL) return;
    os_unfair_lock_lock(&audioBufferLock);
    sndBufferUsed[curFillBuffer] = outputFormat.mBytesPerFrame * numSamples;
    memcpy(sndBuffer[curFillBuffer], p, sndBufferUsed[curFillBuffer]);
    int remain = sndBufferSize - sndBufferUsed[curFillBuffer];
    bzero(sndBuffer[curFillBuffer]+sndBufferSize-remain, remain);
    curFillBuffer = curFillBuffer ? 0 : 1;
    numFullBuffers++;
    os_unfair_lock_unlock(&audioBufferLock);
}

void audio_play_startup_sound(const void *p, int numSamples)
{
    if (p == NULL || numSamples <= 0) return;

    os_unfair_lock_lock(&audioBufferLock);
    const size_t byteCount = (size_t)outputFormat.mBytesPerFrame * (size_t)numSamples;
    const uint8_t *bytes = (const uint8_t *)p;
    startupSoundBuffer.assign(bytes, bytes + byteCount);
    startupSoundOffset = 0;
    os_unfair_lock_unlock(&audioBufferLock);
}
