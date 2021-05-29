import groovy.sql.Sql
import groovy.transform.PackageScope

import java.math.RoundingMode
import java.sql.SQLException
import java.time.LocalDate
import java.time.LocalDateTime

class Virtuallet {

    static final String DB_FILE = '../db_virtuallet.db'
    static final String CONF_INCOME_DESCRIPTION = 'income_description'
    static final String CONF_INCOME_AMOUNT = 'income_amount'
    static final String CONF_OVERDRAFT = 'overdraft'

    static def main(args) {
        final def database = new Database()
        final def setup = new Setup(database)
        final def loop = new Loop(database)
        println TextResources.banner()
        try {
            setup.setupOnFirstRun()
            loop.loop()
        } catch (SQLException throwables) {
            throwables.printStackTrace()
            print 'Ouch that hurt...'
        }
    }

}

@PackageScope
class Util {

    private static final Scanner stdin = new Scanner(System.in)

    static def input(message) {
        print message
        stdin.nextLine()
    }

    static def inputOrDefault(message, standard) {
        final def result = input message
        result.is(null) || result.isBlank() ? standard : result
    }

    static def firstCharMatches(str1, str2) {
        !str1.is(null) && !str2.is(null) && !str1.isEmpty() && !str2.isEmpty() && str1.charAt(0).is(str2.charAt(0))
    }

    static def readConfigInput(description, standard) {
        final def input = input(TextResources.setupTemplate(description, standard))
        input.isBlank() ? standard : input
    }

}

@PackageScope
class Database {

    private def connection

    def connect() {
        if (connection.is null) {
            connection = Sql.newInstance "jdbc:sqlite:$Virtuallet.DB_FILE"
        }
    }

    def disconnect() {
        connection.close()
    }

    def createTables() {
        connection.execute '''
            CREATE TABLE ledger (
            description TEXT,
            amount REAL NOT NULL,
            auto_income INTEGER NOT NULL,
            created_by TEXT,
            created_at TIMESTAMP NOT NULL,
            modified_at TIMESTAMP) 
            '''
        connection.execute ' CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL) '
    }

    def insertConfiguration(key, value) {
        connection.execute "INSERT INTO configuration (k, v) VALUES ($key, $value) "
    }

    def insertIntoLedger(description, amount) {
        connection.execute """INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
                VALUES ($description, $amount, 0, datetime('now'), 'Groovy 3.0 Edition')"""
    }

    def balance() {
        (connection.firstRow('''SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger 
            ''', [:])[0] as BigDecimal).setScale(2, RoundingMode.HALF_UP)
    }

    def transactions() {
        final def rows = []
        connection.eachRow('''SELECT created_at, amount, description 
            FROM ledger ORDER BY ROWID DESC LIMIT 30'''){ row ->
            rows.add("\t${row.created_at}\t${row.amount}\t${row.description}")
        }
        String.join '\n', rows
    }

    private def incomeDescription() {
        def rows = connection.rows(" SELECT v FROM configuration WHERE k = $Virtuallet.CONF_INCOME_DESCRIPTION")
        rows.size() == 1 ? rows.get(0).v : 'pocket money'
    }

    private def incomeAmount() {
        def rows = connection.rows(" SELECT v FROM configuration WHERE k = $Virtuallet.CONF_INCOME_AMOUNT")
        rows.size() == 1 ? rows.get(0).v as BigDecimal : 100
    }

    private def overdraft() {
        def rows = connection.rows(" SELECT v FROM configuration WHERE k = $Virtuallet.CONF_OVERDRAFT")
        rows.size() == 1 ? rows.get(0).v as BigDecimal : 200
    }

    def isExpenseAcceptable(expense) {
        balance() + overdraft() - expense >= 0
    }

