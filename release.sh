#!/bin/bash

YAML_FILE=src/ui/flutter_app/pubspec.yaml
QT_RC_FILE=millgame.rc
FLUTTER_WINDOWS_RC_FILE=src/ui/flutter_app/windows/runner/Runner.rc
EN_CHANGLOG_DIR=fastlane/metadata/android/en-US/changelogs
DE_CHANGLOG_DIR=fastlane/metadata/android/de-DE/changelogs
DE_CHANGLOG_DIR=fastlane/metadata/android/es-ES/changelogs
ZH_CHANGLOG_DIR=fastlane/metadata/android/zh-CN/changelogs

# Update Build Number
./version.sh

# version: 1.0.6+1811
VERSION_STRING=`sed -n '4p' $YAML_FILE`
echo "VERSION_STRING = $VERSION_STRING"

# 1.0.6+1811
FULL_VERSION=`echo $VERSION_STRING | cut -d ' ' -f 2`
echo "FULL_VERSION = $FULL_VERSION"

# 1.0.6
VERSION=`echo $FULL_VERSION | cut -d "+" -f 1`
echo "VERSION = $VERSION"
OLD_VERSION=$VERSION
echo "OLD_VERSION = $OLD_VERSION"

# 6
MAJOR_NUMBER=`echo $VERSION | cut -d "." -f 1`
MINOR_NUMBER=`echo $VERSION | cut -d "." -f 2`
PATCH_NUMBER=`echo $VERSION | cut -d "." -f 3`
echo "MAJOR_NUMBER = $MAJOR_NUMBER"
echo "MINOR_NUMBER = $MINOR_NUMBER"
echo "PATCH_NUMBER = $PATCH_NUMBER"

OLD_PATCH_NUMBER=$PATCH_NUMBER
echo "OLD_PATCH_NUMBER = $OLD_PATCH_NUMBER"

# 7
let "PATCH_NUMBER+=1"
echo "PATCH_NUMBER = $PATCH_NUMBER"

# 1.0.7
NEW_VERSION="${MAJOR_NUMBER}.${MINOR_NUMBER}.${PATCH_NUMBER}"
echo "NEW_VERSION = $NEW_VERSION"

# 1811
BUILD_NUMBER=`echo $FULL_VERSION | cut -d "+" -f 2`
echo "BUILD_NUMBER = $BUILD_NUMBER"

# 1.0.7+1811
NEW_FULL_VERSION="$NEW_VERSION+$BUILD_NUMBER"
echo "NEW_FULL_VERSION = $NEW_FULL_VERSION"

# version: 1.0.7+1811
NEW_VERSION_STRING="version: $NEW_FULL_VERSION"
echo "NEW_VERSION_STRING = $NEW_VERSION_STRING"

# Modify yaml
sed -i "s/${VERSION_STRING}/${NEW_VERSION_STRING}/g" $YAML_FILE

# Modify Qt
OLD_FILEVERSION="$MAJOR_NUMBER,$MINOR_NUMBER,$OLD_PATCH_NUMBER"
FILEVERSION="$MAJOR_NUMBER,$MINOR_NUMBER,$PATCH_NUMBER"
sed -i "s/${OLD_FILEVERSION}/${FILEVERSION}/g" $QT_RC_FILE
sed -i "s/${OLD_VERSION}/${NEW_VERSION}/g" $QT_RC_FILE

# Modify Runner.rc
sed -i "s/${OLD_FILEVERSION}/${FILEVERSION}/g" $FLUTTER_WINDOWS_RC_FILE
sed -i "s/${OLD_VERSION}/${NEW_VERSION}/g" $FLUTTER_WINDOWS_RC_FILE

# Changelog
rm -f ${BUILD_NUMBER}.txt
touch ${BUILD_NUMBER}.txt

echo "v$NEW_VERSION" >> ${BUILD_NUMBER}.txt
echo >> ${BUILD_NUMBER}.txt

cp ${BUILD_NUMBER}.txt $EN_CHANGLOG_DIR
cp ${BUILD_NUMBER}.txt $DE_CHANGLOG_DIR
cp ${BUILD_NUMBER}.txt $ZH_CHANGLOG_DIR
rm -f ${BUILD_NUMBER}.txt

echo "* Release notes." >> $EN_CHANGLOG_DIR/${BUILD_NUMBER}.txt
echo "* Versionshinweise." >> $DE_CHANGLOG_DIR/${BUILD_NUMBER}.txt
echo "* 发布说明。" >> $ZH_CHANGLOG_DIR/${BUILD_NUMBER}.txt

notepad $EN_CHANGLOG_DIR/${BUILD_NUMBER}.txt
notepad $DE_CHANGLOG_DIR/${BUILD_NUMBER}.txt
notepad $ZH_CHANGLOG_DIR/${BUILD_NUMBER}.txt

# Git commit
git status -s
git add .
git commit -m "Sanmill v$NEW_VERSION (${BUILD_NUMBER})" -m "Official release version of Sanmill v$NEW_VERSION" -s
git tag -d v$NEW_VERSION || true
git tag v$NEW_VERSION
git push origin v$NEW_VERSION -f
git push origin master

