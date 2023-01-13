import Pkg
Pkg.add("SQLite")

using Dates
using Formatting
using SQLite

const DB_FILE = "../db_virtuallet.db"
const CONF_INCOME_DESCRIPTION = "income_description"
const CONF_INCOME_AMOUNT = "income_amount"
const CONF_OVERDRAFT = "overdraft"
const TAB = "<TAB>"

#= Util =#

	prnt(str::String) = print(replace(str, TAB => "\t"))
	prntln(str::String) = prnt("$str\n")
	
	function input(str::String)::String 
		prnt(str)
		readline()
	end
	
	function read_config_input(prefix::String, default::Union{String,Int})::String
		inp = input(setup_template(prefix, default))
		return isempty(inp) ? string(default) : inp
	end

	current_month() = Dates.month(Dates.today())
	current_year() = Dates.year(Dates.today())

#= Database =#

	mutable struct Database
		con::Union{Nothing,SQLite.DB}
	end
	
	createDatabase!() = Database(nothing)
	
	connect!(database::Database) = if (database.con == nothing) database.con = SQLite.DB(DB_FILE) end

	function create_tables!(database::Database)
		DBInterface.execute(database.con, raw"
			CREATE TABLE ledger (
				description TEXT,
				amount REAL NOT NULL,
				auto_income INTEGER NOT NULL,
				created_by TEXT,
				created_at TIMESTAMP NOT NULL,
				modified_at TIMESTAMP)")
		DBInterface.execute(database.con, "CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)")
	end

	insert_configuration!(database::Database, key::String, value::String) = 
		DBInterface.execute(database.con, "INSERT INTO configuration (k, v) VALUES (?, ?)", [key, value])

	insert_into_ledger!(database::Database, description::String, amount::Float64) = DBInterface.execute(database.con,
			raw"INSERT INTO ledger (description, amount, auto_income, created_at, created_by) 
				VALUES (?, ROUND(?, 2), 0, datetime('now'), 'Julia 1.8 Edition')", [description, amount])
				
	balance(database)::Float64 = first(DBInterface.execute(database.con, "SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger"))[1]

	function transactions(database::Database)::String
		formatted = ""
		for row in DBInterface.execute(database.con, "SELECT created_at, CAST(amount AS TEXT), description FROM ledger ORDER BY ROWID DESC LIMIT 30")
			formatted *= "$TAB$(join(row, TAB))\n"
		end
		return formatted
  	end

	income_description(database::Database)::String = first(DBInterface.execute(database.con, "SELECT v FROM configuration WHERE k = ?", [CONF_INCOME_DESCRIPTION]))[1]

	income_amount(database::Database)::Float64 = first(DBInterface.execute(database.con, "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?", [CONF_INCOME_AMOUNT]))[1]
	
	overdraft(database::Database)::Float64 = first(DBInterface.execute(database.con, "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?", [CONF_OVERDRAFT]))[1]

	is_expense_acceptable(database::Database, expense::Float64) = expense <= balance(database) + overdraft(database)

	function insert_all_due_incomes!(database::Database)
		due_dates = []
		due_date = (month = current_month(), year = current_year())
		while !has_auto_income_for_month(database, due_date.month, due_date.year)
			push!(due_dates, due_date)
			due_date = due_date.month > 1 ? (month = due_date.month - 1, year = due_date.year) : (month = 12, year = due_date.year - 1)
		end
		for due_date in reverse(due_dates)
			insert_auto_income!(database, due_date.month, due_date.year)
		end
	end

	insert_auto_income!(database::Database, month::Int, year::Int) = DBInterface.execute(database.con, raw"
		INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
			VALUES (?, ROUND(?, 2), 1, datetime('now'), 'Julia 1.8 Edition')",
		[sprintf1("$(income_description(database)) %02d/$year", month), income_amount(database)])

	has_auto_income_for_month(database::Database, month::Int, year::Int)::Bool = first(DBInterface.execute(database.con, raw"
		SELECT COALESCE(EXISTS(
           SELECT auto_income FROM ledger
            WHERE auto_income = 1
            AND description LIKE ?), 0)",
        [sprintf1("$(income_description(database)) %02d/$year", month)]))[1] > 0

#= SETUP =#

	struct Setup
		database::Database
	end
	
	createSetup!(database::Database) = Setup(database)
		
	setup_on_first_run!(setup::Setup) = if (!isfile(DB_FILE)) initialize!(setup) end
	
	function initialize!(setup::Setup)
		prnt(setup_pre_database())
		connect!(setup.database)
		create_tables!(setup.database)
		prnt(setup_post_database())
		setup!(setup)
		prntln(setup_complete())
	end
	
	function setup!(setup::Setup)
		income_description = read_config_input(setup_description(), "pocket money")
		income_amount = read_config_input(setup_income(), 100)
		overdraft = read_config_input(setup_overdraft(), 200)
		insert_configuration!(setup.database, CONF_INCOME_DESCRIPTION, income_description)
		insert_configuration!(setup.database, CONF_INCOME_AMOUNT, income_amount)
		insert_configuration!(setup.database, CONF_OVERDRAFT, overdraft)
		insert_auto_income!(setup.database, current_month(), current_year())
	end

#= LOOP =#

	KEY_ADD = '+'
	KEY_SUB = '-'
	KEY_SHOW = '='
	KEY_HELP = '?'
	KEY_QUIT = ':'

	struct Loop
		database::Database
	end
	
	createLoop!(database::Database) = Loop(database)

	function loop!(loop::Loop)
		connect!(loop.database)
		insert_all_due_incomes!(loop.database)
		prntln(current_balance(balance(loop.database)))
		handle_info()
		looping = true
		while looping
			inp::Union{String,Char} = input(enter_input())
			if length(inp) == 1
				inp = first(inp)
				if inp == KEY_ADD
					handle_add!(loop)
				elseif inp == KEY_SUB
					handle_sub!(loop)
				elseif inp == KEY_SHOW
					handle_show(loop)
				elseif inp == KEY_HELP
					handle_help()
				elseif inp == KEY_QUIT
					looping = false
				else
					handle_info()
				end
			elseif length(inp) > 1 && first(inp) in [KEY_ADD, KEY_SUB]
				omg()
			else
				handle_info()
			end
		end
		prntln(bye())
	end
	
	omg() = prntln(error_omg())
	handle_add!(loop::Loop) = add_to_ledger!(loop, 1, income_booked())
	handle_sub!(loop::Loop) = add_to_ledger!(loop, -1, expense_booked())
	
	function add_to_ledger!(loop::Loop, signum, success_message)
		description = input(enter_description())
		amount::Float64 = 0
		try
			amount = parse(Float64, input(enter_amount()))
		catch
		end
		if amount > 0
			if signum == 1 || is_expense_acceptable(loop.database, amount)
				insert_into_ledger!(loop.database, description, amount * signum)
				prntln(success_message)
				prntln(current_balance(balance(loop.database)))
			else
				prntln(error_too_expensive())
			end
		elseif amount < 0
			prntln(error_negative_amount())
		else
			prntln(error_zero_or_invalid_amount())
		end
	end
	
	handle_show(loop) = prnt(formatted_balance(balance(loop.database), transactions(loop.database)))
	handle_info() = prnt(info())
	handle_help() = prnt(help())

#= TEXT_RESOURCES =#

	banner() = raw"

<TAB> _                                 _   _         
<TAB>(_|   |_/o                        | | | |        
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_ 
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |  
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/
                                                     
<TAB>Julia 1.8 Edition                                                 

"

	info() = raw"
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

"

	help() = raw"
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

"

	setup_pre_database() = raw"
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
"

	setup_post_database() = raw"
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

"

	error_zero_or_invalid_amount() = "amount is zero or invalid -> action aborted"
	error_negative_amount() = "amount must be positive -> action aborted"
	income_booked() = "income booked"
	expense_booked() = "expense booked successfully"
	error_too_expensive() = "sorry, too expensive -> action aborted"
	error_omg() = "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that"
	enter_input() = "input > "
	enter_description() = "description (optional) > "
	enter_amount() = "amount > "
	setup_complete() = "setup complete, have fun"
	bye() = "see ya"

	current_balance(balance) = raw"
<TAB>current balance: " * sprintf1("%.2f", balance) * raw"
"
	formatted_balance(balance, formatted_last_transactions) = current_balance(balance) * raw"
<TAB>last transactions (up to 30)
<TAB>----------------------------
" * formatted_last_transactions * raw"
"

	setup_description() = "enter description for regular income"
	setup_income() = "enter regular income"
	setup_overdraft() = "enter overdraft"
	setup_template(description, default) = "$description [default: $default] > "

#= MAIN =#

prntln(banner())
database = createDatabase!()
setup = createSetup!(database)
loop = createLoop!(database)
setup_on_first_run!(setup)
loop!(loop)
