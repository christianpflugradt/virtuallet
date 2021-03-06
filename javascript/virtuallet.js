const DB_FILE = '../db_virtuallet.db'
const CONF_INCOME_DESCRIPTION = 'income_description'
const CONF_INCOME_AMOUNT = 'income_amount'
const CONF_OVERDRAFT = 'overdraft'
const TAB = '<TAB>'

const textResources = function () {

    this.banner = function () {
        return `
<TAB> _                                 _   _         
<TAB>(_|   |_/o                        | | | |        
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_ 
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |  
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/
                                                     
<TAB>Node.js v15.10.0 Edition                                                 
                                                     
        `;
    }

    this.info = function () {
        return `
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit
        `;
    }

    this.help = function () {
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
        `;
    }

    this.setupPreDatabase = function () {
        return `
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.`;
    }

    this.setupPostDatabase = function () {
        return `
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.
        `;
    }

    this.errorZeroOrInvalidAmount = function () {
        return 'amount is zero or invalid -> action aborted';
    }

    this.errorNegativeAmount = function () {
        return 'amount must be positive -> action aborted';
    }

    this.incomeBooked = function () {
        return 'income booked';
    }

    this.expenseBooked = function () {
        return 'expense booked successfully';
    }

    this.errorTooExpensive = function () {
        return 'sorry, too expensive -> action aborted';
    }

    this.errorOmg = function () {
        return 'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that';
    }

    this.enterInput = function () {
        return 'input > ';
    }

    this.enterDescription = function () {
        return 'description (optional) > ';
    }

    this.enterAmount = function () {
        return 'amount > ';
    }

    this.setupComplete = function () {
        return 'setup complete, have fun';
    }

    this.bye = function () {
        return 'see ya';
    }

    this.currentBalance = function (balance) {
        return `
<TAB>current balance: ${balance.toFixed(2)}
        `;
    }

    this.formattedBalance = function (balance, formattedLastTransactions) {
        return `
<TAB>current balance: ${Number(balance).toFixed(2)}

<TAB>last transactions (up to 30)
<TAB>----------------------------
${formattedLastTransactions}
    `
    }

    this.setupDescription = function () {
        return 'enter description for regular income';
    }

    this.setupIncome = function () {
        return 'enter regular income';
    }

    this.setupOverdraft = function () {
        return 'enter overdraft';
    }

    this.setupTemplate = function (description, standard) {
        return `${description} [default: ${standard}}] > `;
    }

}

const util = function () {

    this.readline = require('readline-sync')

    this.print = function (text) {
        console.log(String(text).replaceAll(TAB, '\t'));
    }

    this.input = function (question) {
        return this.readline.question(question, () => {});
    }

    this.readConfigInput = function (description, standard) {
        const input = this.input(TextResources.setupTemplate(description, standard));
        return !input ? standard : input;
    }

    this.firstCharMatches = function (str1, str2) {
        return !!str1 && !!str2 ? str1.charAt(0) === str2.charAt(0) : false;
    }

}

const database = function () {

    this.connect = function () {
        if (!this.db) {
            const sqlite3 = require('sqlite3');
            this.db = new sqlite3.Database(DB_FILE)
        }
    }

    this.disconnect = function () {
        this.db.close();
    }

    this.createTables = function (callback) {
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
            this.db.run('CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)', callback);
        });
    }

    this.incomeDescription = function (callback) {
        return this.db.get(`SELECT v FROM configuration WHERE k = '${CONF_INCOME_DESCRIPTION}'`, [], callback);
    }

    this.incomeAmount = function (callback) {
        return this.db.get(`SELECT v FROM configuration WHERE k = '${CONF_INCOME_AMOUNT}'`, [], callback);
    }

    this.overdraft = function (callback) {
        return this.db.get(`SELECT v FROM configuration WHERE k = '${CONF_OVERDRAFT}'`, [], callback);
    }

    this.executeStatement = function (stmt, callback) {
        return this.db.run(stmt, callback);
    }

    this.insertConfiguration = function (key, value, callback) {
        return this.executeStatement(`INSERT INTO configuration (k, v) VALUES ('${key}', '${value}')`, callback)
    }

    this.balance = function (callback) {
        return this.db.get('SELECT ROUND(COALESCE(SUM(amount), 0), 2) AS balance FROM ledger', [], callback);
    }

    this.insertIntoLedger = function (description, amount, callback) {
        return this.executeStatement(`INSERT INTO ledger (description, amount, auto_income, created_at, created_by) 
                    VALUES ('${description}', ${amount}, 0, datetime('now'), 'Node.js v15.10.0 Edition')
                `, callback);
    }

    this.transactions = function (callback) {
        return this.db.all(
            'SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30', [], (err, rows) => {
            callback(rows.map(row => `\t${row.created_at}\t${Number(row.amount).toFixed(2)}\t${row.description}`)
                .join('\n'));
        });
    }

    this.isAcceptableAmount = function (amount, callback) {
        return this.balance((err, row) => {
            this.overdraft((err2, row2) => {
                return callback(row.balance + Number(row2.v) - amount >= 0);
            });
        });
    }

    this.insertAutoIncome = function (month, year, callback) {
        return this.incomeDescription((err, row) => {
            const description = `${row.v} ${String(month).padStart(2, '0')}/${year}`;
            return this.incomeAmount((err, row2) => {
                const amount = row2.v;
                return this.executeStatement(`INSERT INTO ledger (description, amount, auto_income, created_at, created_by) 
                    VALUES ('${description}', ${amount}, 1, datetime('now'), 'Node.js v15.10.0 Edition')
                `, callback);
            })
        })
    }

    this.hasAutoIncomeForMonth = function (month, year, callback) {
        return this.db.get(`SELECT EXISTS(
            SELECT auto_income FROM ledger
            WHERE auto_income = 1
            AND description LIKE '% ${String(month).padStart(2, '0')}/${year}')`, [], callback);
    }

    this.insertAllDueIncomes = function (callback) {
        const today = new Date();
        let month = today.getMonth() + 1;
        let year = today.getFullYear();
        this.checkNextAutoIncome(month, year, [], (dueDates) => {
            this.insertAutoIncomes(dueDates, callback);
        });
    }

    this.checkNextAutoIncome = function (month, year, dueDates, callback) {
        this.hasAutoIncomeForMonth(month, year, (err, row) => {
            if (Object.entries(row)[0][1] !== 1) {
                dueDates.push(new dueDate(month, year));
                if (month > 1) {
                    month -= 1;
                } else {
                    month = 12;
                    year -= 1;
                }
                this.checkNextAutoIncome(month, year, dueDates, callback);
            } else {
                callback(dueDates);
            }
        });
    }

    this.insertAutoIncomes = function (dueDates, callback) {
        this.insertAutoIncomeForDueDate(dueDates.reverse(), 0, callback);
    }

    this.insertAutoIncomeForDueDate = function (dueDates, index, callback) {
        if (dueDates.length > 0) {
            this.insertAutoIncome(dueDates[index].month, dueDates[index].year, () => {
                if (index < dueDates.length - 1) {
                    this.insertAutoIncomeForDueDate(dueDates, index + 1, callback);
                } else {
                    callback();
                }
            });
        } else {
            callback();
        }
    }

}

const setup = function (database) {

    this.database = database;

    this.setupOnFirstRun = function (callback) {
        const fs = require('fs')
        if (!fs.existsSync(DB_FILE)) {
            Util.print(TextResources.setupPreDatabase());
            this.database.connect();
            return this.database.createTables(() => {
                Util.print(TextResources.setupPostDatabase());
                const incomeDescription = Util.readConfigInput(TextResources.setupDescription(), 'pocket money');
                const incomeAmount = Util.readConfigInput(TextResources.setupIncome(), 100);
                const overdraft = Util.readConfigInput(TextResources.setupOverdraft(), 200);
                return this.database.insertConfiguration(CONF_INCOME_DESCRIPTION, incomeDescription, () => {
                    this.database.insertConfiguration(CONF_INCOME_AMOUNT, incomeAmount, () => {
                        this.database.insertConfiguration(CONF_OVERDRAFT, overdraft, () => {
                            const today = new Date();
                            this.database.insertAutoIncome(today.getMonth() + 1, today.getFullYear(), () => {
                                Util.print(TextResources.setupComplete());
                                callback();
                            });
                        })
                    });
                });
            });
        } else {
            callback();
        }
    }

}

const loop = function (database) {

    this.database = database;

    this.KEY_ADD = '+';
    this.KEY_SUB = '-';
    this.KEY_SHOW = '=';
    this.KEY_HELP = '?';
    this.KEY_QUIT = ':';

    this.loop = function () {
        this.database.connect();
        this.database.insertAllDueIncomes(() => {
            this.database.balance((err, row) => {
                Util.print(TextResources.currentBalance(row.balance));
                this.info();
                this.loopIteration();
            });
        });
    }

    this.loopIteration = function () {
        const input = Util.input(TextResources.enterInput())
        switch(input) {
            case this.KEY_ADD: this.add(); break;
            case this.KEY_SUB: this.sub(); break;
            case this.KEY_SHOW: this.show(); break;
            case this.KEY_HELP: this.help(); break;
            case this.KEY_QUIT: this.quit(); break;
            default: this.handleOtherInput(input); break;
        }
    }

    this.add = function () {
        this.addToLedger(1, TextResources.incomeBooked());
    }

    this.sub = function () {
        this.addToLedger(-1, TextResources.expenseBooked());
    }

    this.addToLedger = function (signum, successMessage) {
        const description = Util.input(TextResources.enterDescription());
        const amountInput = Util.input(TextResources.enterAmount());
        const amount = isNaN(Number(amountInput)) ? 0 : Number(amountInput);
        if (amount > 0) {
            this.database.isAcceptableAmount(amount, (isAcceptable) => {
                if (isAcceptable) {
                    this.database.insertIntoLedger(description, amount * signum, () => {
                        Util.print(successMessage);
                        this.database.balance((err, row) => {
                            Util.print(TextResources.currentBalance(row.balance));
                            this.loopIteration();
                        });
                    });
                } else {
                    Util.print(TextResources.errorTooExpensive());
                    this.loopIteration();
                }
            })
        } else if (amount < 0) {
            Util.print(TextResources.errorNegativeAmount());
            this.loopIteration();
        } else {
            Util.print(TextResources.errorZeroOrInvalidAmount());
            this.loopIteration();
        }
    }

    this.show = function () {
        this.database.balance((err, row) => {
            this.database.transactions((transactions) => {
                Util.print(TextResources.formattedBalance(row.balance, transactions));
                this.loopIteration();
            })
        })
    }

    this.help = function () {
        Util.print(TextResources.help());
        this.loopIteration();
    }

    this.handleOtherInput = function (input) {
        Util.firstCharMatches(input, this.KEY_ADD) || Util.firstCharMatches(input, this.KEY_SUB)
            ? Util.print(TextResources.errorOmg())
            : this.info();
        this.loopIteration();
    }

    this.info = function () {
        Util.print(TextResources.info());
    }

    this.quit = function () {
        this.database.disconnect();
        Util.print(TextResources.bye());
    }

}

const dueDate = function (month, year) {
    this.month = month;
    this.year = year;
}

const TextResources = new textResources();
const Util = new util();
const Database = new database();
const Setup = new setup(Database);
const Loop = new loop(Database);

Util.print(TextResources.banner())
Setup.setupOnFirstRun(() => Loop.loop());
