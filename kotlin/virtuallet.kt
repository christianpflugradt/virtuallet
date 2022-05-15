import java.math.BigDecimal
import java.math.RoundingMode
import java.nio.file.Files
import java.nio.file.Paths
import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet
import java.time.LocalDate

fun Connection.query(qry: String): ResultSet = this.createStatement().executeQuery(qry)
fun ResultSet.str(i: Int): String = this.getString(i)
fun ResultSet.bd(i: Int): BigDecimal = this.getBigDecimal(i)
fun BigDecimal.normalize(): BigDecimal = this.setScale(2, RoundingMode.HALF_UP)

internal object Util {

    fun prnt(message: String) = print(message.replace(Virtuallet.TAB, "\t"))

    fun input(message: String): String {
        print(message)
        return readLine() ?: ""
    }

    fun inputOrDefault(message: String, standard: String) = input(message).let { if (it.isBlank()) standard else it }

    fun readConfigInput(description: String, standard: Any) =
        input(TextResources.setupTemplate(description, standard.toString()))
            .let { if (it.isBlank()) standard.toString() else it }
}

internal class Database {

    private var connection: Connection? = null

    fun connect() {
        if (connection == null) {
            connection = DriverManager.getConnection("jdbc:sqlite:${Virtuallet.DB_FILE}")
        }
    }

    fun disconnect() = connection?.close()

    private fun execute(sql: String) = connection!!.createStatement().execute(sql)

    fun createTables() {
        execute(
            """
            CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL, 
                auto_income INTEGER NOT NULL,
                created_by TEXT, 
                created_at TIMESTAMP NOT NULL, 
                modified_at TIMESTAMP)"""
        )
        execute("CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)")
    }

    fun insertConfiguration(key: String, value: Any) =
        execute("INSERT INTO configuration (k, v) VALUES ('$key', '$value')")

    fun insertIntoLedger(description: String, amount: BigDecimal) =
        execute(
            """INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
            VALUES ('$description', ${amount.toDouble()}, 0, datetime('now'), 'Kotlin 1.6 Edition')"""
        )

    fun balance(): BigDecimal =
        with(connection!!) {
            query(" SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger ").let {
                if (it.next()) it.bd(1).normalize() else 0.toBigDecimal()
            }
        }

    fun transactions(): String =
        with(connection!!) {
            val result = query(" SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30 ")
            val rows = mutableListOf<String>()
            while (result.next()) {
                rows.add(
                    "\t" + listOf(
                        result.str(1),
                        result.bd(2).normalize().toString(),
                        result.str(3)
                    ).joinToString(separator = "\t")
                )
            }
            "${rows.joinToString(separator = "\n")}\n"
        }

    private fun incomeDescription(): String =
        with(connection!!) {
            query(" SELECT v FROM configuration WHERE k = '${Virtuallet.CONF_INCOME_DESCRIPTION}'")
                .let { if (it.next()) it.str(1) else "pocket money" }
        }

    private fun incomeAmount(): BigDecimal =
        with(connection!!) {
            query(" SELECT v FROM configuration WHERE k = '${Virtuallet.CONF_INCOME_AMOUNT}'")
                .let { if (it.next()) it.bd(1) else 100.toBigDecimal() }
        }

    private fun overdraft(): BigDecimal =
        with(connection!!) {
            query(" SELECT v FROM configuration WHERE k = '${Virtuallet.CONF_OVERDRAFT}'")
                .let { if (it.next()) it.bd(1) else 200.toBigDecimal() }
        }

    fun isExpenseAcceptable(expense: BigDecimal) = (balance() + overdraft() - expense).signum() != -1

    fun insertAllDueIncomes() {
        class MonthAndYear(val month: Int, val year: Int)

        val dueDates = mutableListOf<MonthAndYear>()
        var dueDate = MonthAndYear(
            LocalDate.now().getMonthValue(),
            LocalDate.now().getYear()
        )
        while (!hasAutoIncomeForMonth(dueDate.month, dueDate.year)) {
            dueDates.add(dueDate)
            dueDate = MonthAndYear(
                if (dueDate.month > 1) dueDate.month - 1 else 12,
                if (dueDate.month > 1) dueDate.year else dueDate.year - 1
            )
        }
        dueDates.reversed().forEach { insertAutoIncome(it.month, it.year) }
    }

    fun insertAutoIncome(month: Int, year: Int) =
        execute(
            """INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
            VALUES ('${incomeDescription()} ${"%02d".format(month)}/$year', ${incomeAmount()}, 
            1, datetime('now'), 'Kotlin 1.6 Edition')"""
        )

    fun hasAutoIncomeForMonth(month: Int, year: Int): Boolean =
        with(connection!!) {
            query(
                """
                SELECT EXISTS(
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE '% ${"%02d".format(month)}/$year')"""
            )
                .let { it.next() && it.bd(1).signum() == 1 }
        }
}

internal class Setup(private val database: Database) {

    fun setupOnFirstRun() {
        if (Files.notExists(Paths.get(Virtuallet.DB_FILE))) { initialize() }
    }

    private fun initialize() {
        Util.prnt(TextResources.setupPreDatabase())
        database.connect()
        database.createTables()
        Util.prnt(TextResources.setupPostDatabase())
        setup()
        println(TextResources.setupComplete())
    }

