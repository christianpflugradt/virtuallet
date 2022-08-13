using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SQLite;
using System.IO;

namespace virtuallet {

    static class Util {

        internal static void Print(string str) {
            Console.Write(str.Replace(virtuallet.TAB, "\t"));
        }

        internal static void PrintLine(string str) {
            Print($"{str}{Environment.NewLine}");
        }

        internal static string Input(string prefix) {
            Print(prefix);
            return Console.ReadLine();
        }

        internal static string ReadConfigInput(string description, string standard) {
            var input = Input(TextResources.SetupTemplate(description, standard));
            if (string.IsNullOrEmpty(input)) {
                return standard;
            } else {
                return input;
            }
        }

    }

    class Database {

        SQLiteConnection _con = null;

        internal void Connect() {
            if (_con == null) {
                _con = new SQLiteConnection($"Data Source={virtuallet.DB_FILE}");
                _con.Open();
            }
        }

        internal void Disconnect() {
            _con.Close();
        }

        internal void CreateTables() {
            var cmd = new SQLiteCommand(_con);
            cmd.CommandText = @"
                CREATE TABLE ledger (
                    description TEXT,
                    amount REAL NOT NULL,
                    auto_income INTEGER NOT NULL,
                    created_by TEXT,
                    created_at TIMESTAMP NOT NULL,
                    modified_at TIMESTAMP)";
            cmd.ExecuteNonQuery();
            cmd.CommandText = "CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)";
            cmd.ExecuteNonQuery();
        }

        internal void InsertConfiguration(string key, string value) {
            var cmd = new SQLiteCommand(_con);
            cmd.CommandText = "INSERT INTO configuration (k, v) VALUES (@key, @value)";
            cmd.Parameters.AddWithValue("@key", key);
            cmd.Parameters.AddWithValue("@value", value);
            cmd.Prepare();
            cmd.ExecuteNonQuery();
        }

        internal void InsertIntoLedger(string description, double amount) {
            var cmd = new SQLiteCommand(_con);
            cmd.CommandText = @"
                INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
                VALUES (@description, ROUND(@amount, 2), 0, datetime('now'), 'Mono 6.12 Edition')";
            cmd.Parameters.AddWithValue("@description", description);
            cmd.Parameters.AddWithValue("@amount", amount);
            cmd.Prepare();
            cmd.ExecuteNonQuery();
        }

        internal void InsertAutoIncome(int month, int year) {
            var cmd = new SQLiteCommand(_con);
            var description = $"{IncomeDescription()} {month.ToString("D2")}/{year}";
            cmd.CommandText = @"
                INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
                VALUES (@description, ROUND(@amount, 2), 1, datetime('now'), 'Mono 6.12 Edition')";
            cmd.Parameters.AddWithValue("@description", description);
            cmd.Parameters.AddWithValue("@amount", IncomeAmount());
            cmd.Prepare();
            cmd.ExecuteNonQuery();
        }

        internal double Balance() {
            var cmd = new SQLiteCommand("SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger", _con);
            var result = cmd.ExecuteReader();
            result.Read();
            return result.GetDouble(0);
        }

        internal string Transactions() {
            var cmd = new SQLiteCommand($"SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30", _con);
            var result = cmd.ExecuteReader();
            var rows = new List<string>();
            while(result.Read()) {
                rows.Add($"\t{string.Join("\t", new List<string>{result.GetString(0), result.GetDouble(1).ToString(), result.GetString(2)})}");
            }
            return $"{string.Join(Environment.NewLine, rows)}{Environment.NewLine}";
        }

        string IncomeDescription() {
            var cmd = new SQLiteCommand($"SELECT v FROM configuration WHERE k = '{virtuallet.CONF_INCOME_DESCRIPTION}'", _con);
            var result = cmd.ExecuteReader();
            result.Read();
            return result.GetString(0);
        }

        double IncomeAmount() {
            var cmd = new SQLiteCommand($"SELECT v FROM configuration WHERE k = '{virtuallet.CONF_INCOME_AMOUNT}'", _con);
            var result = cmd.ExecuteReader();
            result.Read();
            return Convert.ToDouble(result.GetString(0));
        }

