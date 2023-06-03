import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sql;

const DB_FILE = '../db_virtuallet.db';
const CONF_INCOME_DESCRIPTION = "income_description";
const CONF_INCOME_AMOUNT = "income_amount";
const CONF_OVERDRAFT = "overdraft";
const TAB = "<TAB>";

class Util {

  static prnt(str) {
    stdout.write(str.replaceAll(TAB, '\t'));
  }

  static prntln(str) {
    prnt('$str\n');
  }

  static String input(String message) {
    prnt(message);
    return stdin.readLineSync() ?? '';
  }

  static readConfigInput(String description, standard) {
    final result = input(TextResources.setupTemplate(description, standard));
    return result.trim().isNotEmpty ? result : standard;
  }

}

class Database {

  sql.Database? db = null;

  connect() {
    if (db == null) db = sql.sqlite3.open(DB_FILE);
  }

  disconnect() {
    db?.dispose();
  }

  createTables() {
    db?.execute('''
        CREATE TABLE ledger (
          description TEXT,
          amount REAL NOT NULL, 
          auto_income INTEGER NOT NULL,
          created_by TEXT, 
          created_at TIMESTAMP NOT NULL, 
          modified_at TIMESTAMP)'''
    );
    db?.execute('CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)');
  }

  insertConfiguration(String key, value) {
    db?.execute("INSERT INTO configuration (k, v) VALUES ('$key', '$value')");
  }

  insertIntoLedger(String description, amount) {
    db?.execute(
        '''INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
            VALUES ('$description', ROUND($amount, 2), 0, datetime('now'), 'Dart 3.0 Edition')'''
    );
  }

  balance() => db?.select('SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger').first.values[0] ?? 0.0;

  transactions() {
    final rows = List.empty(growable: true);
    for (final row in db?.select('SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30') ?? []) {
      rows.add('<TAB>${row['created_at']}<TAB>${row['amount']}<TAB>${row['description']}');
    }
    return '${rows.join('\n')}\n';
  }

  incomeDescription() => db?.select("SELECT v FROM configuration WHERE k = '$CONF_INCOME_DESCRIPTION'").first.values[0];
  incomeAmount() => db?.select("SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = '$CONF_INCOME_AMOUNT'").first.values[0];
  overdraft() => db?.select("SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = '$CONF_OVERDRAFT'").first.values[0];

  isExpenseAcceptable(double expense) => expense <= balance() + overdraft();

  insertAutoIncome(int month, int year) {
    final description = '${incomeDescription()} ${month.toString().padLeft(2, '0')}/$year';
    final amount = incomeAmount();
    db?.execute(
      '''INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
         VALUES ('$description', ROUND($amount, 2), 1, datetime('now'), 'Dart 3.0 Edition')'''
    );
  }

  insertAllDueIncomes() {
    var dueDate = (month: DateTime.now().month, year: DateTime.now().year);
    final dueDates = List.empty(growable: true);
    while (!_hasAutoIncomeForMonth(dueDate.month, dueDate.year)) {
      dueDates.add(dueDate);
      dueDate = dueDate.month > 1
          ? (month: dueDate.month - 1, year: dueDate.year)
          : (month: 12, year: dueDate.year - 1);
    }
    dueDates.reversed.forEach((dueDate) { insertAutoIncome(dueDate.month, dueDate.year); });
  }

  _hasAutoIncomeForMonth(int month, int year) => db?.select('''
        SELECT EXISTS(
          SELECT auto_income FROM ledger
          WHERE auto_income = 1
          AND description LIKE '% ${month.toString().padLeft(2, '0')}/$year')''').first.values[0] == 1;

}

class Setup {

  final Database database;

  Setup(this.database);

  setupOnFirstRun() {
    if (!File(DB_FILE).existsSync()) {
      _initialize();
    }
  }

  _initialize() {
    Util.prnt(TextResources.setupPreDatabase());
    database.connect();
    database.createTables();
    Util.prnt(TextResources.setupPostDatabase());
    _setup();
    Util.prntln(TextResources.setupComplete());
  }

  _setup() {
    final incomeDescription = Util.readConfigInput(TextResources.setupDescription(), 'pocket money');
    final incomeAmount = Util.readConfigInput(TextResources.setupIncome(), 100);
    final overdraft = Util.readConfigInput(TextResources.setupOverdraft(), 200);
    database.insertConfiguration(CONF_INCOME_DESCRIPTION, incomeDescription);
    database.insertConfiguration(CONF_INCOME_AMOUNT, incomeAmount);
    database.insertConfiguration(CONF_OVERDRAFT, overdraft);
    database.insertAutoIncome(DateTime.now().month, DateTime.now().year);
  }

}

class Loop {

  static const KEY_ADD = '+';
  static const KEY_SUB = '-';
  static const KEY_SHOW = '=';
  static const KEY_HELP = '?';
  static const KEY_QUIT = ':';

  final Database database;

