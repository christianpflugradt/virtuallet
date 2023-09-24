#import <Foundation/Foundation.h>
#import <sqlite3.h>

NSString *const DB_FILE = @"../db_virtuallet.db";
NSString *const CONF_INCOME_DESCRIPTION = @"income_description";
NSString *const CONF_INCOME_AMOUNT = @"income_amount";
NSString *const CONF_OVERDRAFT = @"overdraft";
NSString *const TAB = @"<TAB>";

@interface TextResources:NSObject
+ (NSString*)banner;
+ (NSString*)info;
+ (NSString*)help;
+ (NSString*)setupPreDatabase;
+ (NSString*)setupPostDatabase;
+ (NSString*)errorZeroOrInvalidAmount;
+ (NSString*)errorNegativeAmount;
+ (NSString*)incomeBooked;
+ (NSString*)expenseBooked;
+ (NSString*)errorTooExpensive;
+ (NSString*)errorOmg;
+ (NSString*)enterInput;
+ (NSString*)enterDescription;
+ (NSString*)enterAmount;
+ (NSString*)setupComplete;
+ (NSString*)bye;
+ (NSString*)currentBalance:(NSNumber*)balance;
+ (NSString*)formattedBalance:(NSNumber*)balance withTransactions:(NSString*)transactions;
+ (NSString*)setupDescription;
+ (NSString*)setupIncome;
+ (NSString*)setupOverdraft;
+ (NSString*)setupTemplateWithDescription:(NSString*)description andStandard:(NSString*)standard;
@end

@interface Util:NSObject
+ (void)print:(NSString*)str;
+ (void)println:(NSString*)str;
+ (NSString*)input:(NSString*)withPrefix;
+ (NSString*)readConfigInputWithDescription:(NSString*)description andStandard:(NSString*)standard;
+ (NSInteger)currentMonth;
+ (NSInteger)currentYear;
+ (NSNumber*)numberValueOf:(NSString*)str;
@end

@implementation Util

+ (void)print:(NSString*)str {
    fprintf(stdout, "%s", [[str stringByReplacingOccurrencesOfString:TAB withString:@"\t"] UTF8String]);
}

+ (void)println:(NSString*)str {
    [Util print:[NSString stringWithFormat:@"%@\n", str]];
}

+ (NSString*)input:(NSString*)withPrefix {
    [Util print:withPrefix];
    char *line = NULL;
    size_t len = 0;
    getline(&line, &len, stdin);
    line[strlen(line) - 1] = '\0';
    return @(line);
}

+ (NSString*)readConfigInputWithDescription:(NSString*)description andStandard:(NSString*)standard {
    NSString* userInput = [[Util input:[TextResources setupTemplateWithDescription:description andStandard:standard]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [userInput length] == 0 ? standard : userInput;
}

+ (NSInteger)dateField:(NSString*)format {
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:format];
    return [[dateFormatter stringFromDate:date] integerValue];

}

+ (NSInteger)currentMonth {
    return [Util dateField:@"MM"];
}

+ (NSInteger)currentYear {
    return [Util dateField:@"yyyy"];
}

+ (NSNumber*)numberValueOf:(NSString*)str {
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    return [formatter numberFromString:str];
}

@end

@interface Database:NSObject {
    sqlite3 *db;
}
- (void)connect;
- (void)disconnect;
- (void)createTables;
- (void)insertConfigurationWithKey:(NSString*)key andValue:(NSString*)value;
- (void)insertIntoLedgerWithDescription:(NSString*)description andAmount:(NSNumber*)amount;
- (NSNumber*)balance;
- (NSString*)transactions;
- (NSString*)incomeDescription;
- (NSNumber*)incomeAmount;
- (NSNumber*)overdraft;
- (BOOL)isExpenseAcceptable:(NSNumber*)expense;
- (void)insertAutoIncomeWithMonth:(NSInteger)month andYear:(NSInteger)year;
- (void)insertAllDueIncomes;
@end

@implementation Database

- (void)connect {
    if (!db) {
        sqlite3_open([DB_FILE UTF8String], &db);
    }
}

- (void)disconnect {
    sqlite3_close(db);
}

- (void)createTables {
    char *err = 0;
    sqlite3_exec(db, "\
        CREATE TABLE ledger ( \
        description TEXT, \
        amount REAL NOT NULL, \
        auto_income INTEGER NOT NULL, \
        created_by TEXT, \
        created_at TIMESTAMP NOT NULL, \
        modified_at TIMESTAMP) ", 0, 0, &err);
    sqlite3_exec(db, " CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL) ", 0, 0, &err);
    sqlite3_free(err);
}

- (void)insertConfigurationWithKey:(NSString*)key andValue:(NSString*)value {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " INSERT INTO configuration (k, v) VALUES (?, ?)", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, [key UTF8String], [key length], NULL);
    sqlite3_bind_text(stmt, 2, [value UTF8String], [value length], NULL);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
}

