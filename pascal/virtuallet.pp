{$MODE OBJFPC}
{$M+}
program virtuallet;
uses crt, dos, sqldb, sqlite3conn, sysutils;

const
    DB_FILE = '../db_virtuallet.db';
    CONF_INCOME_DESCRIPTION = 'income_description';
    CONF_INCOME_AMOUNT = 'income_amount';
    CONF_OVERDRAFT = 'overdraft';
    TAB = '<TAB>';

type TextResources = class
    public
        function banner: AnsiString;
        function info: AnsiString;
        function help: AnsiString;
        function setupPreDatabase: AnsiString;
        function setupPostDatabase: AnsiString;
        function errorZeroOrInvalidAmount: AnsiString;
        function errorNegativeAmount: AnsiString;
        function incomeBooked: AnsiString;
        function expenseBooked: AnsiString;
        function errorTooExpensive: AnsiString;
        function errorOmg: AnsiString;
        function enterInput: AnsiString;
        function enterDescription: AnsiString;
        function enterAmount: AnsiString;
        function setupComplete: AnsiString;
        function bye: AnsiString;
        function currentBalance(balance: extended): AnsiString;
        function formattedBalance(balance: extended; formattedLastTransactions: AnsiString): AnsiString;
        function setupDescription: AnsiString;
        function setupIncome: AnsiString;
        function setupOverdraft: AnsiString;
        function setupTemplate(description, standard: AnsiString): AnsiString;
    end;

    Util = class
    private
        tr: TextResources;
    public
        constructor create(param: TextResources);
        procedure prnt(str: AnsiString);
        procedure prntln(str: AnsiString);
        function input(prompt: AnsiString): AnsiString;
        function readConfigInput(prefix, standard: AnsiString): AnsiString;
        function floatVal(str: AnsiString): extended;
        function getAbsoluteDatabaseFilename: AnsiString;
    end;

    Database = class
    private
        sqlite: TSQLite3Connection;
        trans: TSQLTransaction;
        query: TSQLQuery;
        ut: Util;
        procedure insertAutoIncome(month, year: integer);
        function hasAutoIncomeForMonth(month, year: integer): boolean;
    public
        constructor create(param: Util);
        procedure connect;
        procedure disconnect;
        procedure createTables;
        procedure insertConfiguration(key, value: AnsiString);
        procedure insertIntoLedger(description: AnsiString; amount: extended);
        function balance: extended;
        function transactions: AnsiString;
        function incomeDescription: AnsiString;
        function incomeAmount: extended;
        function overdraft: extended;
        function isExpenseAcceptable(expense: extended): boolean;
        procedure insertAllDueIncomes;
    end;

    Setup = class
    private
        db: Database;
        ut: Util;
        tr: TextResources;
        procedure configure;
        procedure setup;
    public
        constructor create(param1: Database; param2: Util; param3: TextResources);
        procedure setupOnFirstRun;
    end;

    Loop = class
    private
        db: Database;
        ut: Util;
          tr: TextResources;
        const KEY_ADD = '+';
        const KEY_SUB = '-';
        const KEY_SHOW = '=';
        const KEY_HELP = '?';
        const KEY_QUIT = ':';
        procedure omg;
        procedure handleAdd;
        procedure handleSub;
        procedure addToLedger(signum: integer; successMessage: AnsiString);
        procedure handleShow;
        procedure handleInfo;
        procedure handleHelp;
    public
        constructor create(param1: Database; param2: Util; param3: TextResources);
        procedure loop;
    end;

    DueDate = record
        month: integer;
        year: integer;
    end;

var
    myUtil: Util;
    myDatabase: Database;
    mySetup: Setup;
    myLoop: Loop;
    myTextResources: TextResources;

constructor Util.create(param: TextResources);
begin
    self.tr := param;
end;

