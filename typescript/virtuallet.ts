import { Database as Sqlite3Database } from 'sqlite3'
import { existsSync } from 'fs'
import { question  } from 'readline-sync'

const DB_FILE = '../db_virtuallet.db'
const CONF_INCOME_DESCRIPTION = 'income_description'
const CONF_INCOME_AMOUNT = 'income_amount'
const CONF_OVERDRAFT = 'overdraft'
const TAB = '<TAB>'

class Util {

    static print(str: string) {
        console.log(str.replaceAll(TAB, '\t'))
    }

    static input(prefix: string) {
        return question(prefix)
    }

    static readConfigInput(description: string, standard: string | number) {
        const input = Util.input(TextResources.setupTemplate(description, String(standard)))
        return !input ? String(standard) : input
    }

    static firstCharMatches(str1: string, str2: string) {
        return !!str1 && !!str2 ? str1.charAt(0) === str2.charAt(0) : false
    }

}

class Database {

    private db: Sqlite3Database

    connect() {
        if (!this.db) {
            this.db = new Sqlite3Database(DB_FILE)
        }
    }

    disconnect() {
        this.db.close()
    }

    createTables(callback) {
        return this.db.run(`
            CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL,
                auto_income INTEGER NOT NULL,
                created_by TEXT,
                created_at TIMESTAMP NOT NULL,
                modified_at TIMESTAMP
            )
        `, () => {
            this.db.run('CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)', callback)
        })
    }

    incomeDescription(callback) {
        return this.db.get(`SELECT v FROM configuration WHERE k = '${CONF_INCOME_DESCRIPTION}'`, [], callback)
    }

    incomeAmount(callback) {
        return this.db.get(`SELECT v FROM configuration WHERE k = '${CONF_INCOME_AMOUNT}'`, [], callback)
    }

    overdraft(callback) {
        return this.db.get(`SELECT v FROM configuration WHERE k = '${CONF_OVERDRAFT}'`, [], callback)
    }

    executeStatement(sql: string, callback) {
        return this.db.run(sql, callback)
    }

    insertConfiguration(key: string, value: string, callback) {
        return this.executeStatement(`INSERT INTO configuration (k, v) VALUES ('${key}', '${value}')`, callback)
    }

    balance(callback) {
        return this.db.get('SELECT ROUND(COALESCE(SUM(amount), 0), 2) AS balance FROM ledger', [], callback)
    }

    insertIntoLedger(description: string, amount: number, callback) {
        return this.executeStatement(`INSERT INTO ledger (description, amount, auto_income, created_at, created_by) 
                    VALUES ('${description}', ${amount}, 0, datetime('now'), 'TypeScript 5.3 Edition')
                `, callback)
    }

    transactions(callback) {
        interface TransactionRow { created_at: string, amount: number, description: string }
        return this.db.all(
            'SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30', [], (err, rows) => {
            callback((rows as TransactionRow[]).map(row => `\t${row.created_at}\t${Number(row.amount).toFixed(2)}\t${row.description}`)
                .join('\n'))
        })
    }

    isAcceptableAmount(amount: number, callback) {
        return this.balance((err, row) => {
            this.overdraft((err2, row2) => {
                return callback(row.balance + Number(row2.v) - amount >= 0)
            })
        })
    }

    insertAutoIncome(month: number, year: number, callback) {
        return this.incomeDescription((err, row) => {
            const description = `${row.v} ${String(month).padStart(2, '0')}/${year}`
            return this.incomeAmount((err, row2) => {
                const amount = row2.v
                return this.executeStatement(`INSERT INTO ledger (description, amount, auto_income, created_at, created_by) 
                    VALUES ('${description}', ${amount}, 1, datetime('now'), 'TypeScript 5.3 Edition')
                `, callback)
            })
        })
    }

    hasAutoIncomeForMonth(month: number, year: number, callback) {
        return this.db.get(`SELECT EXISTS(
            SELECT auto_income FROM ledger
            WHERE auto_income = 1
            AND description LIKE '% ${String(month).padStart(2, '0')}/${year}')`, [], callback)
    }

    insertAllDueIncomes(callback) {
        const today = new Date()
        let month = today.getMonth() + 1
        let year = today.getFullYear()
        this.checkNextAutoIncome(month, year, [], (dueDates) => {
            this.insertAutoIncomes(dueDates, callback)
        })
    }

    checkNextAutoIncome(month: number, year: number, dueDates: [number, number][], callback) {
        this.hasAutoIncomeForMonth(month, year, (err, row) => {
            if (Object.entries(row)[0][1] !== 1) {
                dueDates.push([month, year])
                if (month > 1) {
                    month -= 1
                } else {
                    month = 12
                    year -= 1
                }
                this.checkNextAutoIncome(month, year, dueDates, callback)
            } else {
                callback(dueDates)
            }
        })
    }

    insertAutoIncomes(dueDates: [number, number][], callback) {
        this.insertAutoIncomeForDueDate(dueDates.reverse(), 0, callback)
    }

    insertAutoIncomeForDueDate(dueDates: [number, number][], index: number, callback) {
        if (dueDates.length > 0) {
            this.insertAutoIncome(dueDates[index][0], dueDates[index][1], () => {
                if (index < dueDates.length - 1) {
                    this.insertAutoIncomeForDueDate(dueDates, index + 1, callback)
                } else {
                    callback()
                }
            })
        } else {
            callback()
        }
    }

}

class Setup {

    constructor(private readonly database: Database) {}

