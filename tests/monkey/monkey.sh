#!/bin/bash

PLATFORM_TOOLS=~/AppData/Local/Android/Sdk/platform-tools

if [ "$(uname)" == "Darwin" ]; then
    PLATFORM_TOOLS=~/Library/Android/sdk/platform-tools
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    PLATFORM_TOOLS=~/Android/sdk/platform-tools
fi

cd ${PLATFORM_TOOLS} || exit
./adb shell monkey -v -p com.calcitem.sanmill --pct-touch 50 --pct-motion 50 --pct-trackball 0 --pct-nav 0 --pct-majornav 0 --pct-syskeys 0 --pct-anyevent 0 --throttle 500 10000000
