// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include "../../../../../command/command_channel.h"
#include "../../../../../command/engine_main.h"
#include "../../../../../command/engine_state.h"
#include <jni.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

extern "C" {

EngineState state = EngineState::STATE_READY;
pthread_t thread_id = 0;

void *engineThread(void *)
{
    printf("Engine Think Thread enter.\n");

    engineMain();

    printf("Engine Think Thread exit.\n");

    return NULL;
}

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_send(
    JNIEnv *env, jobject, jstring command);

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_shutdown(JNIEnv *,
                                                                     jobject);

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_startup(JNIEnv *env,
                                                                    jobject obj)
{
    if (thread_id) {
        Java_com_calcitem_sanmill_MillEngine_shutdown(env, obj);
        pthread_join(thread_id, NULL);
    }

    CommandChannel::getInstance();

    usleep(10);

    pthread_create(&thread_id, NULL, engineThread, NULL);

    Java_com_calcitem_sanmill_MillEngine_send(env, obj,
                                              env->NewStringUTF("uci"));

    return 0;
}

JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_send(JNIEnv *env, jobject, jstring command)
{
    const char *pCommand = env->GetStringUTFChars(command, JNI_FALSE);

    if (pCommand[0] == 'g' && pCommand[1] == 'o')
        state = EngineState::STATE_THINKING;

    CommandChannel *channel = CommandChannel::getInstance();

    bool success = channel->pushCommand(pCommand);
    if (success)
        printf(">>> %s\n", pCommand);

    env->ReleaseStringUTFChars(command, pCommand);

    return success ? 0 : -1;
}

JNIEXPORT jstring JNICALL Java_com_calcitem_sanmill_MillEngine_read(JNIEnv *env,
                                                                    jobject)
{
    char line[4096] = {0};

    CommandChannel *channel = CommandChannel::getInstance();
    bool got_response = channel->popupResponse(line);

    if (!got_response)
        return NULL;

    printf("<<< %s\n", line);

    if (strstr(line, "readyok") || strstr(line, "uciok") ||
        strstr(line, "bestmove") || strstr(line, "nobestmove")) {
        state = EngineState::STATE_READY;
    }

    return env->NewStringUTF(line);
}

JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_shutdown(JNIEnv *env, jobject obj)
{
    Java_com_calcitem_sanmill_MillEngine_send(env, obj,
                                              env->NewStringUTF("quit"));

    pthread_join(thread_id, NULL);

    thread_id = 0;

    return 0;
}

JNIEXPORT jboolean JNICALL
Java_com_calcitem_sanmill_MillEngine_isReady(JNIEnv *, jobject)
{
    return static_cast<jboolean>(state == EngineState::STATE_READY);
}

JNIEXPORT jboolean JNICALL
Java_com_calcitem_sanmill_MillEngine_isThinking(JNIEnv *, jobject)
{
    return static_cast<jboolean>(state == EngineState::STATE_THINKING);
}
}