- (void)insertIntoLedgerWithDescription:(NSString*)description andAmount:(NSNumber*)amount {
       sqlite3_stmt *stmt;
       sqlite3_prepare_v2(db, " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 0, datetime('now'), 'GNUstep 1.29 Edition') ", -1, &stmt, 0);
       sqlite3_bind_text(stmt, 1, [description UTF8String], [description length], NULL);
       sqlite3_bind_double(stmt, 2, [amount floatValue]);
       sqlite3_step(stmt);
       sqlite3_finalize(stmt);
}

- (NSNumber*)balance {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger ", -1, &stmt, 0);
    sqlite3_step(stmt);
    NSNumber* balance = @(sqlite3_column_double(stmt, 0));
    sqlite3_finalize(stmt);
    return balance;
}

- (NSString*)transactions {
    NSMutableArray* lines = [NSMutableArray array];
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30 ", -1, &stmt, 0);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char* createdAt = sqlite3_column_text(stmt, 0);
        const float amount = sqlite3_column_double(stmt, 1);
        const unsigned char* description = sqlite3_column_text(stmt, 2);
        NSString* line = [NSString stringWithFormat:@"\t%@\t%.2f\t%@",
            [NSString stringWithUTF8String:(char*)createdAt],
            amount,
            [NSString stringWithUTF8String:(char*)description]];
        [lines addObject:line];
    }
    sqlite3_finalize(stmt);
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString*)incomeDescription {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, [CONF_INCOME_DESCRIPTION UTF8String], [CONF_INCOME_DESCRIPTION length], NULL);
    sqlite3_step(stmt);
    const unsigned char* description = sqlite3_column_text(stmt, 0);
    NSString* result = [NSString stringWithUTF8String:(char*)description];
    sqlite3_finalize(stmt);
    return result;
}

- (NSNumber*)incomeAmount {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, [CONF_INCOME_AMOUNT UTF8String], [CONF_INCOME_AMOUNT length], NULL);
    sqlite3_step(stmt);
    const unsigned char* amount = sqlite3_column_text(stmt, 0);
    NSNumber* result = @([[NSString stringWithUTF8String:(char*)amount] floatValue]);
    sqlite3_finalize(stmt);
    return result;
}

- (NSNumber*)overdraft {
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT v FROM configuration WHERE k = ?", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, [CONF_OVERDRAFT UTF8String], [CONF_OVERDRAFT length], NULL);
    sqlite3_step(stmt);
    const unsigned char* overdraft = sqlite3_column_text(stmt, 0);
    NSNumber* result = @([[NSString stringWithUTF8String:(char*)overdraft] floatValue]);
    sqlite3_finalize(stmt);
    return result;
}

- (BOOL)isExpenseAcceptable:(NSNumber*)expense {
    return [[self balance] floatValue] + [[self overdraft] floatValue] - [expense floatValue] >= 0;
}

