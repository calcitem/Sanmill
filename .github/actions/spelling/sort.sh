#!/bin/bash

# Check if the files exist
if [ ! -f "allow.txt" ] || [ ! -f "expect.txt" ]; then
    echo "Files do not exist."
    exit 1
fi

# Sort the contents of allow.txt with uppercase letters first
LC_COLLATE=C sort allow.txt -o allow.txt

# Sort the contents of expect.txt with uppercase letters first
LC_COLLATE=C sort expect.txt -o expect.txt

echo "Sorting complete."
