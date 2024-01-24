import java.nio.file.Files
import java.nio.file.Paths
import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet
import java.time.LocalDate
import scala.io.StdIn.readLine
import scala.math.BigDecimal.RoundingMode
import scala.util.{Try, Success, Failure}

val DB_FILE = "../db_virtuallet.db"
val CONF_INCOME_DESCRIPTION = "income_description"
val CONF_INCOME_AMOUNT = "income_amount"
val CONF_OVERDRAFT = "overdraft"
val TAB = "<TAB>"

object Util {

    def prnt(message: String) = { print(message replace(TAB, "\t")) }
    def prntln(message: String) = { prnt(s"$message\n") }

    def input(message: String) = {
        prnt(message)
        readLine
    }

    def readConfigInput(description: String, standard: Any) = {
        val inp = input(TextResources.setupTemplate(description, standard.toString()))
        if (inp.isBlank) standard.toString else inp
    }

}

class Database {

    private var connection: Option[Connection] = None

    private def con = connection getOrElse null

    def connect = if (connection.isEmpty) connection = Some(DriverManager getConnection(s"jdbc:sqlite:$DB_FILE"))

    def disconnect = { con.close }

    extension(c: Connection)
        def execute(sql: String) = c.createStatement().execute(sql)
        def query(qry: String) = c.createStatement().executeQuery(qry)

    extension(b: BigDecimal)
        def normalize = b.setScale(2, RoundingMode.HALF_UP)

    def createTables = {
        con.execute("""
            CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL,
                auto_income INTEGER NOT NULL,
                created_by TEXT,
                created_at TIMESTAMP NOT NULL,
                modified_at TIMESTAMP)""")
        con.execute("CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)")
    }

    def insertConfiguration(key: String, value: String) = con.execute(s"INSERT INTO configuration (k, v) VALUES ('$key', '$value')")

    def insertIntoLedger(description: String, amount: BigDecimal) = con.execute(s"""
        INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
        VALUES ('$description', ${amount.toDouble}, 0, datetime('now'), 'Scala 3.1 Edition')""")

    def balance = {
        val result = con.query("SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger")
        if (result.next()) result.getBigDecimal(1).normalize else BigDecimal(0)
    }

    def transactions = {
        val result = con.query("SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30")
        var rows: List[String] = Nil
        while (result.next()) {
            rows = s"\t${result.getString(1)}\t${result.getBigDecimal(2).normalize}\t${result.getString(3)}" :: rows
        }
        rows.reverse.mkString("\n") + "\n"
    }

    def incomeDescription = {
        val result = con.query(s"SELECT v FROM configuration WHERE k = '$CONF_INCOME_DESCRIPTION'")
        if (result.next()) result.getString(1) else ""
    }

    def incomeAmount = {
        val result = con.query(s"SELECT v FROM configuration WHERE k = '$CONF_INCOME_AMOUNT'")
        if (result.next()) result.getBigDecimal(1).normalize else BigDecimal(0)
    }

    def overdraft = {
        val result = con.query(s"SELECT v FROM configuration WHERE k = '$CONF_OVERDRAFT'")
        if (result.next()) result.getBigDecimal(1).normalize else BigDecimal(0)
    }

    def isExpenseAcceptable(expense: BigDecimal) = balance + overdraft - expense >= 0

    def insertAutoIncome(month: Int, year: Int) = con.execute(f"""
        INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
        VALUES ('$incomeDescription $month%02d/$year', $incomeAmount,
        1, datetime('now'), 'Scala 3.1 Edition')""")

    def hasAutoIncomeForMonth(month: Int, year: Int): Boolean = {
        val result = con.query(f"""
            SELECT EXISTS(
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE '%% $month%02d/$year')""")
        if (result.next()) result.getBigDecimal(1).signum == 1 else false
    }

    def insertAllDueIncomes = {
        var dueDate = (LocalDate.now().getMonthValue(), LocalDate.now().getYear())
        var dueDates: List[(Int, Int)] = Nil
        while (!(hasAutoIncomeForMonth tupled dueDate)) {
            dueDates = dueDate :: dueDates
            dueDate = if (dueDate(0) > 1) (dueDate(0) - 1, dueDate(1)) else (12, dueDate(1) - 1)
        }
        dueDates.foreach(insertAutoIncome)
    }

}

class Setup(val database: Database) {

    def setupOnFirstRun = if (Files notExists(Paths get DB_FILE)) initialize

    def initialize = {
        Util prnt TextResources.setupPreDatabase
        database.connect
        database.createTables
        Util prnt TextResources.setupPostDatabase
        setup
        Util prntln TextResources.setupComplete
    }

