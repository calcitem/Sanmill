#!/bin/bash

VERSION_H=include/git_version.h
TEMPLATE_FILE=git_version.h.template
GIT_BRANCH=master

rm -f $VERSION_H

git rev-list HEAD | sort > config.git-hash

LOCALVER=`wc -l config.git-hash | awk '{print $1}'`

if [ $LOCALVER \> 1 ] ; then
    VER=`git rev-list origin/$GIT_BRANCH | sort | join config.git-hash - | wc -l | awk '{print $1}'`
    if [ $VER != $LOCALVER ] ; then
        VER="$VER+$(($LOCALVER-$VER))"
    fi
    if git status | grep -q "modified:" ; then
        VER="${VER}M"
    fi
    VER="$VER g$(git rev-list HEAD -n 1 | cut -c 1-7)"
    GIT_VERSION=r$VER
else
    GIT_VERSION=
    VER="x"
fi

rm -f config.git-hash

cat $TEMPLATE_FILE | sed "s/\$FULL_VERSION/$GIT_VERSION/g" > $VERSION_H

echo "Generated $VERSION_H"
echo
cat $VERSION_H


