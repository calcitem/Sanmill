#!/bin/bash

NDK_STACK=ndk-stack.cmd

if [ "$(uname)" == "Darwin" ]; then
    NDK_STACK=ndk-stack
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    NDK_STACK=ndk-stack
fi

"${ANDROID_NDK_HOME}/${NDK_STACK}" -sym "../build/app/intermediates/cmake/debug/obj/arm64-v8a" -dump bt.txt
"${ANDROID_NDK_HOME}/${NDK_STACK}" -sym "../build/app/intermediates/cmake/debug/obj/armeabi-v7a" -dump bt.txt
