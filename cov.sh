#!/bin/bash

rm -rf cov-int
rm -f sanmill.tgz
cd src
rm -rf cov-int
rm -f sanmill.tgz

make clean
cov-build --dir cov-int  make -j build ARCH=x86-64
tar czvf sanmill.tgz cov-int

cd ..
