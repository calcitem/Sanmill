#!/bin/bash

VERSION_H=include/version.h
TEMPLATE_FILE=include/version.h.template
PUBSPEC_YAML_FILE=src/ui/flutter_app/pubspec.yaml
GIT_BRANCH=master

SED=sed

if [ "$(uname)" == "Darwin" ]; then
	SED=gsed
fi

rm -f $VERSION_H

git rev-list HEAD | sort > config.git-hash

LOCALVER="$(wc -l config.git-hash | awk '{print $1}')"
TAG="$(git describe --tags "$(git rev-list --tags --max-count=1)")"

if [ "$LOCALVER" -gt "1" ] ; then
	VER=$(git rev-list origin/$GIT_BRANCH | sort | join config.git-hash - | wc -l | awk '{print $1}')
	if [ "$VER" != "$LOCALVER" ] ; then
		VER="$VER+$((LOCALVER-VER))"
	fi
	if git status | grep -q "modified:" ; then
		VER="${VER}M"
	fi
	VER="$VER g$(git rev-list HEAD -n 1 | cut -c 1-7)"
	GIT_VERSION="$TAG r$VER"
	APP_VERSION="${TAG:1}+${LOCALVER-VER}"
else
	DATE=$(date +%Y%m%d)
	if [ -n "$GITHUB_RUN_NUMBER" ] ; then
		VER="$GITHUB_RUN_NUMBER"
		GIT_VERSION="$TAG #$VER"
	else
		VER="${DATE:2}"
		GIT_VERSION="$TAG Build $VER"
	fi
	APP_VERSION="${TAG:1}+${VER}"
fi

rm -f config.git-hash

$SED "s/\$FULL_VERSION/$GIT_VERSION/g" < $TEMPLATE_FILE > $VERSION_H

git update-index --assume-unchanged $VERSION_H

echo "App Version: ${APP_VERSION}"
echo
echo "Generated $VERSION_H"
echo
cat $VERSION_H

$SED -i '/version:/d' ${PUBSPEC_YAML_FILE}
$SED -i "4i\version: ${APP_VERSION}" ${PUBSPEC_YAML_FILE}
