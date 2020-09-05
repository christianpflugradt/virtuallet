package main

import (
	"bufio"
	"database/sql"
	"fmt"
	_ "github.com/mattn/go-sqlite3"
	"os"
	"strconv"
	"strings"
	"time"
)

const dbFile = "../db_virtuallet.db"
const confIncomeDescription = "income_description"
const confIncomeAmount = "income_amount"
const confOverdraft = "overdraft"
const tab = "<TAB>"

// database

type Database struct {
	con *sql.DB
}

func (db *Database) Connect() {
	if db.con == nil {
		con, _ := sql.Open("sqlite3", dbFile)
		db.con = con
	}
}

func (db *Database) Disconnect() {
	db.con.Close()
}

func (db *Database) CreateTables() {
	db.con.Exec(`
		CREATE TABLE ledger (description TEXT, amount REAL NOT NULL, auto_income INTEGER NOT NULL,
				created_by TEXT, created_at TIMESTAMP NOT NULL, modified_at TIMESTAMP)`)
	db.con.Exec("CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)")
}

func (db *Database) insertIntoConfiguration(key string, value string) {
	db.con.Exec("INSERT INTO configuration (k, v) VALUES (?, ?)", key, value)
}

func (db *Database) insertIntoLedger(description string, amount float32) {
	db.con.Exec(`INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES
							(?, ROUND(?, 2), 0, datetime('now'), 'Go 1.15 Edition')`, description, amount)
}

func (db *Database) insertAutoIncome(month int, year int) {
	description := fmt.Sprintf("%s %02d/%d", db.description(), month, year)
	amount := db.amount()
	db.con.Exec(`INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES
							(?, ROUND(?, 2), 1, datetime('now'), 'Go 1.15 Edition')`, description, amount)
}

func (db *Database) balance() float32 {
	rows, _ := db.con.Query("SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger")
	defer rows.Close()
	rows.Next()
	var balance float32
	rows.Scan(&balance)
	return balance
}

func (db *Database) transactions() string {
	rows, _ := db.con.Query("SELECT created_at, CAST(amount AS TEXT), description FROM ledger ORDER BY ROWID DESC LIMIT 30")
	defer rows.Close()
	var transactions strings.Builder
	for rows.Next() {
		var createdAt string
		var amount string
		var description string
		rows.Scan(&createdAt, &amount, &description)
		transactions.WriteString(fmt.Sprintf("\t%s\t%s\t%s\n", createdAt, amount, description))
	}
	return transactions.String()
}

func (db *Database) isExpenseAcceptable(expense float32) bool {
	return expense <= db.balance() + db.overdraft()
}

func (db *Database) description() string {
	rows, _ := db.con.Query("SELECT v FROM configuration WHERE k = ?", confIncomeDescription)
	defer rows.Close()
	rows.Next()
	var description string
	rows.Scan(&description)
	return description
}

func (db *Database) amount() float32 {
	rows, _ := db.con.Query("SELECT ROUND(v, 2) FROM configuration WHERE k = ?", confIncomeAmount)
	defer rows.Close()
	rows.Next()
	var amount float32
	rows.Scan(&amount)
	return amount
}

func (db *Database) overdraft() float32 {
	rows, _ := db.con.Query("SELECT ROUND(v, 2) FROM configuration WHERE k = ?", confOverdraft)
	defer rows.Close()
	rows.Next()
	var overdraft float32
	rows.Scan(&overdraft)
	return overdraft
}

func (db *Database) insertAllDueIncomes() {
	var dueDates []dueDate
	nextDueDate := dueDate{ month: int(time.Now().Month()), year: time.Now().Year() }
	for !db.hasAutoIncomeForMonth(nextDueDate.month, nextDueDate.year) {
		dueDates = append(dueDates, nextDueDate)
		if nextDueDate.month > 1 {
			nextDueDate = dueDate{ month: nextDueDate.month - 1, year: nextDueDate.year }
		} else {
			nextDueDate = dueDate{ month: 12, year: nextDueDate.year - 1 }
		}
	}
	for i:=len(dueDates) - 1; i >= 0; i-- {
		db.insertAutoIncome(dueDates[i].month, dueDates[i].year)
	}
}

func (db *Database) hasAutoIncomeForMonth(month int, year int) bool {
	match := fmt.Sprintf("%% %02d/%d", month, year)
	rows, _ := db.con.Query(`
			SELECT EXISTS( 
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE ?)
		`, match)
	defer rows.Close()
	rows.Next()
	var result int
	rows.Scan(&result)
	return result > 0
}

// setup

type Setup struct {
	database *Database
}

func (setup *Setup) New(database *Database) {
	setup.database = database
}

func (setup *Setup) SetupOnFirstRun() {
	if _, err := os.Stat(dbFile); err != nil {
		setup.initialize()
	}
}

func (setup *Setup) initialize() {
	setup.database.Connect()
	printSetupPreDatabase()
	setup.database.CreateTables()
	printSetupPostDatabase()
	setup.configure()
}

func (setup *Setup) configure() {
	incomeDescription := inputOrDefault(printSetupDescription, "pocket money")
	incomeAmount := inputOrDefault(printSetupIncome, "100")
	overdraft := inputOrDefault(printSetupOverdraft, "200")
	setup.database.insertIntoConfiguration(confIncomeDescription, incomeDescription)
	setup.database.insertIntoConfiguration(confIncomeAmount, incomeAmount)
	setup.database.insertIntoConfiguration(confOverdraft, overdraft)
	setup.database.insertAutoIncome(int(time.Now().Month()), time.Now().Year())
	printSetupComplete()
}

