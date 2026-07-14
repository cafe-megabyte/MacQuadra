//
//  audio_ios_impl.cpp
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 14/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#include <libkern/OSAtomic.h>
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
static OSSpinLock audioBufferLock = OS_SPINLOCK_INIT;

void audio_callback (void *data, AudioQueueRef mQueue, AudioQueueBufferRef mBuffer)
{
    OSSpinLockLock(&audioBufferLock);
    mBuffer->mAudioDataByteSize = sndBufferSize;
    if (numFullBuffers == 0) {
        bzero(mBuffer->mAudioData, sndBufferSize);
    } else {
        memcpy(mBuffer->mAudioData, sndBuffer[curReadBuffer], sndBufferSize);
        numFullBuffers--;
        curReadBuffer = curReadBuffer ? 0 : 1;
    }
    OSSpinLockUnlock(&audioBufferLock);
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
    OSSpinLockLock(&audioBufferLock);
    sndBufferUsed[curFillBuffer] = outputFormat.mBytesPerFrame * numSamples;
    memcpy(sndBuffer[curFillBuffer], p, sndBufferUsed[curFillBuffer]);
    int remain = sndBufferSize - sndBufferUsed[curFillBuffer];
    bzero(sndBuffer[curFillBuffer]+sndBufferSize-remain, remain);
    curFillBuffer = curFillBuffer ? 0 : 1;
    numFullBuffers++;
    OSSpinLockUnlock(&audioBufferLock);
}