    setupOnFirstRun(callback) {
        if (!existsSync(DB_FILE)) {
            Util.print(TextResources.setupPreDatabase())
            this.database.connect()
            return this.database.createTables(() => {
                Util.print(TextResources.setupPostDatabase())
                const incomeDescription = Util.readConfigInput(TextResources.setupDescription(), 'pocket money')
                const incomeAmount = Util.readConfigInput(TextResources.setupIncome(), 100)
                const overdraft = Util.readConfigInput(TextResources.setupOverdraft(), 200)
                return this.database.insertConfiguration(CONF_INCOME_DESCRIPTION, incomeDescription, () => {
                    this.database.insertConfiguration(CONF_INCOME_AMOUNT, incomeAmount, () => {
                        this.database.insertConfiguration(CONF_OVERDRAFT, overdraft, () => {
                            const today = new Date()
                            this.database.insertAutoIncome(today.getMonth() + 1, today.getFullYear(), () => {
                                Util.print(TextResources.setupComplete())
                                callback()
                            })
                        })
                    })
                })
            })
        } else {
            callback()
        }
    }

}

class Loop {

    constructor(private readonly database: Database) {}

    private static readonly KEY_ADD = '+'
    private static readonly KEY_SUB = '-'
    private static readonly KEY_SHOW = '='
    private static readonly KEY_HELP = '?'
    private static readonly KEY_QUIT = ':'

    loop() {
        this.database.connect()
        this.database.insertAllDueIncomes(() => {
            this.database.balance((err, row) => {
                Util.print(TextResources.currentBalance(row.balance))
                this.info()
                this.loopIteration()
            })
        })
    }

    loopIteration() {
        const input = Util.input(TextResources.enterInput())
        switch(input) {
            case Loop.KEY_ADD: this.add(); break
            case Loop.KEY_SUB: this.sub(); break
            case Loop.KEY_SHOW: this.show(); break
            case Loop.KEY_HELP: this.help(); break
            case Loop.KEY_QUIT: this.quit(); break
            default: this.handleOtherInput(input); break
        }
    }

    add() {
        this.addToLedger(1, TextResources.incomeBooked())
    }

    sub() {
        this.addToLedger(-1, TextResources.expenseBooked())
    }

    addToLedger(signum: number, successMessage: string) {
        const description = Util.input(TextResources.enterDescription())
        const amountInput = Util.input(TextResources.enterAmount())
        const amount = isNaN(Number(amountInput)) ? 0 : Number(amountInput)
        if (amount > 0) {
            this.database.isAcceptableAmount(amount, (isAcceptable) => {
                if (isAcceptable) {
                    this.database.insertIntoLedger(description, amount * signum, () => {
                        Util.print(successMessage)
                        this.database.balance((err, row) => {
                            Util.print(TextResources.currentBalance(row.balance))
                            this.loopIteration()
                        })
                    })
                } else {
                    Util.print(TextResources.errorTooExpensive())
                    this.loopIteration()
                }
            })
        } else if (amount < 0) {
            Util.print(TextResources.errorNegativeAmount())
            this.loopIteration()
        } else {
            Util.print(TextResources.errorZeroOrInvalidAmount())
            this.loopIteration()
        }
    }

    show() {
        this.database.balance((err, row) => {
            this.database.transactions((transactions) => {
                Util.print(TextResources.formattedBalance(row.balance, transactions))
                this.loopIteration()
            })
        })
    }

    help() {
        Util.print(TextResources.help())
        this.loopIteration()
    }

    handleOtherInput(input: string) {
        Util.firstCharMatches(input, Loop.KEY_ADD) || Util.firstCharMatches(input, Loop.KEY_SUB)
            ? Util.print(TextResources.errorOmg())
            : this.info()
        this.loopIteration()
    }

    info() {
        Util.print(TextResources.info())
    }

    quit() {
        this.database.disconnect()
        Util.print(TextResources.bye())
    }

}

class TextResources {

    static banner() {
        return `
<TAB> _                                 _   _         
<TAB>(_|   |_/o                        | | | |        
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_ 
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |  
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/
                                                     
<TAB>TypeScript 5.3 Edition
                                                     
        `
    }

    static info() {
        return `
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit
        `
    }

    static help() {
        return `
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
        `
    }

    static setupPreDatabase() {
        return `
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.`
    }

    static setupPostDatabase() {
        return `
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.
        `
    }

    static errorZeroOrInvalidAmount() {
        return 'amount is zero or invalid -> action aborted'
    }

    static errorNegativeAmount() {
        return 'amount must be positive -> action aborted'
    }

    static incomeBooked() {
        return 'income booked'
    }

    static expenseBooked() {
        return 'expense booked successfully'
    }

    static errorTooExpensive() {
        return 'sorry, too expensive -> action aborted'
    }

    static errorOmg() {
        return 'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that'
    }

    static enterInput() {
        return 'input > '
    }

    static enterDescription() {
        return 'description (optional) > '
    }

    static enterAmount() {
        return 'amount > '
    }

    static setupComplete() {
        return 'setup complete, have fun'
    }

    static bye() {
        return 'see ya'
    }

    static currentBalance(balance: number) {
        return `
<TAB>current balance: ${balance.toFixed(2)}
        `
    }

    static formattedBalance(balance: number, formattedLastTransactions: string) {
        return `
<TAB>current balance: ${balance.toFixed(2)}

<TAB>last transactions (up to 30)
<TAB>----------------------------
${formattedLastTransactions}
    `
    }

    static setupDescription() {
        return 'enter description for regular income'
    }

    static setupIncome() {
        return 'enter regular income'
    }

    static setupOverdraft() {
        return 'enter overdraft'
    }

    static setupTemplate(description: string, standard: string) {
        return `${description} [default: ${standard}}] > `
    }

}

const database = new Database()
const setup = new Setup(database)
const loop = new Loop(database)

Util.print(TextResources.banner())
setup.setupOnFirstRun(() => loop.loop())
