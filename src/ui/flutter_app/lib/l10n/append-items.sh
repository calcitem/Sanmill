#!/bin/bash

append() {
    for file in `ls *.arb`
    do
        if test -f $file
        then
            echo "ARB file: $file"
            ./append.sh $file . # append.sh is a script to append items
          fi
    done
}

path="/home/work/xxx/xxx"

append
