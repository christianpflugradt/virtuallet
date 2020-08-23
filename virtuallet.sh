#!/usr/bin/env bash

RND=$$
EDITIONS_COUNT=3
SELECTED_EDITION=$(($(($RND%$EDITIONS_COUNT))+1))

if [ $SELECTED_EDITION == 1 ]; then
  cd python
  python3 virtuallet.py
elif [ $SELECTED_EDITION == 2 ]; then
  cd java
  javac -cp sqlite-jdbc.jar:. virtuallet.java
  java -cp sqlite-jdbc.jar:. virtuallet
elif [ $SELECTED_EDITION == 3 ]; then
  cd c
  gcc -std=gnu89 virtuallet.c -o virtuallet.out -lsqlite3 -lm
  ./virtuallet.out
fi
