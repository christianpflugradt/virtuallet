#!/usr/bin/python3

import sqlite3 as sql
from os import path
from datetime import datetime

DB_FILE = 'db_virtuallet.db'
CONF_INCOME_DESCRIPTION = 'income_description'
CONF_INCOME_AMOUNT = 'income_amount'
CONF_OVERDRAFT = "overdraft"


class Database:

    def __init__(self):
        self.con = None
        self.cur = None

    def connect(self):
        if self.con is None:
            self.con = sql.connect(DB_FILE)
            self.cur = self.con.cursor()

    def disconnect(self):
        self.con.close()

    def create_tables(self):
        self.cur.execute("""
            CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL, 
                auto_income INTEGER NOT NULL,
                created_at TIMESTAMP NOT NULL, 
                modified_at TIMESTAMP)""")
        self.cur.execute("CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)")

    def insert_configuration(self, key, value):
        self.cur.execute("INSERT INTO configuration (k, v) VALUES ('%s', '%s')" % (key, value))
        self.con.commit()

    def insert_into_ledger(self, description, amount):
        self.cur.execute("INSERT INTO ledger (description, amount, auto_income, created_at) VALUES (?, ?, ?, ?)", (description, amount, 0, datetime.now()))
        self.con.commit()

    def balance(self):
        self.cur.execute("SELECT SUM(amount) FROM ledger")
        res = self.cur.fetchone()[0]
        return 0 if res is None else float(res)

    def transactions(self):
        self.cur.execute("SELECT created_at, amount, description FROM ledger ORDER BY created_at DESC LIMIT 30")
        res = self.cur.fetchall()
        return '\n'.join([''.join(['\t{:3}'.format(col) for col in row]) for row in res])

    def __income_description(self):
        self.cur.execute("SELECT v FROM configuration WHERE k = '%s'" % CONF_INCOME_DESCRIPTION)
        return self.cur.fetchone()[0]

    def __income_amount(self):
        self.cur.execute("SELECT v FROM configuration WHERE k = '%s'" % CONF_INCOME_AMOUNT)
        return float(self.cur.fetchone()[0])

    def __overdraft(self):
        self.cur.execute("SELECT v FROM configuration WHERE k = '%s'" % CONF_OVERDRAFT)
        return float(self.cur.fetchone()[0])

    def is_expense_acceptable(self, expense):
        return expense <= self.balance() + self.__overdraft()

    def insert_all_due_incomes(self):
        due_dates = []
        due_date = (datetime.today().month, datetime.today().year)
        while not self.has_auto_income_for_month(due_date[0], due_date[1]):
            due_dates.append(due_date)
            due_date = (due_date[0] - 1, due_date[1]) if due_date[0] > 1 else (12, due_date[1] - 1)
        due_dates.reverse()
        for due_date in due_dates:
            self.insert_auto_income(due_date[0], due_date[1])

    def insert_auto_income(self, month, year):
        description = "%s %02d/%d" % (self.__income_description(), month, year)
        amount = self.__income_amount()
        self.cur.execute("INSERT INTO ledger (description, amount, auto_income, created_at) VALUES (?, ?, ?, ?)", (description, amount, 1, datetime.now()))
        self.con.commit()

    def has_auto_income_for_month(self, month, year):
        self.cur.execute("""
            SELECT EXISTS(
                SELECT auto_income FROM ledger 
                WHERE CAST(strftime('%%m', created_at) AS DECIMAL) = %d
                AND CAST(strftime('%%Y', created_at) AS DECIMAL) = %d
                AND auto_income = 1)""" % (month, year))
        return self.cur.fetchone()[0] > 0


class Loop:

    KEY_ADD = '+'
    KEY_SUB = '-'
    KEY_SHOW = '='
    KEY_HELP = '?'
    KEY_QUIT = ':'

    db = None

    def __init__(self, database):
        self.db = database

    def loop(self):
        self.db.connect()
        self.db.insert_all_due_incomes()
        print(TextResources.current_balance(self.db.balance()))
        self.__handle_info()
        looping = True
        while looping:
            inp = input(TextResources.enter_input())
            if inp == self.KEY_ADD:
                self.__handle_add()
            elif inp == self.KEY_SUB:
                self.__handle_sub()
            elif inp == self.KEY_SHOW:
                self.__handle_show()
            elif inp == self.KEY_HELP:
                Loop.__handle_help()
            elif inp == self.KEY_QUIT:
                looping = False
            elif inp[0] in [self.KEY_ADD, self.KEY_SUB]:
                Loop.__omg()
            else:
                Loop.__handle_info()
        db.disconnect()
        print(TextResources.bye())

    @staticmethod
    def __omg():
        print(TextResources.error_omg())

    def __handle_add(self):
        self.__add_to_ledger(-1, TextResources.income_booked());

    def __handle_sub(self):
        self.__add_to_ledger(-1, TextResources.expense_booked());

    def __add_to_ledger(self, signum, success_message):
        description = input(TextResources.enter_description())
        amount = Util.float_val(input(TextResources.enter_amount()))
        if amount > 0:
            if self.db.is_expense_acceptable(amount):
                self.db.insert_into_ledger(description, amount * signum)
                print(success_message)
            else:
                print(TextResources.error_too_expensive())
        elif amount < 0:
            print(TextResources.error_negative_amount())
        else:
            print(TextResources.error_zero_or_invalid_amount())

    def __handle_show(self):
        print(TextResources.formatted_balance(self.db.balance(), self.db.transactions()))

    @staticmethod
    def __handle_info():
        print(TextResources.info())

    @staticmethod
    def __handle_help():
        print(TextResources.help())


