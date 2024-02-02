#!/bin/bash

YAML_FILE=src/ui/flutter_app/pubspec.yaml
SNAP_YAML_FILE=snap/snapcraft.yaml
SNAP_DESKTOP_FILE=snap/gui/mill.desktop
DEBIAN_YAML_FILE=src/ui/flutter_app/debian/debian.yaml
DEBIAN_DESKTOP_FILE=rc/ui/flutter_app/debian/gui/mill.desktop
QT_RC_FILE=src/ui/qt/mill-pro.rc

EN_CHANGLOG_DIR=fastlane/metadata/android/en-US/changelogs
ZH_CHANGLOG_DIR=fastlane/metadata/android/zh-CN/changelogs

SED=sed
EDITOR=notepad

if [ "$(uname)" == "Darwin" ]; then
	SED=gsed
	EDITOR=vi
fi

if [ "$(uname)" == "Linux" ]; then
	SED=sed
	EDITOR=vi
fi

# Format source code
./format.sh

# Update Build Number
./version.sh

# version: 1.0.6+1811
VERSION_STRING=`$SED -n '4p' $YAML_FILE`
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

echo "Old:"
echo "MAJOR_NUMBER = $MAJOR_NUMBER"
echo "MINOR_NUMBER = $MINOR_NUMBER"
echo "PATCH_NUMBER = $PATCH_NUMBER"

OLD_PATCH_NUMBER=$PATCH_NUMBER
echo "OLD_PATCH_NUMBER = $OLD_PATCH_NUMBER"

# 7

if [ "$1" == "x" ]; then
  let "MAJOR_NUMBER+=1"
  MINOR_NUMBER=0
  PATCH_NUMBER=0
elif [ "$1" == "y" ]; then
  let "MINOR_NUMBER+=1"
  PATCH_NUMBER=0
else
  let "PATCH_NUMBER+=1"
fi

echo "New:"
echo "MAJOR_NUMBER = $MAJOR_NUMBER"
echo "MINOR_NUMBER = $MINOR_NUMBER"
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
$SED -i "s/${VERSION_STRING}/${NEW_VERSION_STRING}/g" $YAML_FILE

# Modify Snap
$SED -i "s/version: ${OLD_VERSION}/version: ${NEW_VERSION}/g" $SNAP_YAML_FILE
$SED -i "s/Version=${OLD_VERSION}/Version=${NEW_VERSION}/g" $SNAP_DESKTOP_FILE

# Modify Debain
$SED -i "s/Version: ${OLD_VERSION}/Version: ${NEW_VERSION}/g" $DEBIAN_YAML_FILE
$SED -i "s/Version=${OLD_VERSION}/Version=${NEW_VERSION}/g" $DEBIAN_DESKTOP_FILE

# Modify Qt
OLD_FILEVERSION="$MAJOR_NUMBER,$MINOR_NUMBER,$OLD_PATCH_NUMBER"
FILEVERSION="$MAJOR_NUMBER,$MINOR_NUMBER,$PATCH_NUMBER"
$SED -i "s/${OLD_FILEVERSION},0/${FILEVERSION},0/g" $QT_RC_FILE
$SED -i "s/${OLD_VERSION}.0/${NEW_VERSION}.0/g" $QT_RC_FILE

# Changelog
rm -f ${BUILD_NUMBER}.txt
touch ${BUILD_NUMBER}.txt

echo "v$NEW_VERSION" >> ${BUILD_NUMBER}.txt
echo >> ${BUILD_NUMBER}.txt

cp ${BUILD_NUMBER}.txt $EN_CHANGLOG_DIR
cp ${BUILD_NUMBER}.txt $ZH_CHANGLOG_DIR
rm -f ${BUILD_NUMBER}.txt

echo "This update includes various improvements and bug fixes to make the app better for you." >> $EN_CHANGLOG_DIR/${BUILD_NUMBER}.txt
echo "此更新包括各种改进和错误修复，以使本 App 更好用。" >> $ZH_CHANGLOG_DIR/${BUILD_NUMBER}.txt


$EDITOR $EN_CHANGLOG_DIR/${BUILD_NUMBER}.txt
$EDITOR $ZH_CHANGLOG_DIR/${BUILD_NUMBER}.txt

# Git commit
git status -s
git add .
git commit -m "Sanmill v$NEW_VERSION (${BUILD_NUMBER})" -m "Official release version of Sanmill v$NEW_VERSION"
#exit
git tag -d v$NEW_VERSION || true
git tag -m "Sanmill v$NEW_VERSION (${BUILD_NUMBER})" -m "Official release version of Sanmill v$NEW_VERSION" v$NEW_VERSION
git push origin v$NEW_VERSION -f
git push origin master