    def insertAllDueIncomes() {
        final def dueDates = new ArrayList<Tuple<Integer>>()
        def dueDate = new Tuple(LocalDateTime.now().getMonth().getValue(), LocalDateTime.now().getYear())
        while (!hasAutoIncomeForMonth(dueDate.get(0) ,dueDate.get(1))) {
            dueDates.add(dueDate)
            dueDate = new Tuple(
                    dueDate.get(0) > 1 ? dueDate.get(0) - 1 : 12,
                    dueDate.get(0) > 1 ? dueDate.get(1) : dueDate.get(1) - 1)
        }
        dueDates.reverse().forEach(due -> insertAutoIncome(due.get(0), due.get(1)))
    }

    def insertAutoIncome(month, year) {
        final def description = "${incomeDescription()} ${month.toString().padLeft(2, '0')}/$year"
        final def amount = incomeAmount()
        connection.execute """INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
            VALUES ($description, $amount, 1, datetime('now'), 'Groovy 3.0 Edition') """
    }

    def hasAutoIncomeForMonth(month, year) {
        (connection.firstRow("""
                SELECT EXISTS(
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE '% ${month.toString().padLeft(2, '0')}/$year')
            """, [:]).getAt(0) as BigDecimal).signum().is(1)
    }

}

@PackageScope
class Setup {

    private final def database

    Setup(database) {
        this.database = database
    }

    def setupOnFirstRun() {
        if (!new File(Virtuallet.DB_FILE).exists()) {
            initialize()
        }
    }

    private def initialize() {
        println TextResources.setupPreDatabase()
        database.connect()
        database.createTables()
        println TextResources.setupPostDatabase()
        setup()
        println TextResources.setupComplete()
    }

    private def setup() {
        final def incomeDescription = Util.readConfigInput TextResources.setupDescription(), 'pocket money'
        final def incomeAmount = Util.readConfigInput TextResources.setupIncome(), 100
        final def overdraft = Util.readConfigInput TextResources.setupOverdraft(), 200
        database.insertConfiguration Virtuallet.CONF_INCOME_DESCRIPTION, incomeDescription
        database.insertConfiguration Virtuallet.CONF_INCOME_AMOUNT, incomeAmount
        database.insertConfiguration Virtuallet.CONF_OVERDRAFT, overdraft
        database.insertAutoIncome LocalDate.now().getMonthValue(), LocalDate.now().getYear()
    }

}

@PackageScope
class Loop {

    private static final String KEY_ADD = '+'
    private static final String KEY_SUB = '-'
    private static final String KEY_SHOW = '='
    private static final String KEY_HELP = '?'
    private static final String KEY_QUIT = ':'

    private final def database

    Loop(database) {
        this.database = database
    }

     def loop() {
        database.connect()
        database.insertAllDueIncomes()
        println(TextResources.currentBalance(database.balance()))
        handleInfo()
        def looping = true
        while (looping) {
            final def input = Util.input TextResources.enterInput()
            switch(input) {
                case KEY_ADD:
                    handleAdd()
                    break
                case KEY_SUB:
                    handleSub()
                    break
                case KEY_SHOW:
                    handleShow()
                    break
                case KEY_HELP:
                    handleHelp()
                    break
                case KEY_QUIT:
                    looping = false
                    break
                default:
                    if (Util.firstCharMatches(input, KEY_ADD) || Util.firstCharMatches(input, KEY_SUB)) {
                        omg()
                    } else {
                        handleInfo()
                    }
            }
        }
        database.disconnect()
        println TextResources.bye()
    }

    private static def omg() {
        print TextResources.errorOmg()
    }

    private def handleAdd() {
        addToLedger(1, TextResources.incomeBooked())
    }

    private def handleSub() {
        addToLedger(-1, TextResources.expenseBooked())
    }

    private def addToLedger(signum, successMessage) {
        final def description = Util.input TextResources.enterDescription()
        final def input = Util.inputOrDefault(TextResources.enterAmount(), '0')
        final def amount = input.matches('-?\\d+(\\.\\d+)?') ? input as BigDecimal : 0
        if (amount > 0) {
            if (signum.is(1) || database.isExpenseAcceptable(amount)) {
                database.insertIntoLedger description, amount * signum
                print successMessage
                println(TextResources.currentBalance(database.balance()))
            } else {
                print TextResources.errorTooExpensive()
            }
        } else if (amount < 0) {
            print TextResources.errorNegativeAmount()
        } else {
            print TextResources.errorZeroOrInvalidAmount()
        }
    }

