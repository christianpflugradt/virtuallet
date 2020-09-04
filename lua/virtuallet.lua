local DB_FILE <const> = '../db_virtuallet.db'
local CONF_INCOME_DESCRIPTION <const> = 'income_description'
local CONF_INCOME_AMOUNT <const> = 'income_amount'
local CONF_OVERDRAFT <const> = 'overdraft'

-- database

Database = { sqlite3 = nil, con = nil }

function Database:new()
    local database = {}
    setmetatable(database, self)
    self.__index = self
    self.sqlite3 = require 'lsqlite3'
    return database
end

function Database:connect()
    if self.con == nil then
        self.con = self.sqlite3.open(DB_FILE)
    end
end

function Database:disconnect()
    self.con:close()
end

function Database:execute(sql)
    self.con:exec(sql, nil, nil)
end

function Database:queryOneField(sql)
    for row in self.con:rows(sql) do
        return row[1]
    end
end

function Database:createTables()
    self:execute([=[
        CREATE TABLE ledger (description TEXT, amount REAL NOT NULL, auto_income INTEGER NOT NULL,
            created_at TIMESTAMP NOT NULL, modified_at TIMESTAMP);
        CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL);
    ]=])
end

function Database:insertIntoConfiguration(key, value)
    self:execute(string.format("INSERT INTO configuration (k, v) VALUES ('%s', '%s')", key, value))
end

function Database:insertIntoLedger(description, amount)
    self:execute(string.format([[
        INSERT INTO ledger (description, amount, auto_income, created_at)
        VALUES ('%s', ROUND(%s, 2), 0, datetime('now'))]],
        description, amount))
end

function Database:insertAutoIncome(month, year)
    local description = string.format("%s %02d/%s", self:incomeDescription(), tonumber(month), year)
    local amount = self:incomeAmount()
    self:execute(string.format([[
        INSERT INTO ledger (description, amount, auto_income, created_at)
        VALUES ('%s', ROUND(%s, 2), 1, datetime('now'))]],
        description, amount))
end

function Database:isExpenseAcceptable(expense)
    return expense <= tonumber(self:balance()) + tonumber(self:overdraft())
end

function Database:transactions()
    allRows = ''
    for row in self.con:rows('SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30') do
            formattedRow = string.format('        %s\t%s\t%s\n', row[1], row[2], row[3])
         allRows = allRows..formattedRow
    end
    return allRows
end

function Database:balance()
    return self:queryOneField('SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger')
end

function Database:incomeDescription()
    return self:queryOneField(string.format("SELECT v FROM configuration WHERE k = '%s'", CONF_INCOME_DESCRIPTION))
end

function Database:incomeAmount()
    return self:queryOneField(string.format("SELECT v FROM configuration WHERE k = '%s'", CONF_INCOME_AMOUNT))
end

function Database:overdraft()
    return self:queryOneField(string.format("SELECT v FROM configuration WHERE k = '%s'", CONF_OVERDRAFT))
end

function Database:insertAllDueIncomes()
    local due_dates = { month = 0, year = 0 }
    local index = 0
    due_dates[index] = { month = tonumber(os.date('%m')), year = tonumber(os.date('%Y')) }
    while not self:hasAutoIncomeForMonth(due_dates[index].month, due_dates[index].year) do
        index = index + 1
        if due_dates[index - 1].month > 1 then
            due_dates[index] = { month = due_dates[index-1].month - 1, year = due_dates[index-1].year }
        else
            due_dates[index] = { month = 12, year = due_dates[index-1].year - 1 }
        end
    end
    for i=index-1, 1, -1 do
        self:insertAutoIncome(due_dates[i].month, due_dates[i].year)
    end
end

function Database:hasAutoIncomeForMonth(month, year)
    return tonumber(self:queryOneField(string.format([[
        SELECT EXISTS(
            SELECT auto_income FROM ledger
            WHERE auto_income = 1
            AND description LIKE '%s')]], string.format('%% %02d/%d', month, year)))) > 0
end

-- setup

Setup = { database = nil }

function Setup:new(db)
    local setup = {}
    setmetatable(setup, self)
    self.__index = self
    self.database = db
    return setup
end

function Setup:setupOnFirstRun()
    if not databaseFileExists() then
        self:setup()
    end
end

function Setup:configure()
    local incomeDescription = inputWithDefault(printSetupDescription, 'pocket money')
    local incomeAmount = inputWithDefault(printSetupIncome, '100')
    local overdraft = inputWithDefault(printSetupOverdraft, '200')
    self.database:insertIntoConfiguration(CONF_INCOME_DESCRIPTION, incomeDescription)
    self.database:insertIntoConfiguration(CONF_INCOME_AMOUNT, incomeAmount)
    self.database:insertIntoConfiguration(CONF_OVERDRAFT, overdraft)
    self.database:insertAutoIncome(os.date('%m'),  os.date('%Y'))
end

function Setup:setup()
    printSetupPreDatabase()
    self.database:connect()
    self.database:createTables()
    printSetupPostDatabase()
    self:configure()
    printSetupComplete()
