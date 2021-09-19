#!/bin/bash
 
append() {
    for file in `ls *.arb`
    do
        if test -f $file
        then
            echo "ARB file: $file"
            ./append.sh $file . #需要执行的命令，这里解包deb文件
          fi
    done
}
 
path="/home/work/xxx/xxx"

append