// loop

type Loop struct {
	database *Database
	keyAdd string
	keySub string
	keyShow string
	keyHelp string
	keyQuit string
}

func (loop *Loop) New(database *Database) {
	loop.database = database
	loop.keyAdd = "+"
	loop.keySub = "-"
	loop.keyShow = "="
	loop.keyHelp = "?"
	loop.keyQuit = ":"
}

func (loop *Loop) Loop() {
	loop.database.Connect()
	loop.database.insertAllDueIncomes()
	printCurrentBalance(loop.database.balance())
	loop.handleInfo()
	var looping = true
	for looping {
		input := input(printEnterInput)
		switch input {
		case loop.keyAdd:
			loop.handleAdd()
		case loop.keySub:
			loop.handleSub()
		case loop.keyShow:
			loop.handleShow()
		case loop.keyHelp:
			loop.handleHelp()
		case loop.keyQuit:
			looping = false
		default:
			if len(input) > 0 && (input[0:1] == loop.keyAdd || input[0:1] == loop.keySub) {
				loop.omg()
			} else {
				loop.handleInfo()
			}
		}
	}
	loop.database.Disconnect()
	printBye()
}

func (loop *Loop) omg() {
	printErrorOmg()
}

func (loop *Loop) handleAdd() {
	loop.addToLedger(1, printIncomeBooked)
}

func (loop *Loop) handleSub() {
	loop.addToLedger(-1, printExpenseBooked)
}

func (loop *Loop) addToLedger(signum int, printSuccessFunction printFunction) {
	description := input(printEnterDescription)
	amount, _ := strconv.ParseFloat(input(printEnterAmount), 32)
	if amount > 0 {
		if signum == 1 || loop.database.isExpenseAcceptable(float32(amount)) {
			loop.database.insertIntoLedger(description, float32(amount))
			printSuccessFunction()
		} else {
			printErrorTooExpensive()
		}
	} else if amount < 0 {
		printErrorNegativeAmount()
	} else {
		printErrorZeroOrInvalidAmount()
	}
}

func (loop *Loop) handleShow() {
	printFormattedBalance(loop.database.balance(), loop.database.transactions())
}

func (loop *Loop) handleInfo() {
	printInfo()
}

func (loop *Loop) handleHelp() {
	printHelp()
}

// utility functions

type printFunction func()

type dueDate struct {
	month int
	year int
}

func prntln(str string) {
	prnt(str)
	prnt("\n")
}

func prnt(str string) {
	fmt.Print(strings.ReplaceAll(str, tab, "\t"))
}

func inputOrDefault(printFunction printFunction, standard string) string {
	printSetupTemplate(printFunction, standard)
	input := input(nil)
	if len(strings.TrimSpace(input)) > 0 {
		return input
	} else {
		return standard
	}
}

func input(printFunction printFunction) string {
	if printFunction != nil {
		printFunction()
	}
	prnt(" > ")
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	return scanner.Text()
}

// print functions

func printBanner() {
	prnt(`
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>Go 1.15 Edition


	`)
}

func printInfo() {
	prnt(`
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

`)
}

func printHelp() {
	prnt(`
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

`)
}

func printSetupPreDatabase() {
	prnt(`
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
`)
}

func printSetupPostDatabase() {
	prnt(`
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

`)
}

func printErrorZeroOrInvalidAmount() {
	prntln("amount is zero or invalid -> action aborted")
}

func printErrorNegativeAmount() {
	prntln("amount must be positive -> action aborted")
}

func printIncomeBooked() {
	prntln("income booked")
}

func printExpenseBooked() {
	prntln("expense booked successfully")
}

func printErrorTooExpensive() {
	prntln("sorry, too expensive -> action aborted")
}

func printErrorOmg() {
	prntln("OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that")
}

func printEnterInput() {
	prnt("input")
}

func printEnterDescription() {
	prnt("description (optional)")
}

func printEnterAmount() {
	prnt("amount")
}

func printSetupComplete() {
	prntln("setup complete, have fun")
}

func printBye() {
	prntln("see ya")
}

func printCurrentBalance(balance float32) {
	prnt(fmt.Sprintf(`
<TAB>current balance: %.2f

`, balance))
}

func printFormattedBalance(balance float32, formattedTransactions string) {
	printCurrentBalance(balance)
	prnt(fmt.Sprintf(
`<TAB>last transactions (up to 30)
<TAB>----------------------------
%s
`, formattedTransactions))
}

func printSetupDescription() {
	prnt("enter description for regular income")
}

func printSetupIncome() {
	prnt("enter regular income")
}

func printSetupOverdraft() {
	prnt("enter overdraft")
}

func printSetupTemplate(printFunction printFunction, standard string) {
	printFunction()
	prnt(fmt.Sprintf(" [default: %s]", standard))
}

// main

func main() {
	printBanner()
	database := Database{}
	setup := Setup{}
	setup.New(&database)
	setup.SetupOnFirstRun()
	loop := Loop{}
	loop.New(&database)
	loop.Loop()
}