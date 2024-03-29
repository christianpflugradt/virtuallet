#INCLUDE "sqlite3.bi"
#include "vbcompat.bi"

CONST DB_FILE = "../db_virtuallet.db"
CONST CONF_INCOME_DESCRIPTION = "income_description"
CONST CONF_INCOME_AMOUNT = "income_amount"
CONST CONF_OVERDRAFT = "overdraft"
CONST TABULATOR = "<TAB>"

NAMESPACE TEXTRESOURCES
    DECLARE FUNCTION BANNER AS STRING
    DECLARE FUNCTION INFO AS STRING
    DECLARE FUNCTION HELP AS STRING
    DECLARE FUNCTION SETUP_PRE_DATABASE AS STRING
    DECLARE FUNCTION SETUP_POST_DATABASE AS STRING
    DECLARE FUNCTION ERROR_ZERO_OR_INVALID_AMOUNT AS STRING
    DECLARE FUNCTION ERROR_NEGATIVE_AMOUNT AS STRING
    DECLARE FUNCTION INCOME_BOOKED AS STRING
    DECLARE FUNCTION EXPENSE_BOOKED AS STRING
    DECLARE FUNCTION ERROR_TOO_EXPENSIVE AS STRING
    DECLARE FUNCTION ERROR_OMG AS STRING
    DECLARE FUNCTION ENTER_INPUT AS STRING
    DECLARE FUNCTION ENTER_DESCRIPTION AS STRING
    DECLARE FUNCTION ENTER_AMOUNT AS STRING
    DECLARE FUNCTION SETUP_COMPLETE AS STRING
    DECLARE FUNCTION BYE AS STRING
    DECLARE FUNCTION CURRENT_BALANCE(BALANCE AS DOUBLE) AS STRING
    DECLARE FUNCTION FORMATTED_BALANCE(BALANCE AS DOUBLE, FORMATTED_LAST_TRANSACTIONS AS STRING) AS STRING
    DECLARE FUNCTION SETUP_DESCRIPTION AS STRING
    DECLARE FUNCTION SETUP_INCOME AS STRING
    DECLARE FUNCTION SETUP_OVERDRAFT AS STRING
    DECLARE FUNCTION SETUP_TEMPLATE(DESCRIPTION AS STRING, STANDARD AS STRING) AS STRING
END NAMESPACE

NAMESPACE UTIL

    FUNCTION REPLACEALL(MYSTR AS CONST STRING, ORIGINAL AS CONST STRING, REPLACEMENT AS CONST STRING) AS STRING
        DIM ORGSTR AS STRING = MYSTR
        DIM NEWSTR AS STRING = ""
        DIM POSITION AS INTEGER = INSTR(ORGSTR, ORIGINAL)
        DO UNTIL POSITION = 0
            NEWSTR = NEWSTR & LEFT(ORGSTR, POSITION - 1) & REPLACEMENT
            ORGSTR = MID(ORGSTR, POSITION + LEN(ORIGINAL))
            POSITION = INSTR(ORGSTR, ORIGINAL)
        LOOP
        RETURN NEWSTR & ORGSTR
    END FUNCTION

    SUB PRNT(MYSTR AS CONST STRING)
        PRINT UTIL.REPLACEALL(MYSTR, TABULATOR, !"\t");
    END SUB

    SUB PRNTLN(MYSTR AS CONST STRING)
        UTIL.PRNT MYSTR & !"\n"
    END SUB

    FUNCTION GETINPUT(PREFIX AS STRING) AS STRING
        DIM USERINPUT AS STRING
        UTIL.PRNT PREFIX
        INPUT "", USERINPUT
        RETURN USERINPUT
    END FUNCTION

    FUNCTION READ_CONFIG_INPUT(DESCRIPTION AS STRING, STANDARD AS STRING) AS STRING
        DIM USERINPUT AS STRING = UTIL.GETINPUT(TEXTRESOURCES.SETUP_TEMPLATE(DESCRIPTION, STANDARD))
        IF LEN(USERINPUT) > 0 THEN RETURN USERINPUT ELSE RETURN STANDARD
    END FUNCTION

END NAMESPACE