  Loop(this.database);

  loop() {
    database.connect();
    database.insertAllDueIncomes();
    Util.prntln(TextResources.currentBalance(database.balance()));
    _handleInfo();
    var looping = true;
    while(looping) {
      final input = Util.input(TextResources.enterInput());
      switch(input) {
        case KEY_ADD:
          _handleAdd();
          break;
        case KEY_SUB:
          _handleSub();
          break;
        case KEY_SHOW:
          _handleShow();
          break;
        case KEY_HELP:
          _handleHelp();
          break;
        case KEY_QUIT:
          looping = false;
          break;
        default:
          if (input.isNotEmpty && ([KEY_ADD, KEY_SUB].contains(input[0]))) {
            _omg();
          } else {
            _handleInfo();
          }
          break;
      }
    }
    database.disconnect();
    Util.prntln(TextResources.bye());
  }

  _handleAdd() {
    _addToLedger(1, TextResources.incomeBooked());
  }

  _handleSub() {
    _addToLedger(-1, TextResources.expenseBooked());
  }

  _addToLedger(int signum, String successMessage) {
    final description = Util.input(TextResources.enterDescription());
    final amount = double.tryParse(Util.input(TextResources.enterAmount())) ?? 0;
    if (amount > 0) {
      if (signum == 1 || database.isExpenseAcceptable(amount)) {
        database.insertIntoLedger(description, amount * signum);
        Util.prntln(successMessage);
        Util.prntln(TextResources.currentBalance(database.balance()));
      } else {
        Util.prntln(TextResources.errorTooExpensive());
      }
    } else if (amount < 0) {
      Util.prntln(TextResources.errorNegativeAmount());
    } else {
      Util.prntln(TextResources.errorZeroOrInvalidAmount());
    }
  }

  _handleShow() {
    Util.prnt(TextResources.formattedBalance(database.balance(), database.transactions()));
  }

  _handleInfo() {
    Util.prnt(TextResources.info());
  }

  _handleHelp() {
    Util.prnt(TextResources.help());
  }

  _omg() {
    Util.prntln(TextResources.errorOmg());
  }

}

class TextResources {

  static banner() => '''
  
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/

<TAB>Dart 3.0 Edition


''';

  static info() => '''
  
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

''';

  static help() => '''
  
<TAB>Virtuallet is a tool to act as your virtual wallet. Wow...
<TAB>Virtuallet is accessible via terminal and uses a Sqlite database to store all its data.
<TAB>On first start Virtuallet will be configured and requires some input
<TAB>but you already know that unless you are currently studying the source code.

<TAB>Virtuallet follows two important design principles:

<TAB>- shit in shit out
<TAB>- UTFSB (Use The F**king Sqlite Browser)

<TAB>As a consequence everything in the database is considered valid.
<TAB>Program behaviour is unspecified for any database content being invalid. Ouch...

<TAB>As its primary feature Virtuallet will auto-add the configured income on start up
<TAB>for all days in the past since the last registered regular income.
<TAB>So if you have specified a monthly income and haven't run Virtuallet for three months
<TAB>it will auto-create three regular incomes when you boot it the next time if you like it or not.

<TAB>Virtuallet will also allow you to add irregular incomes and expenses manually.
<TAB>It can also display the current balance and the 30 most recent transactions.

<TAB>The configured overdraft will be considered if an expense is registered.
<TAB>For instance if your overdraft equals the default value of 200
<TAB>you won't be able to add an expense if the balance would be less than -200 afterwards.

<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser
<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.

<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.

''';

  static setupPreDatabase() => '''
  
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
''';

  static setupPostDatabase() => '''
  
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

''';

  static errorZeroOrInvalidAmount() => 'amount is zero or invalid -> action aborted';
  static errorNegativeAmount() => 'amount must be positive -> action aborted';
  static incomeBooked() => 'income booked';
  static expenseBooked() => 'expense booked successfully';
  static errorTooExpensive() => 'sorry, too expensive -> action aborted';
  static errorOmg() => 'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that';
  static enterInput() => 'input > ';
  static enterDescription() => 'description (optional) > ';
  static enterAmount() => 'amount > ';
  static setupComplete() => 'setup complete, have fun';
  static bye() => 'see ya';

  static currentBalance(double balance) => '''

<TAB>current balance: $balance           
''';

  static formattedBalance(double balance, String formattedLastTransactions) => '''
${TextResources.currentBalance(balance)}
<TAB>last transactions (up to 30)
<TAB>----------------------------
$formattedLastTransactions
''';

  static setupDescription() => 'enter description for regular income';

  static setupIncome() => 'enter regular income';

  static setupOverdraft() => 'enter overdraft';

  static setupTemplate(String description, standard) => '$description [default: $standard] > ';

}

main() {
  final database = Database();
  final setup = Setup(database);
  final loop = Loop(database);
  Util.prnt(TextResources.banner());
  setup.setupOnFirstRun();
  loop.loop();
}
