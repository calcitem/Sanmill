#!/bin/bash

ENV_FILE_PATH=assets/files
ENV_FILE=$ENV_FILE_PATH/environment_variables.txt

cd src/ui/flutter_app || exit

mkdir -p $ENV_FILE_PATH || true
touch $ENV_FILE
export > $ENV_FILE

flutter pub get
flutter pub global activate intl_utils
flutter --no-color pub global run intl_utils:generate
flutter create --platforms=windows .