TYPE DATABASE
    DECLARE SUB CONNECT
    DECLARE SUB DISCONNECT
    DECLARE SUB CREATE_TABLES
    DECLARE SUB INSERT_CONFIGURATION(KEY AS STRING, VALUE AS STRING)
    DECLARE SUB INSERT_INTO_LEDGER(DESCRIPTION AS STRING, AMOUNT AS DOUBLE)
    DECLARE FUNCTION BALANCE AS DOUBLE
    DECLARE FUNCTION TRANSACTIONS AS STRING
    DECLARE FUNCTION INCOME_DESCRIPTION AS STRING
    DECLARE FUNCTION INCOME_AMOUNT AS DOUBLE
    DECLARE FUNCTION OVERDRAFT AS DOUBLE
    DECLARE FUNCTION IS_EXPENSE_ACCEPTABLE(EXPENSE AS DOUBLE) AS BOOLEAN
    DECLARE SUB INSERT_AUTO_INCOME(MONTH AS INTEGER, YEAR AS INTEGER)
    DECLARE SUB INSERT_ALL_DUE_INCOMES
PRIVATE:
    DB AS SQLITE3 PTR = 0
    DECLARE FUNCTION HAS_AUTO_INCOME_FOR_MONTH(MONTH AS INTEGER, YEAR AS INTEGER) AS BOOLEAN
END TYPE

SUB DATABASE.CONNECT
    IF DB = 0 THEN
        SQLITE3_OPEN(DB_FILE, @THIS.DB)
    END IF
END SUB

SUB DATABASE.DISCONNECT
    SQLITE3_CLOSE(THIS.DB)
END SUB

SUB DATABASE.CREATE_TABLES
    SQLITE3_EXEC THIS.DB, _
        " CREATE TABLE ledger ( " _
            " description TEXT, " _
            " amount REAL NOT NULL, " _
            " auto_income INTEGER NOT NULL, " _
            " created_by TEXT, " _
            " created_at TIMESTAMP NOT NULL, " _
            " modified_at TIMESTAMP) ", _
        0, 0, 0
    SQLITE3_EXEC THIS.DB, " CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL) ", 0, 0, 0
END SUB

SUB DATABASE.INSERT_CONFIGURATION(KEY AS STRING, VALUE AS STRING)
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " INSERT INTO configuration (k, v) VALUES (?, ?) "
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_BIND_TEXT STMT, 1, KEY, -1, SQLITE_TRANSIENT
    SQLITE3_BIND_TEXT STMT, 2, VALUE, -1, SQLITE_TRANSIENT
    SQLITE3_STEP STMT
    SQLITE3_FINALIZE STMT
END SUB

SUB DATABASE.INSERT_INTO_LEDGER(DESCRIPTION AS STRING, AMOUNT AS DOUBLE)
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) " _
                                    " VALUES (?, ROUND(?, 2), 0, datetime('now'), 'FreeBASIC 1.10 Edition') "
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_BIND_TEXT STMT, 1, DESCRIPTION, -1, SQLITE_TRANSIENT
    SQLITE3_BIND_DOUBLE STMT, 2, AMOUNT
    SQLITE3_STEP STMT
    SQLITE3_FINALIZE STMT
END SUB

FUNCTION DATABASE.BALANCE AS DOUBLE
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger"
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_STEP STMT
    DIM AS STRING RESULT = *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 0))
    SQLITE3_FINALIZE STMT
    RETURN VAL(RESULT)
END FUNCTION

FUNCTION DATABASE.TRANSACTIONS AS STRING
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30 "
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    DIM AS STRING LINES = ""
    DO WHILE SQLITE3_STEP(STMT) = SQLITE_ROW
        LINES = LINES & TABULATOR & *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 0)) & _
            TABULATOR & *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 1)) & _
            TABULATOR & *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 2)) & !"\n"
    LOOP
    SQLITE3_FINALIZE STMT
    RETURN MID(LINES, 1, LEN(LINES) - 1)
END FUNCTION

FUNCTION DATABASE.INCOME_DESCRIPTION AS STRING
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " SELECT v FROM configuration WHERE k = ?"
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_BIND_TEXT STMT, 1, CONF_INCOME_DESCRIPTION, -1, SQLITE_TRANSIENT
    SQLITE3_STEP STMT
    DIM AS STRING RESULT = *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 0))
    SQLITE3_FINALIZE STMT
    RETURN RESULT
END FUNCTION

FUNCTION DATABASE.INCOME_AMOUNT AS DOUBLE
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " SELECT v FROM configuration WHERE k = ?"
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_BIND_TEXT STMT, 1, CONF_INCOME_AMOUNT, -1, SQLITE_TRANSIENT
    SQLITE3_STEP STMT
    DIM AS STRING RESULT = *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 0))
    SQLITE3_FINALIZE STMT
    RETURN VAL(RESULT)
