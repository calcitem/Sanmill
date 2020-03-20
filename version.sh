#!/bin/bash

VERSION_H=include/version.h
TEMPLATE_FILE=include/version.h.template
GIT_BRANCH=master

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
else
    GIT_VERSION=
    VER="x"
fi

rm -f config.git-hash

sed "s/\$FULL_VERSION/$GIT_VERSION/g" < $TEMPLATE_FILE > $VERSION_H

git update-index --assume-unchanged $VERSION_H

echo "Generated $VERSION_H"
echo
cat $VERSION_H