- (void)insertAutoIncomeWithMonth:(NSInteger)month andYear:(NSInteger)year {
       NSString* description = [NSString stringWithFormat:@"%@ %02ld/%ld", [self incomeDescription], month, year];
       NSNumber* amount = [self incomeAmount];
       sqlite3_stmt *stmt;
       sqlite3_prepare_v2(db, " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 1, datetime('now'), 'GNUstep 1.29 Edition') ", -1, &stmt, 0);
       sqlite3_bind_text(stmt, 1, [description UTF8String], [description length], NULL);
       sqlite3_bind_double(stmt, 2, [amount floatValue]);
       sqlite3_step(stmt);
       sqlite3_finalize(stmt);
}

- (BOOL)hasAutoIncomeForMonth:(NSInteger)month andYear:(NSInteger)year {
    NSString* description = [NSString stringWithFormat:@"%% %02ld/%ld", month, year];
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, " SELECT EXISTS( "\
                " SELECT auto_income FROM ledger "\
                " WHERE auto_income = 1 "\
                " AND description LIKE ? )", -1, &stmt, 0);
    sqlite3_bind_text(stmt, 1, [description UTF8String], [description length], NULL);
    sqlite3_step(stmt);
    int exists = sqlite3_column_int(stmt, 0);
    sqlite3_finalize(stmt);
    return exists == 1;
}

typedef struct {
    NSInteger month;
    NSInteger year;
} DueDate;

- (void)insertAllDueIncomes {
    DueDate dueDate;
    dueDate.month = [Util currentMonth];
    dueDate.year = [Util currentYear];
    NSMutableArray* dueDates = [NSMutableArray array];
    while (![self hasAutoIncomeForMonth:dueDate.month andYear:dueDate.year]) {
        DueDate next;
        next.month = dueDate.month;
        next.year = dueDate.year;
        [dueDates addObject:[NSValue value:&next withObjCType:@encode(DueDate)]];
        dueDate.month = dueDate.month == 1 ? 12 : dueDate.month - 1;
        dueDate.year = dueDate.month == 12 ? dueDate.year - 1 : dueDate.year;
    }
    NSEnumerator *enumerator = [dueDates reverseObjectEnumerator];
    for (id element in enumerator) {
        DueDate dueDate;
        [element getValue:&dueDate];
        [self insertAutoIncomeWithMonth:dueDate.month andYear:dueDate.year];
    }
}

@end

@interface Setup:NSObject {
    Database* database;
}
- (id)initWithDatabase : (Database*)database;
- (void)setupOnFirstRun;
@end

@implementation Setup

-(id)initWithDatabase : (Database*)givenDatabase {
    database = givenDatabase;
    return self;
}

- (void)setupOnFirstRun {
    if (![[NSFileManager defaultManager] fileExistsAtPath: DB_FILE]) {
        [self initialize];
    }
}

- (void)initialize {
    [Util print:[TextResources setupPreDatabase]];
    [database connect];
    [database createTables];
    [Util print:[TextResources setupPostDatabase]];
    [self setup];
    [Util println:[TextResources setupComplete]];
}

- (void)setup {
    NSString* incomeDescription = [Util readConfigInputWithDescription:[TextResources setupDescription] andStandard:@"pocket money"];
    NSString* incomeAmount = [Util readConfigInputWithDescription:[TextResources setupIncome] andStandard:@"100"];
    NSString* overdraft = [Util readConfigInputWithDescription:[TextResources setupOverdraft] andStandard:@"200"];
    [database insertConfigurationWithKey:CONF_INCOME_DESCRIPTION andValue:incomeDescription];
    [database insertConfigurationWithKey:CONF_INCOME_AMOUNT andValue:incomeAmount];
    [database insertConfigurationWithKey:CONF_OVERDRAFT andValue:overdraft];
    [database insertAutoIncomeWithMonth:[Util currentMonth] andYear:[Util currentYear]];
}

@end