END FUNCTION

FUNCTION DATABASE.OVERDRAFT AS DOUBLE
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " SELECT v FROM configuration WHERE k = ?"
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_BIND_TEXT STMT, 1, CONF_OVERDRAFT, -1, SQLITE_TRANSIENT
    SQLITE3_STEP STMT
    DIM AS STRING RESULT = *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 0))
    SQLITE3_FINALIZE STMT
    RETURN VAL(RESULT)
END FUNCTION

FUNCTION DATABASE.IS_EXPENSE_ACCEPTABLE(EXPENSE AS DOUBLE) AS BOOLEAN
    RETURN THIS.BALANCE() + THIS.OVERDRAFT() - EXPENSE
END FUNCTION

SUB DATABASE.INSERT_AUTO_INCOME(MONTH AS INTEGER, YEAR AS INTEGER)
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " INSERT INTO ledger (description, amount, auto_income, created_at, created_by) " _
                                    " VALUES (?, ROUND(?, 2), 1, datetime('now'), 'FreeBASIC 1.10 Edition') "
    DIM AS STRING DESCRIPTION = THIS.INCOME_DESCRIPTION() & " " & FORMAT(MONTH, "00") & "/" & YEAR
    DIM AS DOUBLE AMOUNT = THIS.INCOME_AMOUNT()
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_BIND_TEXT STMT, 1, DESCRIPTION, -1, SQLITE_TRANSIENT
    SQLITE3_BIND_DOUBLE STMT, 2, AMOUNT
    SQLITE3_STEP STMT
    SQLITE3_FINALIZE STMT
END SUB

FUNCTION DATABASE.HAS_AUTO_INCOME_FOR_MONTH(MONTH AS INTEGER, YEAR AS INTEGER) AS BOOLEAN
    DIM AS SQLITE3_STMT PTR STMT
    DIM AS STRING SQL = " SELECT EXISTS( " _
          " SELECT auto_income FROM ledger " _
          " WHERE auto_income = 1 " _
          " AND description LIKE ? )"
    DIM AS STRING DESCRIPTION = "%% " & FORMAT(MONTH, "00") & "/" & YEAR
    SQLITE3_PREPARE_V2 THIS.DB, SQL, LEN(SQL), @STMT, 0
    SQLITE3_BIND_TEXT STMT, 1, DESCRIPTION, -1, SQLITE_TRANSIENT
    SQLITE3_STEP STMT
    DIM AS STRING RESULT = *CAST(ZSTRING PTR, SQLITE3_COLUMN_TEXT(STMT, 0))
    SQLITE3_FINALIZE STMT
    RETURN VAL(RESULT) = 1
END FUNCTION

SUB DATABASE.INSERT_ALL_DUE_INCOMES
    TYPE DUEDATE
        AS INTEGER MONTH
        AS INTEGER YEAR
    END TYPE
    DIM MYDUEDATE AS DUEDATE = TYPE(MONTH(NOW()), YEAR(NOW()))
    DIM INDEX AS INTEGER = 0
    DIM SIZE AS INTEGER = 10
    REDIM DUEDATES(0 TO 10) AS DUEDATE
    DO UNTIL THIS.HAS_AUTO_INCOME_FOR_MONTH(MYDUEDATE.MONTH, MYDUEDATE.YEAR)
        DUEDATES(INDEX) = TYPE(MYDUEDATE.MONTH, MYDUEDATE.YEAR)
        INDEX += 1
        IF INDEX = SIZE THEN
            SIZE += 10
            REDIM PRESERVE DUEDATES(0 TO SIZE)
        ENDIF
        IF MYDUEDATE.MONTH = 1 THEN
            MYDUEDATE = TYPE(12, MYDUEDATE.YEAR - 1)
        ELSE
            MYDUEDATE = TYPE(MYDUEDATE.MONTH - 1, MYDUEDATE.YEAR)
        END IF
    LOOP
    FOR INDEX = UBOUND(DUEDATES) TO LBOUND(DUEDATES) STEP -1
        IF NOT DUEDATES(INDEX).MONTH = 0 THEN
            THIS.INSERT_AUTO_INCOME DUEDATES(INDEX).MONTH, DUEDATES(INDEX).YEAR
        END IF
    NEXT
END SUB

TYPE SETUP
    DECLARE CONSTRUCTOR(MYDATABASE AS DATABASE)
    DECLARE SUB SETUP_ON_FIRST_RUN
