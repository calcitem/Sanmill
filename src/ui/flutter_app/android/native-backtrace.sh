#!/bin/bash

NDK_STACK=ndk-stack.cmd

if [ "$(uname)" == "Darwin" ]; then
    NDK_STACK=ndk-stack
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    NDK_STACK=ndk-stack
fi

"${ANDROID_NDK_HOME}/${NDK_STACK}" -sym "../build/app/intermediates/merged_native_libs/debug/mergeDebugNativeLibs/out/lib/arm64-v8a" -dump bt.txt
"${ANDROID_NDK_HOME}/${NDK_STACK}" -sym "../build/app/intermediates/merged_native_libs/debug/mergeDebugNativeLibs/out/lib/armeabi-v7a" -dump bt.txt
