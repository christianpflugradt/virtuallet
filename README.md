# virtuallet

## About virtuallet as a program

Virtuallet as in Virtual Wallet is a very simple offline console based tool to manage digital pocket money.
It offers the following features:
 * automatically add configurable pocket money to your wallet every month
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

Virtuallet should hopefully be self-explanatory. You will get a quick help right when you start it and can get
more details by pressing the '?' key (question mark) and then enter. From the menu everything is accessed by pressing
one key and then enter and Virtuallet will ask for further input when necessary,
for example to enter a description and an amount when you want to add an expense.

Read further to understand how to start this tool.

## About this project

Virtuallet is very simple on purpose not only because it is all I need to manage my personal pocket money
but also because I use it as an opportunity to get to know other programming languages I never had the chance to use before.

For that second reason I will provide an implementation of Virtuallet in several programming languages
and if you actually want to use this tiny but really handy tool, you can choose an implementation you feel comfortable with.
It certainly doesn't hurt to have some "computer knowledge" if you want to use this tool,
but you probably have if you found this project.

This project does not only offer implementations in several programming languages but also a shell script `virtuallet.sh`
which randomly chooses an implementation. In that file you will also see how to get a specific implementation running.
Keep in mind that you probably want to have a look at that script before you accept it blindly. For example you can
run the Python 3 implementation by running `python3 virtuallet.py` but only if python3 is in your path. First of all
a Python 3 runtime must be installed on your system, and then it might not be available under that name, maybe you want
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

The following implementations do not have any further dependencies, which means sqlite3 is part of the language's system library. Julia has an integrated package manager, so the sqlite dependency is automatically downloaded (or updated) on program start.
 * Python 3.9
 * C GNU89
 * C++ 17
 * FreeBASIC 1.10
 * GNUstep 1.29
 * Julia 1.8

#### CHICKEN Scheme 5.3 dependencies

You need to install `sql-de-lite` and `format` using `chicken-install`. The first dependency is for SQLite3. The second dependency is for basic string formatting functionality such as adding leading zeroes to a string.

#### Dart 3.0 dependencies

Dart depends on `sqlite3/sqlite3.dart` but no manual action is required. The dependency will be downloaded/updated on program start.

#### Fortran 2018 dependencies

You need to install the Fortran binding to SQLite3: `https://github.com/interkosmos/fortran-sqlite3`

The shell script `virtuallet.sh` expects the dependency to be located as `libfortran-sqlite3.a` in the same directory as the Fortran implementation of virtuallet.

#### Free Pascal 3.2 dependencies

Sqlite is already part of the Free Pascal Compiler's standard libraries and it uses the sqlite3 library on your system,
something like sqlite3.so on unixoid systems and sqlite3.dll on Windows.

Many Pascal functions are compiler specific so the code won't compile with anything but the Free Pascal Compiler (fpc).

#### GHC 9.4 dependencies

You need to install the sqlite-simple package from Hackage: `https://hackage.haskell.org/package/sqlite-simple`

I used Haskell Cabal to install it: `cabal install --lib sqlite-simple --ghc-option=-dynamic`

I had to add the `ghc-option=-dynamic` option so that ghc wouldn't complain that some files are missing in the `data-array-byte` package.

#### Go 1.15 dependencies

You need to install the sqlite3 driver using go get: `go get github.com/mattn/go-sqlite3`

#### Groovy 3.0 dependencies

Use the jdbc driver specified for the Java Edition

#### Java 11 dependencies

You must have a sqlite3 jdbc driver in your classpath.
I used this one, which is also available on Maven Central: `https://github.com/xerial/sqlite-jdbc`

#### Kotlin 1.6 dependencies

Use the jdbc driver specified for the Java Edition

#### Lua 5.4 dependencies

You need to install a specific sqlite3 driver. You can install it using LuaRocks package manager
but at the time of my implementation it was not yet officially compatible with Lua 5.4,
so I had to compile it manually using `make` which fortunately worked for me without any further configuration.
You can download it here: `http://lua.sqlite.org/index.cgi/home`

#### Mono 6.12.0 dependencies

`System.Data.SQLite` must be included. It was not part of mono for my linux distro. I downloaded the sqlite source code, at that time via `https://system.data.sqlite.org/downloads/1.0.116.0/sqlite-netFx-full-source-1.0.116.0.zip` and compiled the respective dll by executing `xbuild /p:Configuration=Release /p:UseInteropDll=false /p:UseSqliteStandard=true ./System.Data.SQLite/System.Data.SQLite.2017.csproj` from the location I unpacked the zip file.

#### Node.js v15.10 dependencies

You need to install the sqlite3 driver via node package manager: `npm install sqlite3`
Additionally you need to install readline-sync via node package manager: `npm install readline-sync`

#### Perl v5.32 dependencies

Perl is already installed on most Unix-like operating systems and usually comes bundled with SQLite.
However, the installed version of SQLite might be old and not support `CREATE TABLE IF EXISTS`
which will result in the following error: `DBD::SQLite::db do failed: not an error(21) at dbdimp.c line 398`
To resolve the problem, update SQLite using cpan: `cpan DBD::SQLite`

#### PHP 8.0 dependencies