PRIVATE:
    MYDATABASE AS DATABASE
    DECLARE SUB INITIALIZE
    DECLARE SUB SETUP
END TYPE

CONSTRUCTOR SETUP(MYDATABASE AS DATABASE)
    THIS.MYDATABASE = MYDATABASE
END CONSTRUCTOR

SUB SETUP.SETUP_ON_FIRST_RUN
    IF NOT FILEEXISTS(DB_FILE) THEN
        THIS.INITIALIZE
    END IF
END SUB

SUB SETUP.INITIALIZE
    UTIL.PRNT TEXTRESOURCES.SETUP_PRE_DATABASE
    THIS.MYDATABASE.CONNECT
    THIS.MYDATABASE.CREATE_TABLES
    UTIL.PRNT TEXTRESOURCES.SETUP_POST_DATABASE
    THIS.SETUP
    UTIL.PRNTLN TEXTRESOURCES.SETUP_COMPLETE
END SUB

SUB SETUP.SETUP
    DIM INCOME_DESCRIPTION AS STRING = UTIL.READ_CONFIG_INPUT(TEXTRESOURCES.SETUP_DESCRIPTION, "pocket money")
    DIM INCOME_AMOUNT AS STRING = UTIL.READ_CONFIG_INPUT(TEXTRESOURCES.SETUP_INCOME, "100")
    DIM OVERDRAFT AS STRING = UTIL.READ_CONFIG_INPUT(TEXTRESOURCES.SETUP_OVERDRAFT, "200")
    THIS.MYDATABASE.INSERT_CONFIGURATION CONF_INCOME_DESCRIPTION, INCOME_DESCRIPTION
    THIS.MYDATABASE.INSERT_CONFIGURATION CONF_INCOME_AMOUNT, INCOME_AMOUNT
    THIS.MYDATABASE.INSERT_CONFIGURATION CONF_OVERDRAFT, OVERDRAFT
    THIS.MYDATABASE.INSERT_AUTO_INCOME MONTH(NOW), YEAR(NOW)
END SUB

TYPE LOOOP
    DECLARE CONSTRUCTOR(MYDATABASE AS DATABASE)
    DECLARE SUB LOOOP
PRIVATE:
    MYDATABASE AS DATABASE
    CONST KEY_ADD = "+"
    CONST KEY_SUB = "-"
    CONST KEY_SHOW = "="
    CONST KEY_HELP = "?"
    CONST KEY_QUIT = ":"
    DECLARE SUB HANDLE_ADD
    DECLARE SUB HANDLE_SUB
    DECLARE SUB ADD_TO_LEDGER(SIGNUM AS INTEGER, SUCCESS_MESSAGE AS STRING)
    DECLARE SUB OMG
    DECLARE SUB HANDLE_INFO
    DECLARE SUB HANDLE_HELP
    DECLARE SUB HANDLE_SHOW
END TYPE

CONSTRUCTOR LOOOP(MYDATABASE AS DATABASE)
    THIS.MYDATABASE = MYDATABASE
END CONSTRUCTOR

SUB LOOOP.LOOOP
    THIS.MYDATABASE.CONNECT
    THIS.MYDATABASE.INSERT_ALL_DUE_INCOMES
    UTIL.PRNT TEXTRESOURCES.CURRENT_BALANCE(THIS.MYDATABASE.BALANCE)
    THIS.HANDLE_INFO
    DIM AS BOOLEAN LOOPING = TRUE
    WHILE LOOPING
        DIM AS STRING USERINPUT = UTIL.GETINPUT(TEXTRESOURCES.ENTER_INPUT())
        SELECT CASE USERINPUT
        CASE KEY_ADD
            THIS.HANDLE_ADD
        CASE KEY_SUB
            THIS.HANDLE_SUB
        CASE KEY_SHOW
            THIS.HANDLE_SHOW
        CASE KEY_HELP
            THIS.HANDLE_HELP
        CASE KEY_QUIT
            LOOPING = FALSE
        CASE ELSE
            IF LEN(USERINPUT) > 1 AND (MID(USERINPUT, 1, 1) = KEY_ADD OR MID(USERINPUT, 1, 1) = KEY_SUB) THEN
                THIS.OMG
            ELSE
                THIS.HANDLE_INFO
            END IF
        END SELECT
    WEND
    THIS.MYDATABASE.DISCONNECT
    UTIL.PRNTLN TEXTRESOURCES.BYE
END SUB

