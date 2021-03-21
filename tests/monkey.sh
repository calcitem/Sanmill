#!/bin/bash

cd ~/AppData/Local/Android/Sdk/platform-tools || exit
./adb shell monkey -v -p com.calcitem.sanmill --pct-touch 100 --pct-trackball 0 --pct-nav 0 --pct-majornav 0 --pct-syskeys 0 --pct-anyevent 0 --throttle 100 10000000
