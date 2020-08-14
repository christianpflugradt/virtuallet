#!/usr/bin/env bash

RND=$$
RANGE=2
VARIANT=$(($(($RND%$RANGE))+1))

if [ $VARIANT == 1 ]; then
  cd python
  python3 virtuallet.py
elif [ $VARIANT == 2 ]; then
  cd java
  javac -cp sqlite-jdbc.jar:. virtuallet.java
  java -cp sqlite-jdbc.jar:. virtuallet
fi
