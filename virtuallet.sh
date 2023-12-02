#!/usr/bin/env bash

RND=$$
EDITIONS_COUNT=23
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
elif [ $SELECTED_EDITION == 13 ]; then
  cd lisp
  sbcl --script virtuallet.lisp
elif [ $SELECTED_EDITION == 14 ]; then
  cd kotlin
  kotlinc virtuallet.kt -include-runtime -d virtuallet.jar
  java -cp virtuallet.jar:sqlite-jdbc.jar Virtuallet
elif [ $SELECTED_EDITION == 15 ]; then
  cd fortran
  gfortran -std=f2018 virtuallet.f90 libfortran-sqlite3.a -lsqlite3 -o virtuallet.out
  ./virtuallet.out
elif [ $SELECTED_EDITION == 16 ]; then
  cd rust
  echo "
[package]
name = \"virtuallet\"
version = \"0.1.0\"
edition = \"2021\"

[[bin]]
name = \"virtuallet\"
path = \"virtuallet.rs\"

[dependencies]
chrono = \"0.4\"
rusqlite = { version = \"0.27.0\", features = [\"bundled\"] }

" > Cargo.toml
  RUSTFLAGS=-Awarnings cargo build # --offline # offline accelerates compilation significantly if dependencies are already downloaded
  cp target/debug/virtuallet .
  rm -r target
  rm Cargo*
  ./virtuallet
elif [ $SELECTED_EDITION == 17 ]; then
  cd c#
  mcs /reference:System.Data /reference:System.Data.SQLite virtuallet.cs
  ./virtuallet.exe
elif [ $SELECTED_EDITION == 18 ]; then
  cd scheme
  chicken-csi -s virtuallet.scm
elif [ $SELECTED_EDITION == 19 ]; then
  cd julia
  julia virtuallet.jl
elif [ $SELECTED_EDITION == 20 ]; then
  cd haskell
  ghc -dynamic virtuallet.hs
  ./virtuallet
elif [ $SELECTED_EDITION == 21 ]; then
  cd dart
   echo "
  name: virtuallet
  version: 0.1.0
  environment:
    sdk: ^3.0.0
  " > pubspec.yaml
  dart pub add sqlite3
  dart virtuallet.dart
  rm pubspec.*
elif [ $SELECTED_EDITION == 22 ]; then
  cd objective-c
  clang -o virtuallet virtuallet.m -I `gnustep-config --variable=GNUSTEP_SYSTEM_HEADERS` -L `gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARIES` -lgnustep-base -fconstant-string-class=NSConstantString -D_NATIVE_OBJC_EXCEPTIONS -lobjc -lsqlite3
  ./virtuallet
elif [ $SELECTED_EDITION == 23 ]; then
    cd r
    Rscript virtuallet.R
fi
