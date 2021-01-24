#!/bin/bash

cd src/ui/flutter
flutter pub get
flutter pub global activate intl_utils
flutter --no-color pub global run intl_utils:generate