    private fun setup() {
        val incomeDescription = Util.readConfigInput(TextResources.setupDescription(), "pocket money")
        val incomeAmount = Util.readConfigInput(TextResources.setupIncome(), 100)
        val overdraft = Util.readConfigInput(TextResources.setupOverdraft(), 200)
        database.insertConfiguration(Virtuallet.CONF_INCOME_DESCRIPTION, incomeDescription)
        database.insertConfiguration(Virtuallet.CONF_INCOME_AMOUNT, incomeAmount)
        database.insertConfiguration(Virtuallet.CONF_OVERDRAFT, overdraft)
        database.insertAutoIncome(LocalDate.now().getMonthValue(), LocalDate.now().getYear())
    }
}

internal class Loop(private val database: Database) {

    companion object {
        private const val KEY_ADD = '+'
        private const val KEY_SUB = '-'
        private const val KEY_SHOW = '='
        private const val KEY_HELP = '?'
        private const val KEY_QUIT = ':'
    }

    fun loop() {
        database.connect()
        database.insertAllDueIncomes()
        Util.prnt("${TextResources.currentBalance(database.balance())}\n")
        handleInfo()
        var looping = true
        while (looping) {
            val input = Util.input(TextResources.enterInput())
            if (input.length == 1) {
                when (input[0]) {
                    KEY_ADD -> handleAdd()
                    KEY_SUB -> handleSub()
                    KEY_SHOW -> handleShow()
                    KEY_HELP -> handleHelp()
                    KEY_QUIT -> looping = false
                    else -> handleInfo()
                }
            } else if (input.length > 1 && listOf(KEY_ADD, KEY_SUB).contains(input[0])) {
                omg()
            } else {
                handleInfo()
            }
        }
        database.disconnect()
        println(TextResources.bye())
    }

    private fun handleAdd() = addToLedger(1, TextResources.incomeBooked())

    private fun handleSub() = addToLedger(-1, TextResources.expenseBooked())

    private fun addToLedger(signum: Int, successMessage: String) {
        val description = Util.input(TextResources.enterDescription())
        val input = Util.inputOrDefault(TextResources.enterAmount(), 0.toString())
        val amount = runCatching { input.toBigDecimal() }.getOrDefault(0.toBigDecimal())
        if (amount.signum() == 1) {
            if (signum == 1 || database.isExpenseAcceptable(amount)) {
                database.insertIntoLedger(description, amount.multiply(BigDecimal.valueOf(signum.toLong())))
                println(successMessage)
                Util.prnt("${TextResources.currentBalance(database.balance())}\n")
            } else {
                println(TextResources.errorTooExpensive())
            }
        } else if (amount.signum() == -1) {
            println(TextResources.errorNegativeAmount())
        } else {
            println(TextResources.errorZeroOrInvalidAmount())
        }
    }

    private fun omg() = println(TextResources.errorOmg())

    private fun handleInfo() = Util.prnt(TextResources.info())

    private fun handleHelp() = Util.prnt(TextResources.help())

    private fun handleShow() = Util.prnt(TextResources.formattedBalance(database.balance(), database.transactions()))
}

internal object TextResources {
    fun banner() = """
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>Kotlin 1.6 Edition


"""

    fun info() = """
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

"""

    fun help() = """
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

    fun setupPreDatabase() = """
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
"""

    fun setupPostDatabase() = """
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

"""

    fun errorZeroOrInvalidAmount() = "amount is zero or invalid -> action aborted"

    fun errorNegativeAmount() = "amount must be positive -> action aborted"

    fun incomeBooked() = "income booked"

    fun expenseBooked() = "expense booked successfully"

    fun errorTooExpensive() = "sorry, too expensive -> action aborted"

    fun errorOmg() = "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that"

    fun enterInput() = "input > "

    fun enterDescription() = "description (optional) > "

    fun enterAmount() = "amount > "

    fun setupComplete() = "setup complete, have fun"

    fun bye() = "see ya"

    fun currentBalance(balance: BigDecimal) = """
<TAB>current balance: $balance           
"""

    fun formattedBalance(balance: BigDecimal, formattedLastTransactions: String) =
        """${TextResources.currentBalance(balance)}
<TAB>last transactions (up to 30)
<TAB>----------------------------
$formattedLastTransactions
"""

    fun setupDescription() = "enter description for regular income"

    fun setupIncome() = "enter regular income"

    fun setupOverdraft() = "enter overdraft"

    fun setupTemplate(description: String, standard: String) = "$description [default: $standard] > "
}

object Virtuallet {
    const val DB_FILE = "../db_virtuallet.db"
    const val CONF_INCOME_DESCRIPTION = "income_description"
    const val CONF_INCOME_AMOUNT = "income_amount"
    const val CONF_OVERDRAFT = "overdraft"
    const val TAB = "<TAB>"

    @kotlin.jvm.JvmStatic
    fun main(args: Array<String>) {
        val database = Database()
        val setup = Setup(database)
        val loop = Loop(database)
        Util.prnt(TextResources.banner())
        setup.setupOnFirstRun()
        loop.loop()
    }
}
