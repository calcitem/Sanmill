#!/bin/bash

./flutter-init.sh

flutter config --enable-linux-desktop

cd src/ui/flutter_app
flutter create --platforms=linux .
