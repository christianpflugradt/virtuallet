#include <ctype.h>
#include <math.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <cstring>
#include <string>
#include <iostream>
#include <list>

using std::string;

static const string CONF_INCOME_DESCRIPTION = "income_description";
static const string CONF_INCOME_AMOUNT = "income_amount";
static const string CONF_OVERDRAFT = "overdraft";
static const string DB_FILE = "../db_virtuallet.db";
static const string TAB = "<TAB>";

class TextResources {
    public:
        static string banner();
        static string info();
        static string help();
        static string setupPreDatabase();
        static string setupPostDatabase();
        static string setupComplete();
        static string errorOmg();
        static string errorZeroOrInvalidAmount();
        static string errorNegativeAmount();
        static string incomeBooked();
        static string expenseBooked();
        static string errorTooExpensive();
        static string enterInput();
        static string enterDescription();
        static string enterAmount();
        static string bye();
        static string currentBalance(const double value);
        static string formattedBalance(const double balance, const string formattedBalance);
        static string setupDescription();
        static string setupIncome();
        static string setupOverdraft();
        static string setupTemplate(const string description, const string standard);
};

class Util {

    public:

        static bool fileExists(const string filename) {
            struct stat buffer;
            return stat (filename.c_str(), &buffer) == 0;
        }

        static void print(string str) {
            std::cout << Util::replaceAll(str, TAB, "\t");
        }

        static void println(string str) {
            std::cout << str << std::endl;
        }

        static string input(const string prefix) {
            Util::print(prefix + " > ");
            string result;
            getline(std::cin, result);
            return result;
        }

        static string readConfigInput(const string description, const string standard) {
            const string result = Util::input(TextResources::setupTemplate(description, standard));
            return result.empty() ? standard : result;
        }

        static char * strToChr(const string str) {
            char chr[str.size() + 1];
            strcpy(chr, str.c_str());
            return strdup(chr);
        }

        static struct tm * now() {
            time_t now;
            time(&now);
            return localtime(&now);
        }

        static int currentMonth() {
            return now()->tm_mon + 1;
        }

        static int currentYear() {
            return now()->tm_year + 1900;
        }

        static string toFormattedString(const double d) {
            int requiredSize = 50;
            char str[requiredSize];
            snprintf(str, requiredSize, "%.2f", d);
            string result(str);
            return result;

        }

        static string replaceAll(string str, const string occurrence, const string replacement) {
            int found = str.find(occurrence);
            while(found != string::npos) {
                str.replace(str.find(occurrence), occurrence.length(), replacement);
                found = str.find(occurrence);
            }
            return str;
        }

};

class Database {

    public:

        void connect() {
            if (!db) {
                sqlite3_open(DB_FILE.c_str(), &db);
            }
        }

        void disconnect() {
            sqlite3_close(db);
        }

