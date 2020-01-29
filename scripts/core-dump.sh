#!/bin/bash

set -veo pipefail

for file in /cores/*; do
    echo "Core file: $file"
    EXECUTABLE_FILE=$(echo "$file" | sed 's/\/cores\///' | sed -E 's/\.[0-9]+$//' | tr '!' '/')
    echo "Executable: $EXECUTABLE_FILE"
    gdb -c "$file" "$EXECUTABLE_FILE" -ex 'set print pretty on' -ex "thread apply all bt" -ex "set pagination 0" -ex 'info files' -ex 'p $_siginfo._sifields._sigfault.si_addr' -ex 'info locals' -ex 'info frame' -ex 'info args' -ex 'p *sym' -batch
done
