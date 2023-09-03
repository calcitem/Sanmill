#!/bin/bash

ARB_FILE=$1
APPEND_FILE=./append.txt

echo "Appending APPEND_FILE to $ARB_FILE..."

sed -i '$s/}$//' $ARB_FILE
sed -i '$s/    }$//' $ARB_FILE
sed -i '${/^$/d;}' $ARB_FILE

dos2unix.exe $ARB_FILE
dos2unix.exe $APPEND_FILE

cat $APPEND_FILE >>  $ARB_FILE

echo "Done."