SUB LOOOP.HANDLE_ADD
    THIS.ADD_TO_LEDGER 1, TEXTRESOURCES.INCOME_BOOKED
END SUB

SUB LOOOP.HANDLE_SUB
    THIS.ADD_TO_LEDGER -1, TEXTRESOURCES.EXPENSE_BOOKED
END SUB

SUB LOOOP.ADD_TO_LEDGER(SIGNUM AS INTEGER, SUCCESS_MESSAGE AS STRING)
    DIM AS STRING DESCRIPTION = UTIL.GETINPUT(TEXTRESOURCES.ENTER_DESCRIPTION())
    DIM AS DOUBLE AMOUNT = VAL(UTIL.GETINPUT(TEXTRESOURCES.ENTER_AMOUNT()))
    IF AMOUNT > 0 THEN
        IF SIGNUM = 1 OR THIS.MYDATABASE.IS_EXPENSE_ACCEPTABLE(AMOUNT) THEN
            THIS.MYDATABASE.INSERT_INTO_LEDGER DESCRIPTION, AMOUNT * SIGNUM
            UTIL.PRNTLN SUCCESS_MESSAGE
            UTIL.PRNT TEXTRESOURCES.CURRENT_BALANCE(THIS.MYDATABASE.BALANCE)
        ELSE
            UTIL.PRNTLN TEXTRESOURCES.ERROR_TOO_EXPENSIVE
        END IF
    ELSEIF AMOUNT < 0 THEN
        UTIL.PRNTLN TEXTRESOURCES.ERROR_NEGATIVE_AMOUNT
    ELSE
        UTIL.PRNTLN TEXTRESOURCES.ERROR_ZERO_OR_INVALID_AMOUNT
    END IF
END SUB

SUB LOOOP.OMG
    UTIL.PRNTLN TEXTRESOURCES.ERROR_OMG
END SUB

SUB LOOOP.HANDLE_INFO
    UTIL.PRNT TEXTRESOURCES.INFO
END SUB

SUB LOOOP.HANDLE_HELP
    UTIL.PRNT TEXTRESOURCES.HELP
END SUB

SUB LOOOP.HANDLE_SHOW
    UTIL.PRNT TEXTRESOURCES.FORMATTED_BALANCE(THIS.MYDATABASE.BALANCE, THIS.MYDATABASE.TRANSACTIONS)
END SUB

NAMESPACE TEXTRESOURCES

    FUNCTION BANNER AS STRING
        RETURN !"\n" _
"<TAB> _                                 _   _" !"\n" _
"<TAB>(_|   |_/o                        | | | |" !"\n" _
"<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_" !"\n" _
"<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |" !"\n" _
"<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/" !"\n" _
!"\n" _
"<TAB>FreeBASIC 1.10 Edition" !"\n" _
!"\n" _
!"\n"
    END FUNCTION

    FUNCTION INFO AS STRING
        RETURN !"\n" _
"<TAB>Commands:" !"\n" _
"<TAB>- press plus (+) to add an irregular income" !"\n" _
"<TAB>- press minus (-) to add an expense" !"\n" _
"<TAB>- press equals (=) to show balance and last transactions" !"\n" _
"<TAB>- press question mark (?) for even more info about this program" !"\n" _
"<TAB>- press colon (:) to exit" !"\n" _
!"\n"
    END FUNCTION

    FUNCTION HELP AS STRING
        RETURN !"\n" _
"<TAB>Virtuallet is a tool to act as your virtual wallet. Wow..." !"\n" _
"<TAB>Virtuallet is accessible via terminal and uses a Sqlite database to store all its data." !"\n" _
"<TAB>On first start Virtuallet will be configured and requires some input " !"\n" _
"<TAB>but you already know that unless you are currently studying the source code." !"\n" _
!"\n" _
"<TAB>Virtuallet follows two important design principles:" !"\n" _
!"\n" _
"<TAB>- shit in shit out" !"\n" _
"<TAB>- UTFSB (Use The F**king Sqlite Browser)" !"\n" _
!"\n" _
"<TAB>As a consequence everything in the database is considered valid." !"\n" _
"<TAB>Program behaviour is unspecified for any database content being invalid. Ouch..." !"\n" _
!"\n" _
"<TAB>As its primary feature Virtuallet will auto-add the configured income on start up" !"\n" _
"<TAB>for all days in the past since the last registered regular income." !"\n" _
"<TAB>So if you have specified a monthly income and haven't run Virtuallet for three months" !"\n" _
"<TAB>it will auto-create three regular incomes when you boot it the next time if you like it or not." !"\n" _
!"\n" _
"<TAB>Virtuallet will also allow you to add irregular incomes and expenses manually." !"\n" _
"<TAB>It can also display the current balance and the 30 most recent transactions." !"\n" _
!"\n" _
"<TAB>The configured overdraft will be considered if an expense is registered." !"\n" _
"<TAB>For instance if your overdraft equals the default value of 200 " !"\n" _
"<TAB>you won't be able to add an expense if the balance would be less than -200 afterwards." !"\n" _
!"\n" _
"<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser" !"\n" _
"<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle." !"\n" _
!"\n" _
"<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it." !"\n" !"\n"
    END FUNCTION

    FUNCTION SETUP_PRE_DATABASE AS STRING
        RETURN !"\n" _
