#!/usr/bin/env bash

RND=$$
RANGE=2
VARIANT=$(($(($RND%$RANGE))+1))

if [ $VARIANT == 1 ]; then
  python3 virtuallet.py
elif [ $VARIANT == 2 ]; then
  javac -cp sqlite-jdbc.jar:. virtuallet.java
  java -cp sqlite-jdbc.jar:. virtuallet
fi
