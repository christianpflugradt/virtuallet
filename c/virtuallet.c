#include <ctype.h>
#include <math.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

void printBanner();
void setupOnFirstRun();
void loop();
void printBanner();
void printInfo();
void printHelp();
void printSetupPreDatabase();
void printSetupPostDatabase();
void printSetupComplete();
void printErrorOmg();
void printErrorZeroOrInvalidAmount();
void printErrorNegativeAmount();
void printIncomeBooked();
void printExpenseBooked();
void printErrorTooExpensive();
void printEnterInput();
void printEnterDescription();
void printEnterAmount();
void printBye();
void printCurrentBalance(float);
void printFormattedBalance(const char *formattedBalance);
void printSetupDescription();
void printSetupIncome();
void printSetupOverdraft();

const char *CONF_INCOME_DESCRIPTION = "income_description";
const char *CONF_INCOME_AMOUNT = "income_amount";
const char *CONF_OVERDRAFT = "overdraft";
const char *DB_FILE = "../db_virtuallet.db";
sqlite3 *db = NULL;

const char KEY_ADD = '+';
const char KEY_SUB = '-';
const char KEY_SHOW = '=';
const char KEY_HELP = '?';
const char KEY_QUIT = ':';

/*
layout of this unit (ctrl+f to jump to the respective section)
 - ## Util ## (utility functions)
 - ## Database ## (functions that interact with the sqlite database)
 - ## Setup ## (routine for setting up the database)
 - ## Loop ## (main program)
 - ## TextResources ## (functions that print text)
 - ## Entry Point ## (main function)
*/

/*
##########
## Util ##
##########
*/

typedef struct {
    int month;
    int year;
} Payday;

void doNothing() {
}

bool fileExists(const char *filename) {
    struct stat buffer;
    return stat (filename, &buffer) == 0;
}

bool isBlankOrNull(const char* c) {
    bool res = true;
    if (c != NULL) {
        while (*c) {
           if (!isspace(*c)) {
               res = false;
               break;
           }
           c++;
        }
    }
    return res;
}

char * input(void (*printInfo)()) {
    printInfo();
    printf(" > ");
    char *line = NULL;
    size_t len = 0;
    getline(&line, &len, stdin);
    line[strlen(line) - 1] = '\0';
    return line;
}

char * inputWithDefault(void (*printInfo)(), const char* standard) {
    printInfo();
    printf(" [default: ");
    printf(standard);
    printf("]");
    return input(doNothing);
}

struct tm * now() {
    time_t now;
    time(&now);
    return localtime(&now);
}

int currentMonth() {
    return now()->tm_mon + 1;
}

int currentYear() {
    return now()->tm_year + 1900;
}

float toRoundedFloat(const char *amount) {
    return roundf(atof(amount) * 100) / 100;
}

/*
##############
## Database ##
##############
*/

void connect() {
    if (!db) {
        sqlite3_open(DB_FILE, &db);
    }
}

void disconnect() {
    sqlite3_close(db);
}

void executeStatement(const char *sql) {
    char *err = 0;
    sqlite3_exec(db, sql, 0, 0, &err);
    sqlite3_free(err);
}

void createTables() {
    executeStatement(" CREATE TABLE ledger ( "\
                        "description TEXT, "\
                        "amount REAL NOT NULL, "\
                        "auto_income INTEGER NOT NULL, "\
                        "created_by TEXT, "\
                        "created_at TIMESTAMP NOT NULL, "\
                        "modified_at TIMESTAMP) ");
    executeStatement(" CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL) ");
}

void insertConfiguration(const char *key, const char *value) {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " INSERT INTO configuration (k, v) VALUES (?, ?)", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, key, strlen(key), NULL);
    sqlite3_bind_text(stmt, 2, value, strlen(value), NULL);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
}

void insertIntoLedger(const char *description, const float amount) {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 0, datetime('now'), 'C GNU89 Edition') ", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, description, strlen(description), NULL);
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

char * formatCurrentRow(sqlite3_stmt *stmt) {
    char currentRow[300] = "        ";
    const char *isoDatetime = sqlite3_column_text(stmt, 0);
    const float amount = sqlite3_column_double(stmt, 1);
    char amountStr[20];
    sprintf(amountStr, "%.2f", amount);
    const char *description = sqlite3_column_text(stmt, 2);
    strcat(currentRow, isoDatetime);
    strcat(currentRow, "\t");
    strcat(currentRow, amountStr);
    strcat(currentRow, "\t");
    strcat(currentRow, description);
    strcat(currentRow, "\n");
    return strdup(currentRow);
}

char * transactions() {
    char allRows[9000] = "";
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30 ", -1, &stmt, 0);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        char *currentRow = formatCurrentRow(stmt);
        strcat(allRows, currentRow);
        free(currentRow);
    }
    sqlite3_finalize(stmt);
    return strdup(allRows);
}

