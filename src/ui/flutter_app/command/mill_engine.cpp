// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_engine.cpp

#include <iostream>
#include <string.h>
#include <string>
#include <thread>

#include "mill_engine.h"

#include "command_channel.h"
#include "engine_main.h"
#include "engine_state.h"

#ifdef __ANDROID__
#include <jni.h>
#endif // __ANDROID__

extern "C" {

EngineState state = ENGINE_STATE_READY;
std::thread thread;

void engineThread()
{
    std::cout << "Engine Think Thread enter." << std::endl;

    engineMain();

    std::cout << "Engine Think Thread exit." << std::endl;
}

#ifdef __ANDROID__
JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_send(
    JNIEnv *env, jobject, jstring command);

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_shutdown(JNIEnv *,
                                                                     jobject);

JNIEXPORT jint JNICALL Java_com_calcitem_sanmill_MillEngine_startup(JNIEnv *env,
                                                                    jobject obj)
#else
int MillEngine::startup()
#endif // __ANDROID__
{
    if (thread.joinable()) {
#ifdef __ANDROID__
        Java_com_calcitem_sanmill_MillEngine_shutdown(env, obj);
#else
        shutdown();
#endif // __ANDROID__
        if (thread.joinable()) {
            thread.join();
        }
    }

    CommandChannel::getInstance();

    std::this_thread::sleep_for(std::chrono::milliseconds(10));

    thread = std::thread(engineThread);

#ifdef __ANDROID__
    Java_com_calcitem_sanmill_MillEngine_send(env, obj,
                                              env->NewStringUTF("uci"));
#else
    send("uci");
#endif // __ANDROID__

    return 0;
}

#ifdef __ANDROID__
JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_send(JNIEnv *env, jobject, jstring command)
{
    const char *pCommand = env->GetStringUTFChars(command, JNI_FALSE);

    CommandChannel *channel = CommandChannel::getInstance();

    bool success = channel->pushCommand(pCommand);
    if (success) {
        std::cout << ">>> " << command << std::endl;

        if (pCommand[0] == 'g' && pCommand[1] == 'o')
            state = ENGINE_STATE_THINKING;
    }

    env->ReleaseStringUTFChars(command, pCommand);

    return success ? 0 : -1;
}
#else
int MillEngine::send(const char *command)
{
    CommandChannel *channel = CommandChannel::getInstance();

    bool success = channel->pushCommand(command);
    if (success) {
        std::cout << ">>> " << command << std::endl;

        if (command[0] == 'g' && command[1] == 'o') {
            state = ENGINE_STATE_THINKING;
        }
    }

    return success ? 0 : -1;
}
#endif // __ANDROID__

#ifdef __ANDROID__
JNIEXPORT jstring JNICALL Java_com_calcitem_sanmill_MillEngine_read(JNIEnv *env,
                                                                    jobject)
#else
std::string MillEngine::read()
#endif // __ANDROID__
{
    char line[4096] = {0};

    CommandChannel *channel = CommandChannel::getInstance();
    bool got_response = channel->popupResponse(line);

    if (!got_response) {
#ifdef __ANDROID__
        return NULL;
#else
        return "";
#endif // __ANDROID__
    }

    std::cout << "<<< " << line << std::endl;

    if (strstr(line, "readyok") || strstr(line, "uciok") ||
        strstr(line, "bestmove") || strstr(line, "nobestmove")) {
        state = ENGINE_STATE_READY;
    }

#ifdef __ANDROID__
    return env->NewStringUTF(line);
#else
    return line; // TODO
#endif // __ANDROID__
}

#ifdef __ANDROID__
JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_shutdown(JNIEnv *env, jobject obj)
#else
int MillEngine::shutdown()
#endif // __ANDROID__
{
#ifdef __ANDROID__
    Java_com_calcitem_sanmill_MillEngine_send(env, obj,
                                              env->NewStringUTF("quit"));
#else
    send("quit");
#endif // __ANDROID__

    if (thread.joinable()) {
        thread.join();
    }

    return 0;
}

#ifdef __ANDROID__
JNIEXPORT jboolean JNICALL
Java_com_calcitem_sanmill_MillEngine_isReady(JNIEnv *, jobject)
{
    return static_cast<jboolean>(state == ENGINE_STATE_READY);
}

JNIEXPORT jboolean JNICALL
Java_com_calcitem_sanmill_MillEngine_isThinking(JNIEnv *, jobject)
{
    return static_cast<jboolean>(state == ENGINE_STATE_THINKING);
}

#else

bool MillEngine::isReady()
{
    return state == ENGINE_STATE_READY;
}

bool MillEngine::isThinking()
{
    return state == ENGINE_STATE_THINKING;
}
#endif // __ANDROID__
}