        double Overdraft() {
            var cmd = new SQLiteCommand($"SELECT v FROM configuration WHERE k = '{virtuallet.CONF_OVERDRAFT}'", _con);
            var result = cmd.ExecuteReader();
            result.Read();
            return Convert.ToDouble(result.GetString(0));
        }

        internal bool IsExpenseAcceptable(double expense) {
            return Balance() + Overdraft() - expense >= 0;
        }

        internal void InsertAllDueIncomes() {
            var dueDates = new List<Tuple<int, int>>();
            var dueDate = new Tuple<int, int>(DateTime.Today.Month, DateTime.Today.Year);
            while(!HasAutoIncomeForMonth(dueDate.Item1, dueDate.Item2)) {
                dueDates.Add(dueDate);
                dueDate = new Tuple<int, int>(
                    dueDate.Item1 > 1 ? dueDate.Item1 - 1 : 12,
                    dueDate.Item1 > 1 ? dueDate.Item2 : dueDate.Item2 - 1
                );
            }
            dueDates.Reverse();
            foreach (var date in dueDates) {
                InsertAutoIncome(date.Item1, date.Item2);
            }
        }

        bool HasAutoIncomeForMonth(int month, int year) {
            var cmd = new SQLiteCommand($@"
                    SELECT EXISTS(
                        SELECT auto_income FROM ledger
                        WHERE auto_income = 1
                        AND description LIKE '% {month.ToString("D2")}/{year}')
                ", _con);
            var result = cmd.ExecuteReader();
            result.Read();
            return result.GetInt32(0) == 1;
        }

    }

    class Setup {

        readonly Database _database;

        internal Setup(Database database) {
            _database = database;
        }

        internal void SetupOnFirstRun() {
            if (!File.Exists(virtuallet.DB_FILE)) {
                Initialize();
            }
        }

        void Initialize() {
            Util.Print(TextResources.SetupPreDatabase());
            _database.Connect();
            _database.CreateTables();
            Util.Print(TextResources.SetupPostDatabase());
            SetUp();
            Util.PrintLine(TextResources.SetupComplete());
        }

        void SetUp() {
            var descriptionInput = Util.ReadConfigInput(TextResources.SetupDescription(), "pocket money");
            var amountInput = Util.ReadConfigInput(TextResources.SetupIncome(), "100");
            var overdraftInput = Util.ReadConfigInput(TextResources.SetupOverdraft(), "200");
            _database.InsertConfiguration(virtuallet.CONF_INCOME_DESCRIPTION, descriptionInput);
            _database.InsertConfiguration(virtuallet.CONF_INCOME_AMOUNT, amountInput);
            _database.InsertConfiguration(virtuallet.CONF_OVERDRAFT, overdraftInput);
            _database.InsertAutoIncome(DateTime.Today.Month, DateTime.Today.Year);
        }

    }

    class Loop {

        const string KEY_ADD = "+";
        const string KEY_SUB = "-";
        const string KEY_SHOW = "=";
        const string KEY_HELP = "?";
        const string KEY_QUIT = ":";

        readonly Database _database;

        internal Loop(Database database) {
            _database = database;
        }

        internal void Looop() {
            _database.Connect();
            _database.InsertAllDueIncomes();
            Util.Print(TextResources.CurrentBalance(_database.Balance()));
            HandleInfo();
            var looping = true;
            while(looping) {
                string input = Util.Input(TextResources.EnterInput());
                switch(input) {
                    case KEY_ADD:
                        HandleAdd();
                        break;
                    case KEY_SUB:
                        HandleSub();
                        break;
                    case KEY_SHOW:
                        HandleShow();
                        break;
                    case KEY_HELP:
                        HandleHelp();
                        break;
                    case KEY_QUIT:
                        looping = false;
                        break;
                    default:
                        if (new List<string>{KEY_ADD, KEY_SUB}.Contains(input.Substring(0, 1))) {
                            Omg();
                        } else {
                            HandleInfo();
                        }
                        break;
                }
            }
            _database.Disconnect();
            Util.PrintLine(TextResources.Bye());
        }

