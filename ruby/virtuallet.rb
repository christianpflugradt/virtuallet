#!/usr/bin/ruby -w

require 'date'
require 'sqlite3'

DB_FILE = '../db_virtuallet.db'
CONF_INCOME_DESCRIPTION = 'income_description'
CONF_INCOME_AMOUNT = 'income_amount'
CONF_OVERDRAFT = 'overdraft'
TAB = '<TAB>'

class Database

  @db = nil

  def connect
    unless defined? @db
      @db = SQLite3::Database.open DB_FILE
    end
  end

  def disconnect
    @db.close
  end

  def create_tables
    @db.execute <<SQL
      CREATE TABLE ledger (
      description TEXT,
      amount REAL NOT NULL,
      auto_income INTEGER NOT NULL,
      created_by TEXT,
      created_at TIMESTAMP NOT NULL,
      modified_at TIMESTAMP)
SQL
    @db.execute 'CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)'
  end

  def insert_configuration(key, value)
    @db.execute 'INSERT INTO configuration (k, v) VALUES (?, ?)', [key, value]
  end

  def insert_into_ledger(description, amount)
    @db.execute 'INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 0, datetime(\'now\'), \'Ruby 2.7 Edition\')', [description, amount]
  end

  def balance
    (@db.get_first_row 'SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger').at(0)
  end

  def transactions
    formatted = ""
    result = @db.query 'SELECT created_at, CAST(amount AS TEXT), description FROM ledger ORDER BY ROWID DESC LIMIT 30'
    result.each { |row| formatted += "\t#{row.join("\t")}\n" }
    result.close
    formatted
  end

  def income_description
    (@db.get_first_row 'SELECT v FROM configuration WHERE k = ?', CONF_INCOME_DESCRIPTION).at(0)
  end

  def income_amount
    (@db.get_first_row 'SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?', CONF_INCOME_AMOUNT).at(0)
  end

  def overdraft
    (@db.get_first_row 'SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?', CONF_OVERDRAFT).at(0)
  end

  def is_expense_acceptable(expense)
    expense <= balance + overdraft
  end

  def insert_all_due_incomes
    due_dates = Array.new
    due_date = [Time.now.month, Time.now.year]
    until has_auto_income_for_month due_date.at(0), due_date.at(1)
      due_dates << due_date
      due_date = due_date[0] > 1 ? [due_date[0] - 1, due_date[1]] : [12, due_date[1] - 1]
    end
    due_dates.reverse.each { |due_date| insert_auto_income due_date[0], due_date[1]}
  end

  def insert_auto_income(month, year)
    description = "#{self.income_description} #{'%02d' % month}/#{year}"
    amount = income_amount
    @db.execute 'INSERT INTO ledger (description, amount, auto_income, created_at, created_by) VALUES (?, ROUND(?, 2), 1, datetime(\'now\'), \'Ruby 2.7 Edition\')', [description, amount]
  end

  def has_auto_income_for_month(month, year)
    statement = <<SQL
        SELECT COALESCE(EXISTS(
           SELECT auto_income FROM ledger
            WHERE auto_income = 1
            AND description LIKE ?), 0)
SQL
    (@db.get_first_row statement, "#{self.income_description} #{'%02d' % month}/#{year}").at(0) > 0
  end

end