@interface Loop:NSObject {
    Database* database;
}
- (id)initWithDatabase : (Database*)database;
- (void)loop;
@end

@implementation Loop

static char const KEY_ADD = '+';
static char const KEY_SUB = '-';
static char const KEY_SHOW = '=';
static char const KEY_HELP = '?';
static char const KEY_QUIT = ':';

-(id)initWithDatabase : (Database*)givenDatabase {
    database = givenDatabase;
    return self;
}

- (void)loop {
    [database connect];
    [database insertAllDueIncomes];
    [Util print:[TextResources currentBalance:[database balance]]];
    [self handleInfo];
    BOOL looping = YES;
    while (looping) {
        NSString* input = [Util input:[TextResources enterInput]];
        if ([input length] == 1) {
            char inputChar = [input characterAtIndex:0];
            switch(inputChar) {
                case KEY_ADD:
                    [self handleAdd];
                    break;
                case KEY_SUB:
                    [self handleSub];
                    break;
                case KEY_SHOW:
                    [self handleShow];
                    break;
                case KEY_HELP:
                    [self handleHelp];
                    break;
                case KEY_QUIT:
                    looping = NO;
                    break;
                default:
                    [self handleInfo];
                    break;
            }
        } else if ([input length] > 1 && ([input characterAtIndex:0] == KEY_ADD || [input characterAtIndex:0] == KEY_SUB)) {
            [self omg];
        } else {
            [self handleInfo];
        }
    }
    [database disconnect];
    [Util println:[TextResources bye]];
}

- (void)handleAdd {
    [self addToLedgerWithSignum:1 andSuccessMessage:[TextResources incomeBooked]];
}

- (void)handleSub {
    [self addToLedgerWithSignum:-1 andSuccessMessage:[TextResources expenseBooked]];
}

- (void)addToLedgerWithSignum:(NSInteger)signum andSuccessMessage:(NSString*)successMessage {
    NSString* description = [Util input:[TextResources enterDescription]];
    NSNumber* amount = [Util numberValueOf:[Util input:[TextResources enterAmount]]];
    if (amount != nil && [amount floatValue] > 0.0) {
        if ((long)signum == 1 || [database isExpenseAcceptable:amount]) {
            [database insertIntoLedgerWithDescription:description andAmount:amount];
            [Util println:successMessage];
            [Util println:[TextResources currentBalance:[database balance]]];
        } else {
            [Util println:[TextResources errorTooExpensive]];
        }
    } else if (amount != nil && [amount floatValue] < 0.0) {
        [Util println:[TextResources errorNegativeAmount]];
    } else {
        [Util println:[TextResources errorZeroOrInvalidAmount]];
    }
}

- (void)omg {
    [Util println:[TextResources errorOmg]];
}

- (void)handleInfo {
    [Util print:[TextResources info]];
}

- (void)handleHelp {
    [Util print:[TextResources help]];
}

- (void)handleShow {
   [Util print:[TextResources formattedBalance:[database balance] withTransactions:[database transactions]]];
}

@end

@implementation TextResources

+ (NSString*)banner {
    return @"\n\
<TAB> _                                 _   _\n\
<TAB>(_|   |_/o                        | | | |\n\
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_\n\
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |\n\
<TAB>   \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/\n\
\n\
<TAB>GNUstep 1.29 Edition\n\
\n\
\n\
";
}

+ (NSString*)info {
    return @"\n\
<TAB>Commands:\n\
<TAB>- press plus (+) to add an irregular income\n\
<TAB>- press minus (-) to add an expense\n\
<TAB>- press equals (=) to show balance and last transactions\n\
<TAB>- press question mark (?) for even more info about this program\n\
<TAB>- press colon (:) to exit\n\
\n\
";
}