class Setup:

    db = None

    def __init__(self, database):
        self.db = database

    def setup_on_first_run(self):
        if not path.exists(DB_FILE):
            self.__initialize()

    def __initialize(self):
        print(TextResources.setup_pre_database())
        self.db.connect()
        self.db.create_tables()
        print(TextResources.setup_post_database())
        self.__setup()
        print(TextResources.setup_complete())

    def __setup(self):
        income_description = Util.read_config_input(TextResources.setup_description(), 'pocket money')
        income_amount = Util.read_config_input(TextResources.setup_income(), 100)
        overdraft = Util.read_config_input(TextResources.setup_overdraft(), 200)
        self.db.insert_configuration(CONF_INCOME_DESCRIPTION, income_description)
        self.db.insert_configuration(CONF_INCOME_AMOUNT, income_amount)
        self.db.insert_configuration(CONF_OVERDRAFT, overdraft)
        self.db.insert_auto_income(datetime.today().month, datetime.today().year)


class Util:

    @staticmethod
    def float_val(string):
        try:
            return float(string)
        except:
            return 0

    @staticmethod
    def read_config_input(description, default):
        inp = input(TextResources.setup_template(description, default))
        return str(default) if inp == '' else inp


class TextResources:

    @staticmethod
    def banner():
        return """
     _                                 _   _         
    (_|   |_/o                        | | | |        
      |   |      ,_  _|_         __,  | | | |  _ _|_ 
      |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |  
       \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/
                                                     
    Python 3 Edition                                                 
                                                     
        """

    @staticmethod
    def info():
        return """
        Commands:
        - press plus (+) to add an irregular income
        - press minus (-) to add an expense
        - press equals (=) to show balance and last transactions
        - press question mark (?) for even more info about this program
        - press colon (:) to exit
        """

    @staticmethod
    def help():
        return """
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
"""

    @staticmethod
    def setup_pre_database():
        return """
        Database file not found.
        Database will be initialized. This may take a while... NOT."""

    @staticmethod
    def setup_post_database():
        return """
        Database initialized.
        Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
        Press enter to accept the default or input something else. There is no validation 
        because I know you will not make a mistake. No second chances. If you f**k up, 
        you will have to either delete the database file or edit it using a sqlite database browser.
        """

    @staticmethod
    def error_zero_or_invalid_amount():
        return "amount is zero or invalid -> action aborted"

    @staticmethod
    def error_negative_amount():
        return "amount must be positive -> action aborted"

    @staticmethod
    def income_booked():
        return "income booked"

    @staticmethod
    def expense_booked():
        return "expense booked successfully"

    @staticmethod
    def error_too_expensive():
        return "sorry, too expensive -> action aborted"

    @staticmethod
    def error_omg():
        return "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that"

    @staticmethod
    def enter_input():
        return "input > "

    @staticmethod
    def enter_description():
        return "description (optional) > "

    @staticmethod
    def enter_amount():
        return "amount > "

    @staticmethod
    def setup_complete():
        return "setup complete, have fun"

    @staticmethod
    def bye():
        return "see ya"

    @staticmethod
    def current_balance(balance):
        return """
        current balance: %s
        """ % balance

    @staticmethod
    def formatted_balance(balance, formatted_last_transactions):
        return """
        current balance: %s

        last transactions (up to 30)
        ----------------------------
%s
        """ % (balance, formatted_last_transactions)

    @staticmethod
    def setup_description():
        return "enter description for regular income"

    @staticmethod
    def setup_income():
        return "enter regular income"

    @staticmethod
    def setup_overdraft():
        return "enter overdraft"

    @staticmethod
    def setup_template(description, default):
        return "%s [default: %s] > " % (description, default)


db = Database()
setup = Setup(db)
loop = Loop(db)

if __name__ == '__main__':
    print(TextResources.banner())
    setup.setup_on_first_run()
    loop.loop()
