library(RSQLite)

DB_FILE = '../db_virtuallet.db'
CONF_INCOME_DESCRIPTION = 'income_description'
CONF_INCOME_AMOUNT = 'income_amount'
CONF_OVERDRAFT = 'overdraft'
TAB = '<TAB>'

Util.print = function(str) {
    cat(gsub(TAB, '\t', str))
}

Util.println = function(str) {
    Util.print(paste(str, '\n', sep=''))
}

Util.input = function(prefix) {
    Util.print(prefix)
    return(readLines('stdin', n=1))
}

Util.readConfigInput = function(description, standard) {
    input = Util.input(TextResources.setupTemplate(description, standard))
    return(ifelse(input == '', standard, input))
}

Util.currentYear = function() {
    strtoi(format(Sys.Date(), '%Y'))
}

Util.currentMonth = function() {
    strtoi(format(Sys.Date(), '%m'))
}

Database = setRefClass('Database', fields=list(db='SQLiteConnection'),
    methods=list(

        connect = function() {
            db <<- dbConnect(RSQLite::SQLite(), '../db_virtuallet.db')
        },

        disconnect = function() {
            dbDisconnect(db)
        },

        createTables = function() {
            res = dbExecute(db, 'CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL,
                auto_income INTEGER NOT NULL,
                created_by TEXT,
                created_at TIMESTAMP NOT NULL,
                modified_at TIMESTAMP)')
            res = dbExecute(db, 'CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)')
        },

        insertConfiguration = function(key, value) {
            res = dbSendStatement(db, 'INSERT INTO configuration (k, v) VALUES (?, ?)')
            dbBind(res, params=list(key, value))
            dbGetRowsAffected(res)
            dbClearResult(res)
        },

        insertIntoLedger = function(description, amount) {
            res = dbSendStatement(db, "INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
                                        VALUES (?, ROUND(?, 2), 0, datetime('now'), 'R 4.3 Edition')")
            dbBind(res, params=list(description, amount))
            dbGetRowsAffected(res)
            dbClearResult(res)
        },

        balance = function() {
            return(dbGetQuery(db, "SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger")[1,1])
        },

        transactions = function() {
            formatted = ''
            res = dbGetQuery(db, 'SELECT created_at, CAST(amount AS TEXT), description FROM ledger ORDER BY ROWID DESC LIMIT 30')
            for (row in 1:nrow(res)) {
                for (col in 1:ncol(res)) {
                    formatted = paste(formatted, TAB, res[row, col], sep='')
                }
                formatted = paste(formatted, '\n', sep='')
            }
            return(formatted)
        },

        incomeDescription = function() {
            return(dbGetQuery(db, 'SELECT v FROM configuration WHERE k = ?', params = c(CONF_INCOME_DESCRIPTION))[1,1])
        },

        incomeAmount = function() {
            return(dbGetQuery(db, 'SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?', params = c(CONF_INCOME_AMOUNT))[1,1])
        },

        overdraft = function() {
            return(dbGetQuery(db, 'SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?', params = c(CONF_OVERDRAFT))[1,1])
        },

        isExpenseAcceptable = function(expense) {
            return(expense <= balance() + overdraft())
        },

        insertAllDueIncomes = function() {
            dueDates = list()
            dueDate = c(Util.currentMonth(), Util.currentYear())
            while (!.hasAutoIncomeForMonth(dueDate[1], dueDate[2])) {
                dueDates = append(dueDates, list(dueDate))
                dueDate = if (dueDate[1] > 1) c(dueDate[1] - 1, dueDate[2]) else c(12, dueDate[2] - 1)
            }
            for (dueDate in rev(dueDates)) {
                insertAutoIncome(dueDate[1], dueDate[2])
            }
        },

        insertAutoIncome = function(month, year) {
            description = paste(database$incomeDescription(), ' ', sprintf('%02d', month), '/', year, sep='')
            amount = database$incomeAmount()
            res = dbSendStatement(db, "INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
                                        VALUES (?, ROUND(?, 2), 1, datetime('now'), 'R 4.3 Edition')")
            dbBind(res, params=list(
                description,
                amount))
            dbGetRowsAffected(res)
            dbClearResult(res)
        },

        .hasAutoIncomeForMonth = function(month, year) {
            return(dbGetQuery(db, '
                SELECT COALESCE(EXISTS(
                   SELECT auto_income FROM ledger
                    WHERE auto_income = 1
                    AND description LIKE ?), 0)
                ', params = c(paste(database$incomeDescription(), ' ', sprintf('%02d', month), '/', year, sep=''))
            )[1,1] > 0)
        }

    )
)

Setup = setRefClass('Setup', fields=list(database='Database'),
    methods=list(

        setupOnFirstRun = function() {
            if (!file.exists(DB_FILE)) {
                .initialize()
            }
        },

        .initialize = function() {
            Util.print(TextResources.setupPreDatabase())
            database$connect()
            database$createTables()
            Util.print(TextResources.setupPostDatabase())
            .setup()
            Util.println(TextResources.setupComplete())
        },

        .setup = function() {
            incomeDescription = Util.readConfigInput(TextResources.setupDescription(), 'pocket money')
            incomeAmount = Util.readConfigInput(TextResources.setupIncome(), 100)
            overdraft = Util.readConfigInput(TextResources.setupOverdraft(), 200)
            database$insertConfiguration(CONF_INCOME_DESCRIPTION, incomeDescription)
            database$insertConfiguration(CONF_INCOME_AMOUNT, incomeAmount)
            database$insertConfiguration(CONF_OVERDRAFT, overdraft)
            database$insertAutoIncome(Util.currentMonth(), Util.currentYear())
        }

    )
)

KEY_ADD = '+'
KEY_SUB = '-'
KEY_SHOW = '='
KEY_HELP = '?'
KEY_QUIT = ':'

Loop = setRefClass('Loop', fields=list(database='Database'),
    methods=list(

        loop = function() {
            database$connect()
            database$insertAllDueIncomes()
            Util.println(TextResources.currentBalance(database$balance()))
            .handleInfo()
            looping = TRUE
            while (looping) {
                input = Util.input(TextResources.enterInput())
                if (input == KEY_ADD) {
                    .handleAdd()
                } else if (input == KEY_SUB) {
                    .handleSub()
                } else if (input == KEY_SHOW) {
                    .handleShow()
                } else if (input == KEY_HELP) {
                    .handleHelp()
                } else if (input == KEY_QUIT) {
                    looping = FALSE
                } else if (substring(input, 1, 1) == KEY_ADD || substring(input, 1, 1) == KEY_SUB) {
                    .omg()
                } else {
                    .handleInfo()
                }
            }
            database$disconnect()
            Util.println(TextResources.bye())
        },

        .omg = function() {
            Util.println(TextResources.errorOmg())
        },

        .handleAdd = function() {
            .addToLedger(1, TextResources.incomeBooked())
        },

        .handleSub = function() {
            .addToLedger(-1, TextResources.expenseBooked())
        },

        .addToLedger = function(signum, successMessage) {
            description = Util.input(TextResources.enterDescription())
            amount = as.double(Util.input(TextResources.enterAmount()))
            if (is.na(amount)) {
                amount = 0
            }
            if (amount > 0) {
                if (signum == 1 || database$isExpenseAcceptable(amount)) {
                    database$insertIntoLedger(description, amount * signum)
                    Util.println(successMessage)
                    Util.println(TextResources.currentBalance(database$balance()))
                } else {
                    Util.println(TextResources.errorTooExpensive())
                }
            } else if (amount < 0) {
                Util.println(TextResources.errorNegativeAmount())
            } else {
                Util.println(TextResources.errorZeroOrInvalidAmount())
            }
        },

        .handleShow = function() {
            Util.print(TextResources.formattedBalance(database$balance(), database$transactions()))
        },

        .handleInfo = function() {
            Util.print(TextResources.info())
        },

        .handleHelp = function() {
            Util.print(TextResources.help())
        }

    )
)

TextResources.banner = function() {
    return('
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/

<TAB>R 4.3 Edition

')
}

TextResources.info = function() {
    return('
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

')
}

TextResources.help = function() {
    return("
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
<TAB>For database if your overdraft equals the default value of 200
<TAB>you won't be able to add an expense if the balance would be less than -200 afterwards.

<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser
<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.

<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.

")
}

TextResources.setupPreDatabase = function() {
    return('
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
')
}

TextResources.setupPostDatabase = function() {
    return("
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

")
}

TextResources.errorZeroOrInvalidAmount = function() {
    return('amount is zero or invalid -> action aborted')
}

TextResources.errorNegativeAmount = function() {
    return('amount must be positive -> action aborted')
}

TextResources.incomeBooked = function() {
    return('income booked')
}

TextResources.expenseBooked = function() {
    return('expense booked successfully')
}

TextResources.errorTooExpensive = function() {
    return('sorry, too expensive -> action aborted')
}

TextResources.errorOmg = function() {
    return('OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that')
}

TextResources.enterInput = function() {
    return('input > ')
}

TextResources.enterDescription = function() {
    return('description (optional) > ')
}

TextResources.enterAmount = function() {
    return('amount > ')
}

TextResources.setupComplete = function() {
    return('setup complete, have fun')
}

TextResources.bye = function() {
    return('see ya')
}


TextResources.currentBalance = function(balance) {
    return(paste('
<TAB>current balance: ', sprintf('%.2f', balance), '
', sep=''))
}

TextResources.formattedBalance = function(balance, formatted_last_transactions) {
    return(paste(TextResources.currentBalance(balance), '
<TAB>last transactions (up to 30)
<TAB>----------------------------
', formatted_last_transactions, '
', sep=''))
}


TextResources.setupDescription = function() {
    return('enter description for regular income')
}

TextResources.setupIncome = function() {
    return('enter regular income')
}

TextResources.setupOverdraft = function() {
    return('enter overdraft')
}

TextResources.setupTemplate = function(description, default) {
    return(paste(description, ' [default: ', default, '] > ', sep=''))
}

database = Database$new()
setup = Setup$new(database = database)
loop = Loop$new(database=database)
Util.println(TextResources.banner())
setup$setupOnFirstRun()
loop$loop()