        void createTables() {
            executeStatement(R"(
                CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL,
                auto_income INTEGER NOT NULL,
                created_by TEXT,
                created_at TIMESTAMP NOT NULL,
                modified_at TIMESTAMP)
            )");
            executeStatement(" CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)");
        }

        void insertAutoIncome(int month, int year) {
            int requiredSize = 9;
            char dateInfo[requiredSize];
            snprintf(dateInfo, requiredSize, " %02d/%d", month, year);
            const string description = incomeDescription() + dateInfo;
            const float amount = incomeAmount();
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 1, datetime('now'), 'C++17 Edition') ", -1, &stmt, 0);
            sqlite3_bind_text(stmt, 1, description.c_str(), description.length(), NULL);
            sqlite3_bind_double(stmt, 2, amount);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }

        void insertConfiguration(const string key, const string value) {
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " INSERT INTO configuration (k, v) VALUES (?, ?)", -1, &stmt, 0);
            sqlite3_bind_text(stmt, 1, key.c_str(), key.length(), NULL);
            sqlite3_bind_text(stmt, 2, value.c_str(), value.length(), NULL);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }

        void insertIntoLedger(const string description, const float amount) {
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 0, datetime('now'), 'C++17 Edition') ", -1, &stmt, 0);
            sqlite3_bind_text(stmt, 1, description.c_str(), description.length(), NULL);
            sqlite3_bind_double(stmt, 2, amount);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }

        float balance() {
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger ", -1, &stmt, 0);
            sqlite3_step(stmt);
            float balance = sqlite3_column_double(stmt, 0);
            sqlite3_finalize(stmt);
            return balance;
        }

        string transactions() {
            string result = "";
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30 ", -1, &stmt, 0);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const string isoDatetime(sqlite3ColumnText(stmt, 0));
                const string amount = Util::toFormattedString(sqlite3_column_double(stmt, 1));
                const string description(sqlite3ColumnText(stmt, 2));
                result += "\t" + isoDatetime + "\t" + amount + "\t" + description + "\n";
            }
            sqlite3_finalize(stmt);
            return result;
        }

        string incomeDescription() {
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
            sqlite3_bind_text(stmt, 1, CONF_INCOME_DESCRIPTION.c_str(), CONF_INCOME_DESCRIPTION.length(), NULL);
            sqlite3_step(stmt);
            const string description(sqlite3ColumnText(stmt, 0));
            sqlite3_finalize(stmt);
            return description;
        }

        double incomeAmount() {
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
            sqlite3_bind_text(stmt, 1, CONF_INCOME_AMOUNT.c_str(), CONF_INCOME_AMOUNT.length(), NULL);
            sqlite3_step(stmt);
            const string amount(sqlite3ColumnText(stmt, 0));
            sqlite3_finalize(stmt);
            return std::atof(amount.c_str());
        }

        double overdraft() {
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
            sqlite3_bind_text(stmt, 1, CONF_OVERDRAFT.c_str(), CONF_OVERDRAFT.length(), NULL);
            sqlite3_step(stmt);
            const string overdraft(sqlite3ColumnText(stmt, 0));
            sqlite3_finalize(stmt);
            return std::atof(overdraft.c_str());
        }

        bool isExpenseAcceptable(const float expense) {
            return balance() + overdraft() - expense >= 0;
        }

        void insertAllDueIncomes() {
            typedef struct {
                int month;
                int year;
            } DueDate;
            std::list<DueDate> dueDates = {};
            DueDate dueDate;
            dueDate.month = Util::currentMonth();
            dueDate.year = Util::currentYear();
            while(!hasAutoIncomeForMonth(dueDate.month, dueDate.year)) {
                DueDate currentDueDate;
                currentDueDate.month = dueDate.month;
                currentDueDate.year = dueDate.year;
                dueDates.push_back(currentDueDate);
                if (dueDate.month > 1) {
                    dueDate.month -= 1;
                } else {
                    dueDate.year -= 1;
                    dueDate.month = 12;
                }
            }
            while(!dueDates.empty()) {
                DueDate nextDueDate = dueDates.back();
                dueDates.pop_back();
                insertAutoIncome(nextDueDate.month, nextDueDate.year);
            }
        }

    private:

        sqlite3 *db = NULL;

        void executeStatement(const char *sql) {
            char *err = 0;
            sqlite3_exec(db, sql, 0, 0, &err);
            sqlite3_free(err);
        }

        const char * sqlite3ColumnText(sqlite3_stmt *stmt, int index) {
            return reinterpret_cast<const char*>(sqlite3_column_text(stmt, index));
        }

        bool hasAutoIncomeForMonth(const int month, const int year) {
            const int requiredSize = 10;
            char dateInfo[requiredSize];
            snprintf(dateInfo, requiredSize, "%% %02d/%d", month, year);
            sqlite3_stmt *stmt;
            sqlite3_prepare_v2(db, " SELECT EXISTS( "\
                        " SELECT auto_income FROM ledger "\
                        " WHERE auto_income = 1 "\
                        " AND description LIKE ? )", -1, &stmt, 0);
            sqlite3_bind_text(stmt, 1, dateInfo, strlen(dateInfo), NULL);
            sqlite3_step(stmt);
            int match = sqlite3_column_int(stmt, 0);
            sqlite3_finalize(stmt);
            return match == 1;
        }

};

class Setup {

    public:

        Setup(Database database) {
            db = database;
        }

        void setupOnFirstRun() {
            if (!Util::fileExists(DB_FILE)) {
                initialize();
            }
        }

    private:

        Database db;

        void initialize() {
            Util::print(TextResources::setupPreDatabase());
            db.connect();
            db.createTables();
            Util::print(TextResources::setupPostDatabase());
            setup();
            Util::println(TextResources::setupComplete());
        }

        void setup() {
            const string descriptionInput = Util::readConfigInput(TextResources::setupDescription(), "pocket money");
            const string amountInput = Util::readConfigInput(TextResources::setupIncome(), "100");
            const string overdraftInput = Util::readConfigInput(TextResources::setupOverdraft(), "200");
            db.insertConfiguration(CONF_INCOME_DESCRIPTION, descriptionInput);
            db.insertConfiguration(CONF_INCOME_AMOUNT, amountInput);
            db.insertConfiguration(CONF_OVERDRAFT, overdraftInput);
            int month = Util::currentMonth();
            int year = Util::currentYear();
            db.insertAutoIncome(month, year);
        }

};