The line `extension=sqlite3` must be in your `php.ini`. It' usually disabled, with a semicolon in front of it.
My php.ini resides in `/etc/php/`. Under Manjaro I also had to install the library by running `pacman -S php-sqlite`.

#### R 4.3 dependencies

SQLite must be installed. I started the R shell via `R` and then entered `install.packages('RSQLite')` to achieve this.

#### Ruby 2.7 dependencies

You must have sqlite3 gem installed which can be done using RubyGems package manager: `gem install sqlite3`.
See also: https://rubygems.org/gems/sqlite3

#### Rust 1.61 dependencies

You must install chrono (to obtain current month and year) and rusqlite. `virtuallet.sh` uses `cargo` but in theory it is possible to compile the program with both dependencies using `rustc` too.

#### Scala 3.1 dependencies

Use the jdbc driver specified for the Java Edition

#### Steel Bank Common Lisp 2.1 dependencies

You must have `quicklisp` and `asdf` set up. The sqlite dependency will then be automatically downloaded and installed.

#### TypeScript 5.3 dependencies

Node.js is used under the hood but a `package.json` is also temporarily generated, so the dependencies don´t need to be manually preinstalled. For execution `ts-node` is used which can be installed via `npm install ts-node`, alternatively the shell script can be very easily rewritten to use tsc and node directly.

### Implementation challenges

This is a list of aspects that must be considered when implementing Virtuallet in an arbitrary programming language. These aspects can be more or less challenging depending on the language and how experienced one is with it.
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
 * C GNU89
 * C++ 17
 * CHICKEN Scheme 5.3
 * Dart 3.0
 * Fortran 2018
 * Free Pascal 3.2
 * FreeBASIC 1.10
 * GHC 9.4
 * GNUstep 1.29
 * Go 1.15
 * Groovy 3.0
 * Java 11
 * Julia 1.8
 * Kotlin 1.6
 * Lua 5.4
 * Mono 6.12.0
 * Node.js v15.10
 * Perl v5.32
 * PHP 8.0
 * Python 3.9
 * R 4.3
 * Ruby 2.7
 * Rust 1.61
 * Scala 3.1
 * Steel Bank Common Lisp 2.1
 * TypeScript 5.3

 [list of planned implementations](LANGUAGES.md)

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

| Pos | Language         | Verbosity | Lines of Code |
|----:|------------------|----------:|--------------:|
|   1 | Ruby             |    53.66% |           154 |
|   2 | Julia            |    59.58% |           171 |
|   3 | Python           |    62.37% |           179 |
|   4 | Haskell          |    64.11% |           184 |
|   4 | Scala            |    64.11% |           184 |
|   6 | Scheme           |    67.60% |           194 |
|   7 | Common Lisp      |    70.38% |           202 |
|   8 | Dart             |    70.73% |           203 |
|   9 | Kotlin           |    76.66% |           220 |
|  10 | PHP              |    77.00% |           221 |
|  11 | R                |    77.35% |           222 |
|  12 | Lua              |    82.23% |           236 |
|  13 | Groovy           |    83.28% |           239 |
|  14 | Rust             |    91.29% |           262 |
|  15 | TypeScript       |    91.64% |           263 |
|  16 | JavaScript       |    93.03% |           267 |
|  16 | Perl             |    93.03% |           267 |
|  18 | C#               |    94.77% |           272 |
|  19 | Go               |    95.12% |           273 |
|  20 | Java (reference) |   100.00% |           287 |
|  21 | Objective-C      |   104.53% |           300 |
|  22 | FreeBASIC        |   122.30% |           351 |
|  23 | C++              |   125.78% |           361 |
|  24 | C                |   126.83% |           364 |
|  25 | Pascal           |   145.99% |           419 |
|  26 | Fortran          |   155.75% |           447 |

### Character Verbosity

| Pos | Language          | Verbosity | Characters |
|----:|-------------------|----------:|-----------:|
|   1 | Ruby              |    37.38% |       3351 |
|   2 | Dart              |    61.84% |       5543 |
|   3 | Python            |    62.88% |       5637 |
|   4 | Scheme            |    64.88% |       5816 |
|   5 | Julia             |    64.99% |       5826 |
|   6 | R                 |    67.31% |       6034 |
|   7 | Scala             |    67.65% |       6064 |
|   8 | Haskell           |    68.94% |       6180 |
|   9 | Lua               |    69.62% |       6241 |
|  10 | Perl              |    71.92% |       6447 |
|  11 | Groovy            |    71.93% |       6448 |
|  12 | Common Lisp       |    72.23% |       6475 |
|  13 | Go                |    72.31% |       6482 |
|  14 | PHP               |    72.94% |       6538 |
|  15 | Kotlin            |    76.34% |       6843 |
|  16 | TypeScript        |    80.00% |       7172 |
|  17 | C#                |    81.65% |       7319 |
|  18 | JavaScript        |    83.18% |       7456 |
|  19 | Rust              |    87.88% |       7878 |
|  20 | C                 |    97.78% |       8765 |
|  21 | Java (reference)  |   100.00% |       8964 |
|  22 | C++               |   107.54% |       9640 |
|  23 | Pascal            |   112.85% |      10116 |
|  24 | FreeBASIC         |   119.48% |      10710 |
|  25 | Objective-C       |   124.38% |      11149 |
|  26 | Fortran           |   141.79% |      12710 |