        void AddToLedger(int signum, string successMessage) {
            string description = Util.Input(TextResources.EnterDescription());
            double amount;
            if (!Double.TryParse(Util.Input(TextResources.EnterAmount()), out amount)) {
                amount = 0;
            }
            if (amount > 0) {
                if (signum == 1 || _database.IsExpenseAcceptable(amount)) {
                    _database.InsertIntoLedger(description, amount * signum);
                    Util.PrintLine(successMessage);
                    Util.Print(TextResources.CurrentBalance(_database.Balance()));
                } else {
                    Util.PrintLine(TextResources.ErrorTooExpensive());
                }
            } else if (amount < 0) {
                Util.PrintLine(TextResources.ErrorNegativeAmount());
            } else {
                Util.PrintLine(TextResources.ErrorZeroOrInvalidAmount());
            }
        }

        void HandleAdd() {
            AddToLedger(1, TextResources.IncomeBooked());
        }

        void HandleSub() {
            AddToLedger(-1, TextResources.ExpenseBooked());
        }

        void HandleShow() {
            Util.Print(TextResources.FormattedBalance(_database.Balance(), _database.Transactions()));
        }

        void HandleHelp() {
            Util.Print(TextResources.Help());
        }

        void HandleInfo() {
            Util.Print(TextResources.Info());
        }

        void Omg() {
            Util.Print(TextResources.ErrorOmg());
        }

    }

    static class TextResources {

        internal static string Banner() {
            return @"
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>Mono 6.12 Edition


";
        }

        internal static string Info() {
            return @"
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

";
        }

        internal static string Help() {
            return @"
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
<TAB>you won''t be able to add an expense if the balance would be less than -200 afterwards.

<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser
<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.

<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.

";
        }

        internal static string SetupPreDatabase() {
            return @"
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
";
        }

        internal static string SetupPostDatabase() {
            return @"
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

";
        }

        internal static string SetupComplete() {
            return "setup complete, have fun";
        }

        internal static string ErrorOmg() {
            return "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that";
        }

        internal static string ErrorZeroOrInvalidAmount() {
            return "amount is zero or invalid -> action aborted";
        }

        internal static string ErrorNegativeAmount() {
            return "amount must be positive -> action aborted";
        }

        internal static string IncomeBooked() {
            return "income booked";
        }

        internal static string ExpenseBooked() {
            return "expense booked successfully";
        }

        internal static string ErrorTooExpensive() {
            return "sorry, too expensive -> action aborted";
        }

        internal static string EnterInput() {
            return "input > ";
        }

        internal static string EnterDescription() {
            return "description (optional) > ";
        }

        internal static string EnterAmount() {
            return "amount > ";
        }

        internal static string Bye() {
            return "see ya";
        }

        internal static string CurrentBalance(double balance) {
            return $@"
<TAB>current balance: {balance}

";
        }

        internal static string FormattedBalance(double balance, string formattedBalance) {
            return $@"
<TAB>current balance: {balance}

<TAB>last transactions (up to 30)
<TAB>----------------------------
{formattedBalance}
";
        }

        internal static string SetupDescription() {
            return "enter description for regular income";
        }

        internal static string SetupIncome() {
            return "enter regular income";
        }

        internal static string SetupOverdraft() {
            return "enter overdraft";
        }

        internal static string SetupTemplate(string description, string standard) {
            return $"{description} [default: {standard}] > ";
        }

    }

    class virtuallet {

        internal const string CONF_INCOME_DESCRIPTION = "income_description";
        internal const string CONF_INCOME_AMOUNT = "income_amount";
        internal const string CONF_OVERDRAFT = "overdraft";
        internal const string DB_FILE = "../db_virtuallet.db";
        internal const string TAB = "<TAB>";

        static void Main(string[] args) {
            Util.Print(TextResources.Banner());
            var database = new Database();
            var setup = new Setup(database);
            setup.SetupOnFirstRun();
            var loop = new Loop(database);
            loop.Looop();
        }

    }

}