class Loop {

    public:

        Loop(Database database) {
            db = database;
        }

        void loop() {
            db.connect();
            db.insertAllDueIncomes();
            Util::print(TextResources::currentBalance(db.balance()));
            handleInfo();
            bool looping = true;
            while(looping) {
                const string input = Util::input(TextResources::enterInput());
                if (input == KEY_ADD) {
                    handleAdd();
                } else if (input == KEY_SUB) {
                    handleSub();
                } else if (input == KEY_SHOW) {
                    handleShow();
                } else if (input == KEY_HELP) {
                    handleHelp();
                } else if (input == KEY_QUIT) {
                    looping = false;
                } else if (input.substr(0, 1) == KEY_ADD || input.substr(0, 1) == KEY_SUB){
                    omg();
                } else {
                    handleInfo();
                }
            }
            db.disconnect();
            Util::println(TextResources::bye());
        }

    private:

        Database db;
        const string KEY_ADD = "+";
        const string KEY_SUB = "-";
        const string KEY_SHOW = "=";
        const string KEY_HELP = "?";
        const string KEY_QUIT = ":";

        void addToLedger(const int signum, const string successMessage) {
            const string description = Util::input(TextResources::enterDescription());
            const string amountStr = Util::input(TextResources::enterAmount());
            double amount = std::atof(amountStr.c_str());
            if (amount > 0) {
                if (signum == 1 || db.isExpenseAcceptable(amount)) {
                    db.insertIntoLedger(description, amount * signum);
                    Util::println(successMessage);
                    Util::print(TextResources::currentBalance(db.balance()));
                } else {
                    Util::println(TextResources::errorTooExpensive());
                }
            } else if (amount < 0) {
                Util::println(TextResources::errorNegativeAmount());
            } else {
                Util::println(TextResources::errorZeroOrInvalidAmount());
            }
        }

        void handleAdd() {
            addToLedger(1, TextResources::incomeBooked());
        }

        void handleSub() {
            addToLedger(-1, TextResources::expenseBooked());
        }

        void handleShow() {
            Util::print(TextResources::formattedBalance(db.balance(), db.transactions()));
        }

        void handleHelp() {
            Util::print(TextResources::help());
        }

        void handleInfo() {
            Util::print(TextResources::info());
        }

        void omg() {
            Util::println(TextResources::errorOmg());
        }

};

    string TextResources::banner() {
        return R"(
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>C++17 Edition


)";
    }

    string TextResources::info() {
        return R"(
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

)";
    }

    string TextResources::help() {
        return R"(
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

)";
    }

    string TextResources::setupPreDatabase() {
        return R"(
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
)";
    }

    string TextResources::setupPostDatabase() {
        return R"(
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

)";
    }

    string TextResources::setupComplete() {
        return "setup complete, have fun";
    }

    string TextResources::errorOmg() {
        return "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that";
    }

    string TextResources::errorZeroOrInvalidAmount() {
        return "amount is zero or invalid -> action aborted";
    }

    string TextResources::errorNegativeAmount() {
        return "amount must be positive -> action aborted";
    }

    string TextResources::incomeBooked() {
        return "income booked";
    }

    string TextResources::expenseBooked() {
        return "expense booked successfully";
    }

    string TextResources::errorTooExpensive() {
        return "sorry, too expensive -> action aborted";
    }

    string TextResources::enterInput() {
        return "input";
    }

    string TextResources::enterDescription() {
        return "description (optional)";
    }

    string TextResources::enterAmount() {
        return "amount";
    }

    string TextResources::bye() {
        return "see ya";
    }

    string TextResources::currentBalance(const double balance) {
        string result = R"(
<TAB>current balance: ?

)";
        return Util::replaceAll(result, "?", Util::toFormattedString(balance));
    }

    string TextResources::formattedBalance(const double balance, const string formattedBalance) {
        string result = R"(
<TAB>current balance: ?

<TAB>last transactions (up to 30)
<TAB>----------------------------
)";
        return Util::replaceAll(result, "?", Util::toFormattedString(balance)) + formattedBalance;
    }

    string TextResources::setupDescription() {
        return "enter description for regular income";
    }

    string TextResources::setupIncome() {
        return "enter regular income";
    }

    string TextResources::setupOverdraft() {
        return "enter overdraft";
    }

    string TextResources::setupTemplate(const string description, const string standard) {
        return description + " [default: " + standard + "]";
    }

int main() {
	Util::print(TextResources::banner());
	Database database;
	Setup setup = Setup(database);
	setup.setupOnFirstRun();
	Loop loop = Loop(database);
	loop.loop();
	database.disconnect();
	return 0;
}