+ (NSString*)help {
    return @"\n\
<TAB>Virtuallet is a tool to act as your virtual wallet. Wow...\n\
<TAB>Virtuallet is accessible via terminal and uses a Sqlite database to store all its data.\n\
<TAB>On first start Virtuallet will be configured and requires some input\n\
<TAB>but you already know that unless you are currently studying the source code.\n\
\n\
<TAB>Virtuallet follows two important design principles:\n\
\n\
<TAB>- shit in shit out\n\
<TAB>- UTFSB (Use The F**king Sqlite Browser)\n\
\n\
<TAB>As a consequence everything in the database is considered valid.\n\
<TAB>Program behaviour is unspecified for any database content being invalid. Ouch...\n\
\n\
<TAB>As its primary feature Virtuallet will auto-add the configured income on start up\n\
<TAB>for all days in the past since the last registered regular income.\n\
<TAB>So if you have specified a monthly income and haven't run Virtuallet for three months\n\
<TAB>it will auto-create three regular incomes when you boot it the next time if you like it or not.\n\
\n\
<TAB>Virtuallet will also allow you to add irregular incomes and expenses manually.\n\
<TAB>It can also display the current balance and the 30 most recent transactions.\n\
\n\
<TAB>The configured overdraft will be considered if an expense is registered.\n\
<TAB>For instance if your overdraft equals the default value of 200\n\
<TAB>you won't be able to add an expense if the balance would be less than -200 afterwards.\n\
\n\
<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser\n\
<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.\n\
\n\
<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.\n\
\n\
";
}

+ (NSString*)setupPreDatabase {
    return @"\n\
<TAB>Database file not found.\n\
<TAB>Database will be initialized. This may take a while... NOT.\n\
";
}

+ (NSString*)setupPostDatabase {
    return @"\n\
<TAB>Database initialized.\n\
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.\n\
<TAB>Press enter to accept the default or input something else. There is no validation\n\
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,\n\
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.\n\
\n\
";
}

+ (NSString*)errorZeroOrInvalidAmount {
    return @"amount is zero or invalid -> action aborted";
}

+ (NSString*)errorNegativeAmount {
return @"amount must be positive -> action aborted";
}

+ (NSString*)incomeBooked {
    return @"income booked";
}

+ (NSString*)expenseBooked {
    return @"expense booked successfully";
}

+ (NSString*)errorTooExpensive {
    return @"sorry, too expensive -> action aborted";
}

+ (NSString*)errorOmg {
    return @"OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that";
}

+ (NSString*)enterInput {
    return @"input > ";
}

+ (NSString*)enterDescription {
    return @"description (optional) > ";
}

+ (NSString*)enterAmount {
    return @"amount > ";
}

+ (NSString*)setupComplete {
    return @"setup complete, have fun";
}

+ (NSString*)bye {
    return @"see ya";
}

+ (NSString*)currentBalance:(NSNumber*)balance {
    return [NSString stringWithFormat:@"\n\
<TAB>current balance: %.2f\n\
", [balance floatValue]];
}

+ (NSString*)formattedBalance:(NSNumber*)balance withTransactions:(NSString*)transactions {
    return [NSString stringWithFormat:@"%@\n\
<TAB>last transactions (up to 30)\n\
<TAB>----------------------------\n\
%@\n\n\
", [TextResources currentBalance:balance], transactions];
}

+ (NSString*)setupDescription {
    return @"enter description for regular income";
}

+ (NSString*)setupIncome {
    return @"enter regular income";
}

+ (NSString*)setupOverdraft {
    return @"enter overdraft";
}

+ (NSString*)setupTemplateWithDescription:(NSString*)description andStandard:(NSString*)standard {
    return [NSString stringWithFormat:@"%@ [default: %@] > ", description, standard];
}

@end

int main (int argc, const char * argv[]) {
   NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
   Database* database = [[Database alloc] init];
   Setup* setup = [[Setup alloc] initWithDatabase:database];
   Loop* loop = [[Loop alloc] initWithDatabase:database];
   [Util print:[TextResources banner]];
   [setup setupOnFirstRun];
   [loop loop];
   [pool drain];
   return 0;
}