end

-- loop

Loop = { database = nil, KEY_ADD = '+', KEY_SUB = '-', KEY_SHOW = '=', KEY_HELP = '?', KEY_QUIT = ':' }

function Loop:new(db)
    local loop = {}
    setmetatable(loop, self)
    self.__index = self
    self.database = db
    return loop
end

function Loop:loop()
    self.database:connect()
    self.database:insertAllDueIncomes()
    printCurrentBalance(self.database:balance())
    self:handleInfo()
    looping = true
    while looping do
        local input = input(printEnterInput)
        if input == self.KEY_ADD then
            self:handleAdd()
        elseif input == self.KEY_SUB then
            self:handleSub()
        elseif input == self.KEY_SHOW then
            self:handleShow()
        elseif input == self.KEY_HELP then
            self:handleHelp()
        elseif input == self.KEY_QUIT then
            looping = false
        elseif input:sub(1,1) == self.KEY_ADD or input:sub(1,1) == self.KEY_SUB then
            printErrorOmg()
        else
            self:handleInfo()
        end
    end
    self.database:disconnect()
    printBye()
end

function Loop:handleAdd()
    self:addToLedger(1, printIncomeBooked)
end

function Loop:handleSub()
    self:addToLedger(-1, printExpenseBooked)
end

function Loop:addToLedger(signum, printSuccessFunction)
    description = input(printEnterDescription)
    amount = tonumber(input(printEnterAmount))
    if amount > 0 then
        if signum == 1 or self.database:isExpenseAcceptable(amount) then
            self.database:insertIntoLedger(description, amount * signum)
            printSuccessFunction()
        else
            printErrorTooExpensive()
        end
    elseif amount < 0 then
        printErrorNegativeAmount()
    else
        printErrorZeroOrInvalidAmount()
    end
end

function Loop:handleShow()
    printFormattedBalance(self.database:balance(), self.database:transactions())
end

function Loop:handleInfo()
    printInfo()
end

function Loop:handleHelp()
    printHelp()
end

-- utility functions

function databaseFileExists()
    local result = false
    local file <const> = io.open(DB_FILE, 'r')
    if file ~= nil then
        io.close(file)
        result = true
    end
    return result
end

function isNullOrBlank(str)
    return str == nil or str:match('%S') == nil
end

function input(printFunction)
    if printFunction ~= nil then
        printFunction()
    end
    io.write(' > ')
    return io.read()
end

function inputWithDefault(printFunction, default)
    printSetupTemplate(printFunction, default)
    local input = input(nil)
    if not isNullOrBlank(input) then
        return input
    else
        return default
    end
end

-- print functions

function printBanner()
    io.write([[

     _                                 _   _
    (_|   |_/o                        | | | |
      |   |      ,_  _|_         __,  | | | |  _ _|_
      |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
       \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

    Lua 5.4 Edition


]])
end

function printInfo()
    io.write([[

        Commands:
        - press plus (+) to add an irregular income
        - press minus (-) to add an expense
        - press equals (=) to show balance and last transactions
        - press question mark (?) for even more info about this program
        - press colon (:) to exit

]])
end

function printHelp()
    io.write([[

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

]])
end

function printSetupPreDatabase()
   io.write([[

        Database file not found.
        Database will be initialized. This may take a while... NOT.

]])
end

function printSetupPostDatabase()
    io.write([[
        Database initialized.
        Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
        Press enter to accept the default or input something else. There is no validation
        because I know you will not make a mistake. No second chances. If you f**k up,
        you will have to either delete the database file or edit it using a sqlite database browser.

]])
end

function printErrorZeroOrInvalidAmount()
    print('amount is zero or invalid -> action aborted')
end

function printErrorNegativeAmount()
    print('amount must be positive -> action aborted')
end

function printIncomeBooked()
    print('income booked')
end

function printExpenseBooked()
    print('expense booked successfully')
end

function printErrorTooExpensive()
    print('sorry, too expensive -> action aborted')
end

function printErrorOmg()
    print('OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that')
end

function printEnterInput()
    io.write('input')
end

function printEnterDescription()
    io.write('description (optional)')
end

function printEnterAmount()
    io.write('amount')
end

function printSetupComplete()
    print('setup complete, have fun')
end

function printBye()
    print('see ya')
end

function printCurrentBalance(balance)
    print(string.format([[

        current balance: %s
        ]], balance))
end

function printFormattedBalance(balance, formattedTransactions)
    printCurrentBalance(balance)
    io.write(string.format([[
        last transactions (up to 30)
        ----------------------------
%s
]], formattedTransactions))
end

function printSetupDescription()
    io.write('enter description for regular income')
end

function printSetupIncome()
    io.write('enter regular income')
end

function printSetupOverdraft()
    io.write('enter overdraft')
end

function printSetupTemplate(printFunction, default)
    printFunction()
    io.write(string.format(' [default: %s]', default))
end

-- main

printBanner()
local db = Database:new()
local setup = Setup:new(db)
local loop = Loop:new(db)
setup:setupOnFirstRun()
loop:loop()