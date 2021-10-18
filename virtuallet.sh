#!/usr/bin/env bash

RND=$$
EDITIONS_COUNT=12
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
elif [ $SELECTED_EDITION == 4 ]; then
  cd ruby
  ruby virtuallet.rb
elif [ $SELECTED_EDITION == 5 ]; then
  cd lua
  lua virtuallet.lua
elif [ $SELECTED_EDITION == 6 ]; then
  cd go
  export GO111MODULE=off
  go run virtuallet.go
elif [ $SELECTED_EDITION == 7 ]; then
  cd javascript
  node virtuallet.js
elif [ $SELECTED_EDITION == 8 ]; then
  cd perl
  perl virtuallet.pl
elif [ $SELECTED_EDITION == 9 ]; then
  cd groovy
  groovy -cp sqlite-jdbc.jar virtuallet.groovy
elif [ $SELECTED_EDITION == 10 ]; then
  cd php
  php virtuallet.php
elif [ $SELECTED_EDITION == 11 ]; then
  cd pascal
  fpc virtuallet
  ./virtuallet
elif [ $SELECTED_EDITION == 12 ]; then
  cd c++
  gcc -std=c++17 virtuallet.cpp -o virtuallet.out -lstdc++ -lsqlite3 -lm
  ./virtuallet.out
fi
