#!/bin/bash

cd ~/AppData/Local/Android/Sdk/platform-tools || exit
./adb shell kill $(./adb shell ps | grep monkey | xargs | cut -d' ' -f2)