class Loop

  KEY_ADD = '+'
  KEY_SUB = '-'
  KEY_SHOW = '='
  KEY_HELP = '?'
  KEY_QUIT = ':'

  @database = nil

  def initialize(database)
    @database = database
  end

  def loop
    @database.connect
    @database.insert_all_due_incomes
    Util.prnt TextResources.current_balance @database.balance
    handle_info
    looping = true
    while looping
      input = Util.input TextResources.enter_input
      case input
      when KEY_ADD
        handle_add
      when KEY_SUB
        handle_sub
      when KEY_SHOW
        handle_show
      when KEY_HELP
        handle_help
      when KEY_QUIT
        looping = false
      else
        if not input.empty? and [KEY_ADD, KEY_SUB].include? input[0]
          omg
        else
          handle_info
        end
      end
    end
    @database.disconnect
    Util.prnt TextResources.bye
  end

  def omg
    Util.prnt TextResources.error_omg
  end

  def handle_add
    add_to_ledger 1, TextResources.income_booked
  end

  def handle_sub
    add_to_ledger (-1), TextResources.expense_booked
  end

  def add_to_ledger(signum, success_message)
    description = Util.input TextResources.enter_description
    amount = (Util.input TextResources.enter_amount).to_f
    if amount > 0
        if signum == 1 or @database.is_expense_acceptable amount
          @database.insert_into_ledger description, amount * signum
          Util.prnt success_message
          Util.prnt TextResources.current_balance @database.balance
        else
          Util.prnt TextResources.error_too_expensive
        end
    elsif amount < 0
      Util.prnt TextResources.error_negative_amount
    else
      Util.prnt TextResources.error_zero_or_invalid_amount
    end
  end

  def handle_show
    Util.prnt TextResources.formatted_balance @database.balance, @database.transactions
  end

  def handle_info
    Util.prnt TextResources.info
  end

  def handle_help
    Util.prnt TextResources.help
  end

end

class Setup

  @database = nil

  def initialize(database)
    @database = database
  end

  def setup_on_first_run
    unless File.exist?(DB_FILE)
      setup
    end
  end

  def configure
    income_description = Util.read_config_input TextResources.setup_description, 'pocket money'
    income_amount = Util.read_config_input TextResources.setup_income, 100
    overdraft = Util.read_config_input TextResources.setup_overdraft, 200
    @database.insert_configuration CONF_INCOME_DESCRIPTION, income_description
    @database.insert_configuration CONF_INCOME_AMOUNT, income_amount
    @database.insert_configuration CONF_OVERDRAFT, overdraft
    @database.insert_auto_income Time.new.month, Time.new.year
  end

  def setup
    Util.prnt TextResources.setup_pre_database
    @database.connect
    @database.create_tables
    Util.prnt TextResources.setup_post_database
    configure
    Util.prnt TextResources.setup_complete
  end

end

class Util

  def self.prnt(str)
    puts str.gsub TAB, "\t"
  end

  def self.input(prefix)
    print "#{prefix} > "
    STDIN.gets.chomp.strip
  end

  def self.read_config_input(prefix, default)
    result = input TextResources.setup_template prefix, default
    result.empty? ? default.to_s : result
  end

end

class TextResources

  def self.banner
    <<TEXT

<TAB> _                                 _   _         
<TAB>(_|   |_/o                        | | | |        
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_ 
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |  
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/
                                                     
<TAB>Ruby 2.7 Edition                                                 


TEXT
  end

  def self.info
    <<TEXT

<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

TEXT
  end

  def self.help
    <<TEXT

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

TEXT
  end

  def self.setup_pre_database
    <<TEXT
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.

TEXT
  end

  def self.setup_post_database
    <<TEXT
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

TEXT
  end

  def self.error_zero_or_invalid_amount 
    'amount is zero or invalid -> action aborted'
  end

  def self.error_negative_amount
    'amount must be positive -> action aborted'
  end

  def self.income_booked
    'income booked'
  end

  def self.expense_booked
    'expense booked successfully'
  end

  def self.error_too_expensive
    'sorry, too expensive -> action aborted'
  end

  def self.error_omg
    'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that'
  end

  def self.enter_input
    'input'
  end

  def self.enter_description
    'description (optional)'
  end

  def self.enter_amount
    'amount'
  end

  def self.setup_complete
    'setup complete, have fun'
  end

  def self.bye
    'see ya'
  end

  def self.current_balance(balance)
    "\n\tcurrent balance: #{'%.2f' % balance}\n "
  end

  def self.formatted_balance(balance, formatted_last_transactions)
    <<TEXT
#{current_balance balance}
<TAB>last transactions (up to 30)
<TAB>----------------------------
#{formatted_last_transactions}
TEXT
  end

  def self.setup_description
    'enter description for regular income'
  end

  def self.setup_income
    'enter regular income'
  end

  def self.setup_overdraft
    'enter overdraft'
  end

  def self.setup_template(description, default)
    "#{description} [default: #{default}]"
  end

end

Util.prnt TextResources.banner
database = Database.new
setup = Setup.new database
loop = Loop.new database
setup.setup_on_first_run
loop.loop
