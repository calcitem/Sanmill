#!/bin/bash

mv src/ui/flutter_app/android/key.jks ../
mv src/ui/flutter_app/android/key.properties ../

git clean -fdx

mv ../key.jks src/ui/flutter_app/android/
mv ../key.properties src/ui/flutter_app/android/

./flutter-init.sh