procedure Util.prnt(str: AnsiString);
begin
    Write(StringReplace(str, TAB, #9, [rfReplaceAll]));
end;

procedure Util.prntln(str: AnsiString);
begin
    self.prnt(str + LineEnding);
end;

function Util.input(prompt: AnsiString): AnsiString;
begin
    self.prnt(prompt);
    readln(input);
    input := input;
end;

function Util.readConfigInput(prefix, standard: AnsiString): AnsiString;
begin
    readConfigInput := self.input(self.tr.setupTemplate(prefix, standard));
    if readConfigInput = '' then
    begin
        readConfigInput := standard;
    end;
end;

function Util.floatVal(str: AnsiString): extended;
begin
    try
        floatVal := StrToFloat(str);
    except
        floatVal := 0;
    end;
end;

function Util.getAbsoluteDatabaseFilename: AnsiString;
begin
    getAbsoluteDatabaseFilename := StringReplace(DB_FILE, '..', ExpandFileName(IncludeTrailingPathDelimiter(GetCurrentDir) + '..'), []);
end;

constructor Database.create(param: Util);
begin
    self.sqlite := nil;
    self.ut := param;
end;

procedure Database.connect;
begin
    if sqlite = nil then
    begin
        self.query := TSQLQuery.create(nil);
        self.trans := TSQLTransaction.create(nil);
        self.sqlite := TSQLite3Connection.create(nil);
        self.sqlite.DatabaseName := self.ut.getAbsoluteDatabaseFilename;
        self.sqlite.HostName := 'localhost';
        self.sqlite.CharSet := 'UTF8';
        self.sqlite.Transaction := self.trans;
        self.trans.Database := self.sqlite;
        self.query.Database := self.sqlite;
        self.query.Transaction := self.trans;
        self.sqlite.open;
    end;
end;

procedure Database.disconnect;
begin
    self.trans.commit;
    self.query.close;
    self.sqlite.close;
    self.query.free;
    self.trans.free;
    self.sqlite.free;
end;

procedure Database.createTables;
begin
    self.sqlite.executeDirect('' +
'CREATE TABLE ledger (' +
'       description TEXT,' +
'       amount REAL NOT NULL,' +
'       auto_income INTEGER NOT NULL,' +
'       created_by TEXT,' +
'       created_at TIMESTAMP NOT NULL,' +
'       modified_at TIMESTAMP)');
    self.sqlite.executeDirect('CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)');
end;

procedure Database.insertConfiguration(key, value: AnsiString);
begin
    self.sqlite.executeDirect('INSERT INTO configuration (k, v) VALUES (''' + key + ''', ''' + value + ''')');
end;

procedure Database.insertIntoLedger(description: AnsiString; amount: extended);
begin
    self.sqlite.executeDirect('INSERT INTO ledger (description, amount, auto_income, created_at, created_by) ' +
    'VALUES (''' + description + ''', ROUND(' + FloatToStr(amount) + ', 2), 0, datetime(''now''), ''Free Pascal 3.2 Edition'')');
end;

function Database.balance: extended;
begin
    self.query.SQL.Text := 'SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger';
    self.query.open;
    balance := self.ut.floatVal(self.query.Fields.Fields[0].asString);
    self.query.close;
end;

function Database.transactions: AnsiString;
begin
    self.query.SQL.Text := 'SELECT created_at, CAST(amount AS TEXT), description FROM ledger ORDER BY ROWID DESC LIMIT 30';
    self.query.open;
    transactions := '';
    while not self.query.EOF do
    begin
        transactions := transactions +
                     #9 + FormatDateTime('yyyy-mm-dd HH:MM:ss', self.query.Fields.Fields[0].asDateTime) +
                     #9 + self.query.Fields.Fields[1].asString +
                     #9 + self.query.Fields.Fields[2].asString + LineEnding;
        self.query.next;
    end;
    self.query.close;
end;

function Database.incomeDescription: AnsiString;
begin
    self.query.SQL.Text := 'SELECT v FROM configuration WHERE k = ''' + CONF_INCOME_DESCRIPTION + '''';
    self.query.open;
    incomeDescription := self.query.Fields.Fields[0].asString;
    self.query.close;
end;

function Database.incomeAmount: extended;
begin
    self.query.SQL.Text := 'SELECT v FROM configuration WHERE k = ''' + CONF_INCOME_AMOUNT + '''';
    self.query.open;
    incomeAmount := self.ut.floatVal(self.query.Fields.Fields[0].asString);
    self.query.close;
end;

function Database.overdraft: extended;
begin
    self.query.SQL.Text := 'SELECT v FROM configuration WHERE k = ''' + CONF_OVERDRAFT + '''';
    self.query.open;
    overdraft := self.ut.floatVal(self.query.Fields.Fields[0].asString);
    self.query.close;
end;

function Database.isExpenseAcceptable(expense: extended): boolean;
begin
    isExpenseAcceptable := expense <= self.balance + self.overdraft;
end;

procedure Database.insertAllDueIncomes;
var
    due: DueDate;
    dueDates: array of DueDate;
    size, current, i: integer;
    year, month, mday, wday: word;
begin
    size := 0; current := -1;
    year := 0; month := 0; mday := 0; wday := 0;
    getDate(year, month, mday, wday);
    while not self.hasAutoIncomeForMonth(month, year) do
    begin
        current += 1;
        if current >= size then
        begin
            size += 100;
            SetLength(dueDates, size);
        end;
        due.month := month;
        due.year := year;
        dueDates[current] := due;
        if month > 1 then
        begin
            month -= 1;
        end
        else
        begin
            year -= 1;
            month := 12;
        end;
    end;
    for i := current downto 0 do
    begin
        self.insertAutoIncome(dueDates[i].month, dueDates[i].year);
    end;
end;

procedure Database.insertAutoIncome(month, year: integer);
begin
    self.sqlite.executeDirect('INSERT INTO ledger (description, amount, auto_income, created_at, created_by) ' +
        'VALUES (''' + self.incomeDescription + ' ' + Format('%.2d', [month]) + '/' + IntToStr(year) +
        ''', ROUND(' + FloatToStr(self.incomeAmount) + ', 2), 1, datetime(''now''), ''Free Pascal 3.2 Edition'')');
end;

function Database.hasAutoIncomeForMonth(month, year: integer): boolean;
begin
    self.query.SQL.Text := '' +
'SELECT EXISTS( ' +
'SELECT auto_income FROM ledger ' +
'WHERE auto_income = 1 ' +
'AND description LIKE ''' + self.incomeDescription +
' ' + Format('%.2d', [month]) + '/' + IntToStr(year) + ''')';
    self.query.open;
    hasAutoIncomeForMonth := self.ut.floatVal(self.query.Fields.Fields[0].asString) > 0;
    self.query.close;
end;

constructor Setup.create(param1: Database; param2: Util; param3: TextResources);
begin
     self.db := param1;
     self.ut := param2;
     self.tr := param3;
end;

procedure Setup.setupOnFirstRun;
begin
    if not FileExists(DB_FILE) then
    begin
        self.configure;
    end;
end;

procedure Setup.configure;
begin
      self.ut.prnt(self.tr.setupPreDatabase);
      self.db.connect;
      self.db.createTables;
      self.ut.prnt(self.tr.setupPostDatabase);
      self.setup;
      self.ut.prntln(self.tr.setupComplete);
end;

procedure Setup.setup;
var
    incomeDescription, incomeAmount, overdraft: AnsiString;
    year, month, mday, wday: word;
begin
    year := 0; month := 0; mday := 0; wday := 0;
    incomeDescription := self.ut.readConfigInput(self.tr.setupDescription, 'pocket money');
    incomeAmount := self.ut.readConfigInput(self.tr.setupIncome, '100');
    overdraft := self.ut.readConfigInput(self.tr.setupOverdraft, '200');
    self.db.insertConfiguration(CONF_INCOME_DESCRIPTION, incomeDescription);
    self.db.insertConfiguration(CONF_INCOME_AMOUNT, incomeAmount);
    self.db.insertConfiguration(CONF_OVERDRAFT, overdraft);
    getDate(year, month, mday, wday);
    self.db.insertAutoIncome(month, year);
end;

constructor Loop.create(param1: Database; param2: Util; param3: TextResources);
begin
    self.db := param1;
    self.ut := param2;
    self.tr := param3;
end;

procedure Loop.loop;
var
    looping: boolean;
    inp: AnsiString;
begin
    self.db.connect;
    self.db.insertAllDueIncomes;
    self.ut.prnt(self.tr.currentBalance(self.db.balance));
    self.handleInfo;
    looping := true;
    while looping do
    begin
        inp := self.ut.input(self.tr.enterInput);
        case inp of
             self.KEY_ADD: self.handleAdd;
             self.KEY_SUB: self.handleSub;
             self.KEY_SHOW: self.handleShow;
             self.KEY_HELP: self.handleHelp;
             self.KEY_QUIT: looping := false;
             otherwise
             begin
                 if (Length(inp) > 1) and ((Copy(inp, 1, 1) = KEY_ADD) or (Copy(inp, 1, 1) = KEY_SUB)) then
                 begin
                     self.omg;
                 end
                 else
                 begin
                     self.handleInfo;
                 end;
             end;
        end;
    end;
    self.db.disconnect;
    self.ut.prntln(self.tr.bye);
end;

procedure Loop.omg;
begin
    self.ut.prntln(self.tr.errorOmg);
end;

procedure Loop.handleAdd;
begin
    self.addToLedger(1, self.tr.incomeBooked);
end;

procedure Loop.handleSub;
begin
    self.addToLedger(-1, self.tr.expenseBooked);
end;

procedure Loop.addToLedger(signum: integer; successMessage: AnsiString);
var
    description: AnsiString;
    amount: extended;
begin
    description := self.ut.input(self.tr.enterDescription);
    amount := self.ut.floatVal(self.ut.input(self.tr.enterAmount));
    if amount > 0 then
    begin
        if (signum = 1) or (self.db.isExpenseAcceptable(amount)) then
        begin
            self.db.insertIntoLedger(description, amount * signum);
            self.ut.prntln(successMessage);
            self.ut.prnt(self.tr.currentBalance(self.db.balance));
        end
        else
        begin
            self.ut.prntln(self.tr.errorTooExpensive);
        end;
    end
    else if amount < 0 then
    begin
        self.ut.prntln(self.tr.errorNegativeAmount);
    end
    else
    begin
        self.ut.prntln(self.tr.errorZeroOrInvalidAmount);
    end;
end;

procedure Loop.handleShow;
begin
    self.ut.prnt(self.tr.formattedBalance(self.db.balance, self.db.transactions));
end;

procedure Loop.handleInfo;
begin
    self.ut.prnt(self.tr.info);
end;

procedure Loop.handleHelp;
begin
    self.ut.prnt(self.tr.help);
end;

function TextResources.banner: AnsiString;
begin
     banner :=
'' + LineEnding +
'<TAB> _                                 _   _' + LineEnding +
'<TAB>(_|   |_/o                        | | | |' + LineEnding +
'<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_' + LineEnding +
'<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |' + LineEnding +
'<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/' + LineEnding +
'' + LineEnding +
'<TAB>Free Pascal 3.2 Edition' + LineEnding +
'' + LineEnding +
'' + LineEnding;
end;

function TextResources.info: AnsiString;
begin
    info :=
'' + LineEnding +
'<TAB>Commands:' + LineEnding +
'<TAB>- press plus (+) to add an irregular income' + LineEnding +
'<TAB>- press minus (-) to add an expense' + LineEnding +
'<TAB>- press equals (=) to show balance and last transactions' + LineEnding +
'<TAB>- press question mark (?) for even more info about this program' + LineEnding +
'<TAB>- press colon (:) to exit' + LineEnding +
'' + LineEnding;
end;

function TextResources.help: AnsiString;
begin
    help :=
'' + LineEnding +
'<TAB>Virtuallet is a tool to act as your virtual wallet. Wow...' + LineEnding +
'<TAB>Virtuallet is accessible via terminal and uses a Sqlite database to store all its data.' + LineEnding +
'<TAB>On first start Virtuallet will be configured and requires some input' + LineEnding +
'<TAB>but you already know that unless you are currently studying the source code.' + LineEnding +
'' + LineEnding +
'<TAB>Virtuallet follows two important design principles:' + LineEnding +
'' + LineEnding +
'<TAB>- shit in shit out' + LineEnding +
'<TAB>- UTFSB (Use The F**king Sqlite Browser)' + LineEnding +
'' + LineEnding +
'<TAB>As a consequence everything in the database is considered valid.' + LineEnding +
'<TAB>Program behaviour is unspecified for any database content being invalid. Ouch...' + LineEnding +
'' + LineEnding +
'<TAB>As its primary feature Virtuallet will auto-add the configured income on start up' + LineEnding +
'<TAB>for all days in the past since the last registered regular income.' + LineEnding +
'<TAB>So if you have specified a monthly income and haven''t run Virtuallet for three months' + LineEnding +
'<TAB>it will auto-create three regular incomes when you boot it the next time if you like it or not.' + LineEnding +
'' + LineEnding +
'<TAB>Virtuallet will also allow you to add irregular incomes and expenses manually.' + LineEnding +
'<TAB>It can also display the current balance and the 30 most recent transactions.' + LineEnding +
'' + LineEnding +
'<TAB>The configured overdraft will be considered if an expense is registered.' + LineEnding +
'<TAB>For instance if your overdraft equals the default value of 200' + LineEnding +
'<TAB>you won''t be able to add an expense if the balance would be less than -200 afterwards.' + LineEnding +
'' + LineEnding +
'<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser' + LineEnding +
'<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.' + LineEnding +
'' + LineEnding +
'<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.' + LineEnding +
'' + LineEnding;
end;

function TextResources.setupPreDatabase: AnsiString;
begin
    setupPreDatabase :=
'' + LineEnding +
'<TAB>Database file not found.' + LineEnding +
'<TAB>Database will be initialized. This may take a while... NOT.' + LineEnding;
end;

function TextResources.setupPostDatabase: AnsiString;
begin
    setupPostDatabase :=
'' + LineEnding +
'<TAB>Database initialized.' + LineEnding +
'<TAB>Are you prepared for some configuration? If not I don''t care. There is no way to exit, muhahahar.' + LineEnding +
'<TAB>Press enter to accept the default or input something else. There is no validation' + LineEnding +
'<TAB>because I know you will not make a mistake. No second chances. If you f**k up,' + LineEnding +
'<TAB>you will have to either delete the database file or edit it using a sqlite database browser.' + LineEnding +
'' + LineEnding;
end;

function TextResources.errorZeroOrInvalidAmount: AnsiString;
begin
    errorZeroOrInvalidAmount := 'amount is zero or invalid -> action aborted';
end;

function TextResources.errorNegativeAmount: AnsiString;
begin
    errorNegativeAmount := 'amount must be positive -> action aborted';
end;

function TextResources.incomeBooked: AnsiString;
begin
    incomeBooked := 'income booked';
end;

function TextResources.expenseBooked: AnsiString;
begin
    expenseBooked := 'expense booked successfully';
end;

function TextResources.errorTooExpensive: AnsiString;
begin
    errorTooExpensive := 'sorry, too expensive -> action aborted';
end;

function TextResources.errorOmg: AnsiString;
begin
    errorOmg := 'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that';
end;

function TextResources.enterInput: AnsiString;
begin
    enterInput := 'input > ';
end;

function TextResources.enterDescription: AnsiString;
begin
    enterDescription := 'description (optional) > ';
end;

function TextResources.enterAmount: AnsiString;
begin
    enterAmount := 'amount > ';
end;

function TextResources.setupComplete: AnsiString;
begin
    setupComplete := 'setup complete, have fun';
end;

function TextResources.bye: AnsiString;
begin
    bye := 'see ya';
end;

function TextResources.currentBalance(balance: extended): AnsiString;
begin
    currentBalance :=
'' + LineEnding +
'<TAB>current balance: ' + Format('%.2f', [balance]) + LineEnding +
'' + LineEnding;
end;

function TextResources.formattedBalance(balance: extended; formattedLastTransactions: AnsiString): AnsiString;
begin
    formattedBalance :=
'<TAB>' + self.currentBalance(balance) +
'<TAB>last transactions (up to 30)' + LineEnding +
'<TAB>----------------------------' + LineEnding +
'' + formattedLastTransactions + LineEnding;
end;

function TextResources.setupDescription: AnsiString;
begin
    setupDescription := 'enter description for regular income';
end;

function TextResources.setupIncome: AnsiString;
begin
    setupIncome := 'enter regular income';
end;

function TextResources.setupOverdraft: AnsiString;
begin
    setupOverdraft := 'enter overdraft';
end;

function TextResources.setupTemplate(description, standard: AnsiString): AnsiString;
begin
    setupTemplate := description + ' [default: ' + standard + '] > ';
end;

begin
    myTextResources := TextResources.create;
    myUtil := Util.create(myTextResources);
    myDatabase := Database.create(myUtil);
    mySetup := Setup.create(myDatabase, myUtil, myTextResources);
    myLoop := Loop.create(myDatabase, myUtil, myTextResources);
    myUtil.prnt(myTextResources.banner);
    mySetup.setupOnFirstRun;
    myLoop.loop;
end.
