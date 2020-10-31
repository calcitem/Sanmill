//
//  command-engine.cpp
//  Runner
//

#include <jni.h>
#include <sys/types.h>
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "../../../../../command/engine-main.h"
#include "../../../../../command/engine-state.h"
#include "../../../../../command/command-channel.h"

extern "C" {

State state = Ready;
pthread_t thread_id = 0;

void *engineThread(void *) {

    printf("Engine Think Thread enter.\n");

    engineMain();

    printf("Engine Think Thread exit.\n");

    return NULL;
}

JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_send(JNIEnv *env, jobject, jstring command);

JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_shutdown(JNIEnv *, jobject);

JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_startup(JNIEnv *env, jobject obj) {

    if (thread_id) {
        Java_com_calcitem_sanmill_MillEngine_shutdown(env, obj);
        pthread_join(thread_id, NULL);
    }

    // getInstance() 有并发问题，这里首先主动建立实例，避免后续创建重复
    CommandChannel::getInstance();

    usleep(10);

    pthread_create(&thread_id, NULL, engineThread, NULL);

    Java_com_calcitem_sanmill_MillEngine_send(env, obj, env->NewStringUTF("uci"));

    return 0;
}

JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_send(JNIEnv *env, jobject, jstring command) {

    const char *pCommand = env->GetStringUTFChars(command, JNI_FALSE);

    if (pCommand[0] == 'g' && pCommand[1] == 'o') state = Thinking;

    CommandChannel *channel = CommandChannel::getInstance();

    bool success = channel->pushCommand(pCommand);
    if (success) printf(">>> %s\n", pCommand);

    env->ReleaseStringUTFChars(command, pCommand);


    return success ? 0 : -1;
}

JNIEXPORT jstring JNICALL
Java_com_calcitem_sanmill_MillEngine_read(JNIEnv *env, jobject) {

    char line[4096] = {0};

    CommandChannel *channel = CommandChannel::getInstance();
    bool got_response = channel->popupResponse(line);

    if (!got_response) return NULL;

    printf("<<< %s\n", line);

    if (strstr(line, "readyok") ||
        strstr(line, "uciok") ||
        strstr(line, "bestmove") ||
        strstr(line, "nobestmove")) {

        state = Ready;
    }

    return env->NewStringUTF(line);
}

JNIEXPORT jint JNICALL
Java_com_calcitem_sanmill_MillEngine_shutdown(JNIEnv *env, jobject obj) {

    Java_com_calcitem_sanmill_MillEngine_send(env, obj, env->NewStringUTF("quit"));

    pthread_join(thread_id, NULL);

    thread_id = 0;

    return 0;
}

JNIEXPORT jboolean JNICALL
Java_com_calcitem_sanmill_MillEngine_isReady(JNIEnv *, jobject) {
    return static_cast<jboolean>(state == Ready);
}

JNIEXPORT jboolean JNICALL
Java_com_calcitem_sanmill_MillEngine_isThinking(JNIEnv *, jobject) {
    return static_cast<jboolean>(state == Thinking);
}

}