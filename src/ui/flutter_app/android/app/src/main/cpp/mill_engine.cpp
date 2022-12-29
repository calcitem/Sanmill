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
#include <iostream>
#include <string.h>
#include <sys/types.h>
#include <thread>
#include <unistd.h>

extern "C" {

EngineState state = EngineState::STATE_READY;
std::thread thread;

void engineThread()
{
    std::cout << "Engine Think Thread enter." << std::endl;

    engineMain();

    std::cout << "Engine Think Thread exit." << std::endl;
}

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_send(
    JNIEnv *env, jobject, jstring command);

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_shutdown(JNIEnv *,
                                                                     jobject);

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_startup(JNIEnv *env,
                                                                    jobject obj)
{
    if (thread.joinable()) {
        Java_com_calcitem_sanmill_MillEngine_shutdown(env, obj);
        if (thread.joinable()) {
            thread.join();
        }
    }

    CommandChannel::getInstance();

    std::this_thread::sleep_for(std::chrono::milliseconds(10));

    thread = std::thread(engineThread);

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
        std::cout << ">>> " << command << std::endl;

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

    std::cout << "<<< " << line << std::endl;

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

    if (thread.joinable()) {
        thread.join();
    }

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