    private def handleShow() {
        println(TextResources.formattedBalance(database.balance(), database.transactions()))
    }

    private static def handleInfo() {
        println TextResources.info()
    }

    private static def handleHelp() {
        println TextResources.help()
    }

}

@PackageScope
class TextResources {

    static def banner() {
        '''
         _                                 _   _
        (_|   |_/o                        | | | |
          |   |      ,_  _|_         __,  | | | |  _ _|_
          |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
           \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/

        Groovy 3.0 Edition

        '''
    }

    static def info() {
        '''
        Commands:
        - press plus (+) to add an irregular income
        - press minus (-) to add an expense
        - press equals (=) to show balance and last transactions
        - press question mark (?) for even more info about this program
        - press colon (:) to exit
        '''
    }

    static def help() {
        '''
        Virtuallet is a tool to act as your virtual wallet. Wow...
        Virtuallet is accessible via terminal and uses a Sqlite database to store all its data.
        On first start Virtuallet will be configured and requires some input
        but you already know that unless you are currently studying the source code.

        Virtuallet follows two important design principles:

        - shit in shit out
        - UTFSB (Use The F**king Sqlite Browser)

        As a consequence everything in the database is considered valid.
        Program behaviour is unspecified for any database content being invalid. Ouch...

        As its primary feature Virtuallet will auto-add the configured income on start up
        for all days in the past since the last registered regular income.
        So if you have specified a monthly income and haven't run Virtuallet for three months
        it will auto-create three regular incomes when you boot it the next time if you like it or not.

        Virtuallet will also allow you to add irregular incomes and expenses manually.
        It can also display the current balance and the 30 most recent transactions.

        The configured overdraft will be considered if an expense is registered.
        For instance if your overdraft equals the default value of 200
        you won't be able to add an expense if the balance would be less than -200 afterwards.

        Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser
        to view and even edit the database. When making updates please remember the shit in shit out principle.

        As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.
        '''
    }

    static def setupPreDatabase() {
        '''
        Database file not found.
        Database will be initialized. This may take a while... NOT.'''
    }

    static def setupPostDatabase() {
        '''
        Database initialized.
        Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
        Press enter to accept the default or input something else. There is no validation
        because I know you will not make a mistake. No second chances. If you f**k up,
        you will have to either delete the database file or edit it using a sqlite database browser.
        '''
    }

    static def errorZeroOrInvalidAmount() {
        'amount is zero or invalid -> action aborted\n'
    }

    static def errorNegativeAmount() {
        'amount must be positive -> action aborted\n'
    }

    static def incomeBooked() {
        'income booked\n'
    }

    static def expenseBooked() {
        'expense booked successfully\n'
    }

    static def errorTooExpensive() {
        'sorry, too expensive -> action aborted\n'
    }

    static def errorOmg() {
        'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that\n'
    }

    static def enterInput() {
        'input > '
    }

    static def enterDescription() {
        'description (optional) > '
    }

    static def enterAmount() {
        'amount > '
    }

    static def setupComplete() {
        'setup complete, have fun'
    }

    static def bye() {
        'see ya'
    }

    static def currentBalance(balance) {
        """
        current balance: $balance
        """
    }

    static def formattedBalance(balance, formattedLastTransactions) {
        """
        current balance: $balance

        last transactions (up to 30)
        ----------------------------
$formattedLastTransactions
        """
    }

    static def setupDescription() {
        'enter description for regular income'
    }

    static def setupIncome() {
        'enter regular income'
    }

    static def setupOverdraft() {
        'enter overdraft'
    }

    static def setupTemplate(description, standard) {
        "$description [default: $standard] > "
    }

}
