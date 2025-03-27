#!/bin/bash

for file in *.html
do
    if [ -e "$file" ]
    then
        output="${file%.html}.md"
        pandoc -f html -t markdown "$file" -o "$output"
    fi
done
