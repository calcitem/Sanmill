#!/bin/bash

mv src/ui/flutter_app/android/key.jks ../
mv src/ui/flutter_app/android/key.properties ../

git clean -fdx

mv ../key.jks src/ui/flutter_app/android/
mv ../key.properties src/ui/flutter_app/android/

if [ "$(uname)" == "Darwin" ]; then
    echo "TODO: macOS"
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    echo "TODO: Linux"
else
    ./flutter-windows-init.sh
fi
