# virtuallet

## About virtuallet as a program

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

## About this project

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

### Installing dependencies

Besides a compiler or runtime environment some languages require further dependencies to be installed, usually a sqlite3 binding.
The necessary steps to get an implementation running will be documented here. Please have a look at the file `virtuallet.sh`
for details how to compile / run each implementation. 

#### Implementations without dependencies

The following implementations do not have any further dependencies, which means sqlite3 is part of the language's system library.
 * Python 3
 * C GNU89

#### Java 11 dependencies

You must have a sqlite3 jdbc driver in your classpath.
I used this one, which is also available on Maven Central: https://github.com/xerial/sqlite-jdbc

#### Ruby 2.7 dependencies

You must have sqlite3 gem installed which can be done using RubyGems package manager: `gem install sqlite3`.
See also: https://rubygems.org/gems/sqlite3

#### Lua 5.4 dependencies

You need to install a specific sqlite3 driver. You can install it using LuaRocks package manager 
but at the time of my implementation it was not yet officially compatible with Lua 5.4, 
so I had to compile it manually using `make` which fortunately worked for me without any further configuration.
You can download it here: http://lua.sqlite.org/index.cgi/home

#### Go 1.15 dependencies

You need to install the sqlite3 driver using go get: `go get github.com/mattn/go-sqlite3`

#### Node.js v15.10.0 dependencies

You need to install the sqlite3 driver via node package manager: `npm install sqlite3`
Additionally you need to install readline-sync via node package manager: `npm install readline-sync`

#### Perl v5.32.1 dependencies

Perl is already installed on most Unix-like operating systems and usually comes bundled with SQLite.
However the installed version of SQLite might be old and not support `CREATE TABLE IF EXISTS`
which will result in the following error: `DBD::SQLite::db do failed: not an error(21) at dbdimp.c line 398`
To resolve the problem, update SQLite using cpan: `cpan DBD::SQLite`

### Implementation challenges

This is a list of of aspects that must be considered when implementing Virtuallet in an arbitrary programming language. These aspects can be more or less challenging depending on the language and how experienced one is with it.
 * opening a connection to a sqlite database
 * executing parametrized statements against a sqlite database
 * querying multiple rows from a sqlite database
 * determining if a file exists
 * reading from stdin
 * converting a string to a real number
 * obtaining the current month and year
 * working with an array of tuples
 * reversing an array

Virtuallet can be implemented in any language as long as these aspects can be implemented in that language, most importantly that language should have a sqlite binding and support reading from stdin.

## Implementations

Implemented:
 * Python 3
 * Java 11
 * C GNU89
 * Ruby 2.7
 * Lua 5.4
 * Go 1.15
 * Node.js v15.10.0
 * Perl v5.32

Planned:
 * Ada
 * C++
 * C#
 * Clojure
 * Cobol
 * Crystal
 * D
 * Dart
 * Eiffel
 * Elixir
 * Erlang
 * Fortran
 * FreeBASIC
 * F#
 * Groovy
 * Haskell
 * Julia
 * Kotlin
 * Lisp
 * Nim
 * Objective-C
 * OCaml
 * Pascal
 * PHP
 * Pike
 * Prolog
 * R
 * Racket
 * Raku
 * Rust
 * S-Lang
 * Scala
 * Seed7
 * Smalltalk
 * Swift
 * Vala
 * VB
 * VB.NET

To Be Evaluated
 * Limbo
 * Oberon
 * QBASIC

Not Planned
 * ABAP
 * Algol family
 * Apex
 * Matlab

## Language Verbosity

Java is the reference language because it is both popular and verbose,
so it is interesting to see how other languages compare to it.

I measure verbosity in two ways:
 1. Number of non-empty, non-comment lines ("lines of code")
 2. Number of non-whitespace characters

The unit "text resources" is not considered for comparison.
It has a lot of text that is identical in all implementations
and there is barely any logic in it.

Obviously both approaches are not ideal but they're good enough for me.
To give you a few examples of what distorts the result:
* splitting an otherwise long statement into multiple statements makes the code easier to read
but increases the language's verbosity in terms of lines of code
* whitespace sensitive languages like Python have an advantage in non-whitespace character verbosity
because whitespace characters used to make blocks are excluded from the verbosity calculation
* CamelCaseImplementations have an advantage over snake_case_implementations because they need fewer letters
* language features are not equally spread, e.g.: there are a lot of functions for example but no inheritance at all

### Lines of Code Verbosity

|   Pos    |   Language         |   Verbosity   |   Lines of Code   |
| -------: | ------------------ | ------------: | ----------------: |
|   1      |   Ruby             |   53.85%      |   154             |
|   2      |   Python           |   62.59%      |   179             |
|   3      |   Lua              |   82.51%      |   236             |
|   4      |   JavaScript       |   93.36%      |   267             |
|   4      |   Perl             |   93.36%      |   267             |
|   6      |   Go               |   95.45%      |   273             |
|   7      |   Java (reference) |   100.00%     |   286             |
|   8      |   C                |   127.27%     |   364             |

### Character Verbosity

|   Pos    |   Language         |   Verbosity   |   Characters      |
| -------: | ------------------ | ------------: | ----------------: |
|   1      |   Ruby             |   37.61%      |   3351            |
|   2      |   Python           |   63.20%      |   5631            |
|   3      |   Lua              |   70.04%      |   6241            |
|   4      |   Perl             |   72.36%      |   6447            |
|   5      |   Go               |   72.57%      |   6466            |
|   6      |   JavaScript       |   83.67%      |   7455            |
|   7      |   C                |   98.37%      |   8765            |
|   8      |   Java (reference) |   100.00%     |   8910            |
