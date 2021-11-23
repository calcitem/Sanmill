#!/bin/bash

PLATFORM_TOOLS=~/AppData/Local/Android/Sdk/platform-tools

if [ "$(uname)" == "Darwin" ]; then
    PLATFORM_TOOLS=~/Library/Android/sdk/platform-tools
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    PLATFORM_TOOLS=~/Android/sdk/platform-tools
fi

cd ${PLATFORM_TOOLS} || exit

./adb shell kill $(./adb shell ps | grep monkey | xargs | cut -d' ' -f2)