"<TAB>Database file not found." !"\n" _
"<TAB>Database will be initialized. This may take a while... NOT." !"\n"
    END FUNCTION

    FUNCTION SETUP_POST_DATABASE AS STRING
        RETURN !"\n" _
"<TAB>Database initialized." !"\n" _
"<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar." !"\n" _
"<TAB>Press enter to accept the default or input something else. There is no validation" !"\n" _
"<TAB>because I know you will not make a mistake. No second chances. If you f**k up," !"\n" _
"<TAB>you will have to either delete the database file or edit it using a sqlite database browser." !"\n"
    END FUNCTION

    FUNCTION ERROR_ZERO_OR_INVALID_AMOUNT AS STRING
        RETURN "amount is zero or invalid -> action aborted"
    END FUNCTION

    FUNCTION ERROR_NEGATIVE_AMOUNT AS STRING
        RETURN "amount must be positive -> action aborted"
    END FUNCTION

    FUNCTION INCOME_BOOKED AS STRING
        RETURN "income booked"
    END FUNCTION

    FUNCTION EXPENSE_BOOKED AS STRING
        RETURN "expense booked successfully"
    END FUNCTION

    FUNCTION ERROR_TOO_EXPENSIVE AS STRING
        RETURN "sorry, too expensive -> action aborted"
    END FUNCTION

    FUNCTION ERROR_OMG AS STRING
        RETURN "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that"
    END FUNCTION

    FUNCTION ENTER_INPUT AS STRING
        RETURN "input > "
    END FUNCTION

    FUNCTION ENTER_DESCRIPTION AS STRING
        RETURN "description (optional) > "
    END FUNCTION

    FUNCTION ENTER_AMOUNT AS STRING
        RETURN "amount > "
    END FUNCTION

    FUNCTION SETUP_COMPLETE AS STRING
        RETURN "setup complete, have fun"
    END FUNCTION

    FUNCTION BYE AS STRING
        RETURN "see ya"
    END FUNCTION

    FUNCTION CURRENT_BALANCE(BALANCE AS DOUBLE) AS STRING
        RETURN !"\n" "<TAB>current balance: " & FORMAT(BALANCE, "0.00") & !"\n" !"\n"
    END FUNCTION

    FUNCTION FORMATTED_BALANCE(BALANCE AS DOUBLE, FORMATTED_LAST_TRANSACTIONS AS STRING) AS STRING
        RETURN TEXTRESOURCES.CURRENT_BALANCE(BALANCE) & _
"<TAB>last transactions (up to 30)" & !"\n" _
"<TAB>----------------------------" & !"\n" & _
FORMATTED_LAST_TRANSACTIONS & !"\n" & !"\n"
    END FUNCTION

    FUNCTION SETUP_DESCRIPTION AS STRING
        RETURN "enter description for regular income"
    END FUNCTION

    FUNCTION SETUP_INCOME AS STRING
        RETURN "enter regular income"
    END FUNCTION

    FUNCTION SETUP_OVERDRAFT AS STRING
        RETURN "enter overdraft"
    END FUNCTION

    FUNCTION SETUP_TEMPLATE(DESCRIPTION AS STRING, STANDARD AS STRING) AS STRING
        RETURN DESCRIPTION & " [default: " & STANDARD & "] > "
    END FUNCTION

END NAMESPACE

UTIL.PRNT TEXTRESOURCES.BANNER
DIM MYDATABASE AS DATABASE
DIM MYSETUP AS SETUP = MYDATABASE
MYSETUP.SETUP_ON_FIRST_RUN
DIM MYLOOP AS LOOOP = MYDATABASE
MYLOOP.LOOOP