char * incomeDescription() {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, CONF_INCOME_DESCRIPTION, strlen(CONF_INCOME_DESCRIPTION), NULL);
    sqlite3_step(stmt);
    const char *description = sqlite3_column_text(stmt, 0);
    char *result = strdup(description);
    sqlite3_finalize(stmt);
    return result;
}

float incomeAmount() {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, CONF_INCOME_AMOUNT, strlen(CONF_INCOME_AMOUNT), NULL);
    sqlite3_step(stmt);
    const char *amountStr = sqlite3_column_text(stmt, 0);
    float amount = toRoundedFloat(amountStr);
    sqlite3_finalize(stmt);
    return amount;
}

float overdraft() {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, CONF_OVERDRAFT, strlen(CONF_OVERDRAFT), NULL);
    sqlite3_step(stmt);
    const char *overdraftStr = sqlite3_column_text(stmt, 0);
    float overdraft = toRoundedFloat(overdraftStr);
    sqlite3_finalize(stmt);
    return overdraft;
}

bool isExpenseAcceptable(const float expense) {
    return balance() + overdraft() - expense >= 0;
}

void insertAutoIncome(const Payday payday) {
    char *description = incomeDescription();
    int requiredSize = 9;
    char dateInfo[requiredSize];
    snprintf(dateInfo, requiredSize, " %02d/%d", payday.month, payday.year);
    strcat(description, dateInfo);
    float amount = incomeAmount();
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 1, datetime('now'), 'C GNU89 Edition') ", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, description, strlen(description), NULL);
    sqlite3_bind_double(stmt, 2, amount);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    free(description);
}

