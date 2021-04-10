#!/bin/bash

"${ANDROID_NDK_HOME}/ndk-stack.cmd" -sym "../build/app/intermediates/cmake/debug/obj/arm64-v8a" -dump bt.txt
"${ANDROID_NDK_HOME}/ndk-stack.cmd" -sym "../build/app/intermediates/cmake/debug/obj/armeabi-v7a" -dump bt.txt
