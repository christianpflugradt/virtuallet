# virtuallet #

## About virtuallet as a program ##

Virtuallet as in Virtual Wallet is a very simple offline console based tool to manage digital pocket money.
It offers the following features:
 * automatically add a configurable pocket money to your wallet every month
 * ability to add pocket money for multiple months in the past (if you haven't launched the tool for a while)
 * manually add pocket money
 * manually add expenses
 * displays the current balance and (up to) the last 30 transactions
 * a configurable overdraft and a validation to prevent entering expenses that exceed your current credit balance
 * stores everything in a sqlite database file which can be freely accessed using a sqlite shell or browser

It does not and probably will never offer the following:
 * reporting (use a sqlite browser for that)
 * a server component
 * multi user support
 * currencies (your managed money is just plain numbers)
 * other advanced concepts like categories for expenses
 * update/delete actions for existing data (use a sqlite browser for that)

Virtuallet is designed to be very simple and to take very little of your time.
I myself use it to manage my personal digital pocket money which I have negotiated with my wife.
Since I pay for most of my personal expenses online I figured a tiny tool to manage my pocket money was in order.

Virtuallet should hopefully be self explanatory. You will get a quick help right when you start it and can get
more details by pressing the '?' key (question mark) and then enter. From the menu everything is accessed by pressing
one key and then enter and Virtuallet will ask for further input when necessary,
for example to enter a description and an amount when you want to add an expense.

Read further to understand how to start this tool.

## About this project ##

Virtuallet is very simple on purpose not only because it is all I need to manage my personal pocket money
but also because I use it as an opportunity to get to know other programming languages I never had the chance to use before.

For that second reason I will provide an implementation of Virtuallet in several programming languages
and if you actually want to use this tiny but really handy tool, you can choose an implementation you feel comfortable with.
It certainly doesn't hurt to have some "computer knowledge" if you want to use this tool
but you probably have if you found this gitlab project.

This project does not only offer implementations in several programming languages but also a shell script `virtuallet.sh`
which randomly chooses an implementation. In that file you will also see how to get a specific implementation running.
Keep in mind that you probably want to have a look at that script before you accept it blindly. For example you can
run the Python 3 implementation by running `python3 virtuallet.py` but only if python3 is in your path. First of all
a Python 3 runtime must be installed on your system and then it might not be available under that name, maybe you want
to specify the path instead and should actually invoke something like `/usr/bin/python3 virtuallet.py`. Just keep that in mind for any
implementation you would like to run. You can simply edit the shell script to reflect these changes. Also the shell script
is so simple that even without programming experience you can probably just edit it to exclude specific implementations
you don't want to execute. By the way every implementation can be easily identified by a unique subtitle under the
Virtuallet banner that is displayed upon starting the program. For Python 3 the subtitle is *Python 3 Edition*.

### Implementation challenges ###

This is a list of of aspects that must be considered when implementing Virtuallet in an arbitrary programming language. These aspects can be more or less challenging depending on the language and how experienced one is with it.
 * opening a connection to a sqlite database
 * executing parametrized statements against a sqlite database
 * querying multiple rows from a sqlite database
 * determining if a file exists
 * reading from stdin
 * converting a string to a real number
 * formatting and rounding real numbers
 * formatting the current date as iso string
 * obtaining the current month and year
 * working with an array of tuples
 * reversing an array

 Virtuallet can be implemented in any language as long as these aspects can be implemented in that language, most importantly that language should have a sqlite binding and support reading from stdin.

## Implementations ##

Currently available:
 * Python 3
 * Java 11
 * C GNU89
 * Ruby 2.7

Planned:
 * Ada
 * C++
 * Clojure
 * Cobol
 * D
 * Elixir
 * Erlang
 * Fortran
 * Go
 * Groovy
 * Haskell
 * Javascript
 * Julia
 * Kotlin
 * Lisp
 * Lua
 * Nim
 * OCaml
 * Pascal
 * Perl
 * PHP
 * Pike
 * R
 * Racket
 * Rust
 * Scala
 * Smalltalk