bool hasAutoIncomeForMonth(const Payday payday) {
    const int requiredSize = 10;
    char dateInfo[requiredSize];
    snprintf(dateInfo, requiredSize, "%% %02d/%d", payday.month, payday.year);
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

void insertAllDueIncomes() {
    Payday paydays[10 * 12];
    Payday referencePayday;
    referencePayday.month = currentMonth();
    referencePayday.year = currentYear();
    int inc = -1;
    while(!hasAutoIncomeForMonth(referencePayday)) {
        Payday currentPayday;
        currentPayday.month = referencePayday.month;
        currentPayday.year = referencePayday.year;
        paydays[++inc] = currentPayday;
        if (referencePayday.month > 1) {
            referencePayday.month -= 1;
        } else {
            referencePayday.year -= 1;
            referencePayday.month = 12;
        }
    }
    int i;
    for (i=inc; i>=0; i--) {
        insertAutoIncome(paydays[i]);
    }
}

/*
###########
## Setup ##
###########
*/

void setup() {
    const char descriptionDefault[] = "pocket money";
    const char amountDefault[] = "100";
    const char overdraftDefault[] = "200";
    char *descriptionInput = inputWithDefault(printSetupDescription, descriptionDefault);
    insertConfiguration(CONF_INCOME_DESCRIPTION, isBlankOrNull(descriptionInput) ? descriptionDefault : descriptionInput);
    free(descriptionInput);
    char *amountInput = inputWithDefault(printSetupIncome, amountDefault);
    insertConfiguration(CONF_INCOME_AMOUNT, isBlankOrNull(amountInput) ? amountDefault : amountInput);
    free(amountInput);
    char *overdraftInput = inputWithDefault(printSetupOverdraft, overdraftDefault);
    insertConfiguration(CONF_OVERDRAFT, isBlankOrNull(overdraftInput) ? overdraftDefault : overdraftInput);
    free(overdraftInput);
    Payday payday;
    payday.month = currentMonth();
    payday.year = currentYear();
    insertAutoIncome(payday);
}

void initialize() {
    printSetupPreDatabase();
    connect();
    createTables();
    printSetupPostDatabase();
    setup();
    printSetupComplete();
}

void setupOnFirstRun() {
    if (!fileExists(DB_FILE)) {
        initialize();
    }
}

/*
##########
## Loop ##
##########
*/

void addToLedger(const int signum, void (*printSuccessMessage)()) {
    char *description = input(printEnterDescription);
    char *amountStr = input(printEnterAmount);
    float amount = toRoundedFloat(amountStr);
    if (amount > 0) {
        if (signum == 1 || isExpenseAcceptable(amount)) {
            insertIntoLedger(description, amount * signum);
            printSuccessMessage();
            printCurrentBalance(balance());
        } else {
            printErrorTooExpensive();
        }
    } else if (amount < 0) {
        printErrorNegativeAmount();
    } else {
        printErrorZeroOrInvalidAmount();
    }
    free(description);
    free(amountStr);
}

void handleAdd() {
    addToLedger(1, printIncomeBooked);
}

void handleSub() {
    addToLedger(-1, printExpenseBooked);
}

void handleShow() {
    printCurrentBalance(balance());
    printFormattedBalance(transactions());
}

void handleHelp() {
    printHelp();
}

void handleInfo() {
    printInfo();
}

void omg() {
    printErrorOmg();
}

void loop() {
    connect();
    insertAllDueIncomes();
    printCurrentBalance(balance());
    printInfo();
    bool looping = true;
    while(looping) {
        char *inp = input(printEnterInput);
        if (strlen(inp) <= 1) {
            if (isBlankOrNull(inp)) {
                handleInfo();
            } else if (inp[0] == KEY_ADD) {
                handleAdd();
            } else if (inp[0] == KEY_SUB) {
                handleSub();
            } else if (inp[0] == KEY_SHOW) {
                handleShow();
            } else if (inp[0] == KEY_HELP) {
                handleHelp();
            } else if (inp[0] == KEY_QUIT) {
                looping = false;
            } else {
                handleInfo();
            }
        } else {
            omg();
        }
    }
    disconnect();
    printBye();
}

/*
###################
## TextResources ##
###################
*/

void printBanner() {
    printf("\n"\
        "\t _                                 _   _\n"\
        "\t(_|   |_/o                        | | | |\n"\
        "\t  |   |      ,_  _|_         __,  | | | |  _ _|_\n"\
        "\t  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |\n"\
        "\t   \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/\n\n"\
        "\tC GNU89 Edition\n\n\n");
}

void printInfo() {
    printf("\n"\
        "\tCommands:\n"\
        "\t- press plus (+) to add an irregular income\n"\
        "\t- press minus (-) to add an expense\n"\
        "\t- press equals (=) to show balance and last transactions\n"\
        "\t- press question mark (?) for even more info about this program\n"\
        "\t- press colon (:) to exit\n\n");
}

void printHelp() {
    printf("\n"\
        "\tVirtuallet is a tool to act as your virtual wallet. Wow...\n"\
        "\tVirtuallet is accessible via terminal and uses a Sqlite database to store all its data.\n"\
        "\tOn first start Virtuallet will be configured and requires some input\n"\
        "\tbut you already know that unless you are currently studying the source code.\n"\
        "\n"\
        "\tVirtuallet follows two important design principles:\n"\
        "\n"\
        "\t- shit in shit out\n"\
        "\t- UTFSB (Use The F**king Sqlite Browser)\n"\
        "\n"\
        "\tAs a consequence everything in the database is considered valid.\n"\
        "\tProgram behaviour is unspecified for any database content being invalid. Ouch...\n"\
        "\n"\
        "\tAs its primary feature Virtuallet will auto-add the configured income on start up\n"\
        "\tfor all days in the past since the last registered regular income.\n"\
        "\tSo if you have specified a monthly income and haven't run Virtuallet for three months\n"\
        "\tit will auto-create three regular incomes when you boot it the next time if you like it or not.\n"\
        "\n"\
        "\tVirtuallet will also allow you to add irregular incomes and expenses manually.\n"\
        "\tIt can also display the current balance and the 30 most recent transactions.\n"\
        "\n"\
        "\tThe configured overdraft will be considered if an expense is registered.\n"\
        "\tFor instance if your overdraft equals the default value of 200\n"\
        "\tyou won't be able to add an expense if the balance would be less than -200 afterwards.\n"\
        "\n"\
        "\tVirtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser\n"\
        "\tto view and even edit the database. When making updates please remember the shit in shit out principle.\n"\
        "\n"\
        "\tAs a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.\n\n");
}

void printSetupPreDatabase() {
    printf("\tDatabase file not found.\n"\
           "\tDatabase will be initialized. This may take a while... NOT.\n\n");
}

void printSetupPostDatabase() {
    printf("\tDatabase initialized.\n"\
           "\tAre you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.\n"\
           "\tPress enter to accept the default or input something else. There is no validation\n"\
           "\tbecause I know you will not make a mistake. No second chances. If you f**k up,\n"\
           "\tyou will have to either delete the database file or edit it using a sqlite database browser.\n\n");
}

void printSetupComplete() {
    printf("setup complete, have fun\n");
}

void printErrorOmg() {
    printf("OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that\n");
}

void printErrorZeroOrInvalidAmount() {
    printf("amount is zero or invalid -> action aborted\n");
}

void printErrorNegativeAmount() {
    printf("amount must be positive -> action aborted\n");
}

void printIncomeBooked() {
    printf("income booked\n");
}

void printExpenseBooked() {
    printf("expense booked successfully\n");
}

void printErrorTooExpensive() {
    printf("sorry, too expensive -> action aborted\n");
}

void printEnterInput() {
    printf("input");
}

void printEnterDescription() {
    printf("description (optional)");
}

void printEnterAmount() {
    printf("amount");
}

void printBye() {
    printf("see ya\n");
}

void printCurrentBalance(const float value) {
    printf("\n\tcurrent balance: %.2f\n\n", value);
}

void printFormattedBalance(const char *formattedBalance) {
    printf("\tlast transactions (up to 30)\n");
    printf("\t----------------------------\n");
    printf(formattedBalance);
    printf("\n");
}

void printSetupDescription() {
    printf("enter description for regular income");
}

void printSetupIncome() {
    printf("enter regular income");
}

void printSetupOverdraft() {
    printf("enter overdraft");
}

/*
#################
## Entry Point ##
#################
*/

int main() {
	printBanner();
	setupOnFirstRun();
	loop();
	return 0;
}