    def setup = {
        val incomeDescription = Util readConfigInput(TextResources.setupDescription, "pocket money")
        val incomeAmount = Util readConfigInput(TextResources.setupIncome, 100)
        val overdraft = Util readConfigInput(TextResources.setupOverdraft, 200)
        database.insertConfiguration(CONF_INCOME_DESCRIPTION, incomeDescription)
        database.insertConfiguration(CONF_INCOME_AMOUNT, incomeAmount)
        database.insertConfiguration(CONF_OVERDRAFT, overdraft)
        database.insertAutoIncome(LocalDate.now().getMonthValue(), LocalDate.now().getYear())
    }

}

object Loop {
    private val KEY_ADD = '+'
    private val KEY_SUB = '-'
    private val KEY_SHOW = '='
    private val KEY_HELP = '?'
    private val KEY_QUIT = ':'
}

class Loop(val database: Database) {

    def loop = {
        database.connect
        database.insertAllDueIncomes
        Util prntln TextResources.currentBalance(database.balance)
        handleInfo
        var looping = true
        while (looping) {
            val input = Util input TextResources.enterInput
            input.toList match {
                case Loop.KEY_ADD :: Nil => handleAdd
                case Loop.KEY_SUB :: Nil => handleSub
                case Loop.KEY_SHOW :: Nil => handleShow
                case Loop.KEY_HELP :: Nil => handleHelp
                case Loop.KEY_QUIT :: Nil => looping = false
                case (Loop.KEY_ADD | Loop.KEY_SUB) :: xs => omg
                case _ => handleInfo
            }
        }
        database.disconnect
        Util prntln TextResources.bye
    }

    private def handleAdd = addToLedger(1, TextResources.incomeBooked)
    private def handleSub = addToLedger(-1, TextResources.expenseBooked)

    private def addToLedger(signum: Int, successMessage: String) = {
        val description = Util input TextResources.enterDescription
        Try(BigDecimal(Util input TextResources.enterAmount)) match {
            case Success(amount) => {
                amount.signum match {
                    case 1  => {
                        if (signum == 1 || database.isExpenseAcceptable(amount)) {
                            database.insertIntoLedger(description, amount * signum)
                            Util prntln successMessage
                            Util prntln TextResources.currentBalance(database.balance)
                        } else {
                            Util prntln TextResources.errorTooExpensive
                        }
                    }
                    case 0  =>  Util prntln TextResources.errorZeroOrInvalidAmount
                    case -1 =>  Util prntln TextResources.errorNegativeAmount
                }
            }
            case Failure(_) => Util prntln TextResources.errorZeroOrInvalidAmount
        }
    }

    private def omg = Util prntln TextResources.errorOmg
    private def handleInfo = Util prnt TextResources.info
    private def handleHelp = Util prnt TextResources.help
    private def handleShow = Util prnt TextResources.formattedBalance(database.balance, database.transactions)

}

object TextResources {

    def banner = """
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>Scala 3.1 Edition

"""

    def info = """
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

"""

    def help = """
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

"""

    def setupPreDatabase = """
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
"""

    def setupPostDatabase = """
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

"""

    def errorZeroOrInvalidAmount = "amount is zero or invalid -> action aborted"

    def errorNegativeAmount = "amount must be positive -> action aborted"

    def incomeBooked = "income booked"

    def expenseBooked = "expense booked successfully"

    def errorTooExpensive = "sorry, too expensive -> action aborted"

    def errorOmg = "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that"

    def enterInput = "input > "

    def enterDescription = "description (optional) > "

    def enterAmount = "amount > "

    def setupComplete = "setup complete, have fun"

    def bye = "see ya"

    def currentBalance(balance: BigDecimal) = s"""
<TAB>current balance: $balance
"""

    def formattedBalance(balance: BigDecimal, formattedLastTransactions: String) =
        s"""${TextResources.currentBalance(balance)}
<TAB>last transactions (up to 30)
<TAB>----------------------------
$formattedLastTransactions
"""

    def setupDescription = "enter description for regular income"

    def setupIncome = "enter regular income"

    def setupOverdraft = "enter overdraft"

    def setupTemplate(description: String, standard: String) = s"$description [default: $standard] > "
    
}

object virtuallet {
    def main(args: Array[String]) = {
        val database = Database()
        val setup = Setup(database)
        val loop = Loop(database)
        Util prntln TextResources.banner
        setup.setupOnFirstRun
        loop.loop
    }
}
