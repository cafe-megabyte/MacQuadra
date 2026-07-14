//
//  audio_ios_impl.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 14/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

int audioInt(void);
bool open_audio(int sampleRate, int sampleSize, int channels);
void close_audio(void);
void audio_output(void *p, int numSamples);