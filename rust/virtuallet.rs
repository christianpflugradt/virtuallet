use chrono::Datelike;
use rusqlite::Connection;
use rusqlite::params;
use std::path::Path;

const DB_FILE: &str = "../db_virtuallet.db";
const CONF_INCOME_DESCRIPTION: &str = "income_description";
const CONF_INCOME_AMOUNT: &str = "income_amount";
const CONF_OVERDRAFT: &str = "overdraft";
const TAB: &str = "<TAB>";

pub mod util {

    use std::io::Write;
    use self::super::TAB;
    use self::super::text_resources;

    pub fn print(msg: &str) {
        std::io::stdout().write_all(str::replace(msg, TAB, "\t").as_bytes()).unwrap();
    }

    pub fn println(msg: &str) {
        print(msg);
        print("\n");
    }

    pub fn input(msg: &str) -> String {
        print(msg);
        std::io::stdout().flush().unwrap();
        let mut input = String::new();
        std::io::stdin().read_line(&mut input).unwrap();
        return input.trim().to_string();
    }

    pub fn read_config_input(description: &str, standard: &str) -> String {
        let user_input = input(&text_resources::setup_template(description, standard));
        return if user_input.trim().is_empty() {
            standard.to_string()
        } else {
            user_input
        };
    }

    pub fn first_char(str: &str) -> char {
        return str.chars().next().unwrap();
    }

}

struct Database {
    connection: Option<Connection>
}

impl <'a> Database {

    pub fn new() -> Self {
        return Database { connection: None }
    }

    pub fn connect(&mut self) {
        self.connection = Some(Connection::open(DB_FILE).unwrap());
    }

    fn con(&self) -> &Connection {
        return self.connection.as_ref().unwrap();
    }

    pub fn disconnect(&mut self) {
        self.connection.take().unwrap().close();
    }

    pub fn create_tables(&self) {
        self.con().execute(
            "CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL,
                auto_income INTEGER NOT NULL,
                created_by TEXT,
                created_at TIMESTAMP NOT NULL,
                modified_at TIMESTAMP)",
            [],
        );
        self.con().execute("CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)", []);
    }

    pub fn insert_configuration(&self, key: &str, value: &str) {
        self.con().execute("INSERT INTO configuration (k, v) VALUES (?1, ?2)", params![key, value]);
    }

    pub fn insert_into_ledger(&self, description: &str, amount: f64) {
        self.con().execute(
            "INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
                VALUES (?1, ROUND(?2, 2), 0, datetime('now'), 'Rust 1.61 Edition')",
            params![description, amount]);
    }

    pub fn balance(&self) -> f32 {
        let mut stmt = self.con().prepare("SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger").unwrap();
        let mut result = stmt.query([]).unwrap();
        return result.next().unwrap().unwrap()
            .get(0).unwrap();
    }

    pub fn transactions(&self) -> String {
        let mut stmt = self.con().prepare("SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30").unwrap();
        let mut result = stmt.query([]).unwrap();
        let mut rows = Vec::new();
        while let Some(row) = result.next().unwrap() {
            let created_at: String = row.get(0).unwrap();
            let amount: f32 = row.get(1).unwrap();
            let description: String = row.get(2).unwrap();
            rows.push(format!("\t{}\t{:.2}\t{}", created_at, amount, description));
        }
        return format!("{}\n", rows.join("\n"));
    }

    pub fn income_description(&self) -> String {
        let mut stmt = self.con().prepare("SELECT v FROM configuration WHERE k = ?1").unwrap();
        let mut result = stmt.query(params![CONF_INCOME_DESCRIPTION]).unwrap();
        return result.next().unwrap().unwrap().get(0).unwrap();
    }

    pub fn income_amount(&self) -> f32 {
        let mut stmt = self.con().prepare("SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?1").unwrap();
        let mut result = stmt.query(params![CONF_INCOME_AMOUNT]).unwrap();
        return result.next().unwrap().unwrap().get(0).unwrap();
    }

    pub fn overdraft(&self) -> f32 {
        let mut stmt = self.con().prepare("SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?1").unwrap();
        let mut result = stmt.query(params![CONF_OVERDRAFT]).unwrap();
        return result.next().unwrap().unwrap().get(0).unwrap();
    }

    pub fn is_expense_acceptable(&self, expense: f64) -> bool {
        return (self.balance() as f64 + self.overdraft() as f64 - expense) >= 0.0;
    }

    pub fn insert_all_due_incomes(&self) {
        let mut due_date: (u32, i32) = (chrono::Local::today().month(), chrono::Local::today().year());
        let mut due_dates: Vec<(u32, i32)> = Vec::new();
        while !self.has_auto_income_for_month(due_date.0, due_date.1) {
            due_dates.push(due_date);
            due_date = if due_date.0 > 1 { (due_date.0 - 1, due_date.1) } else { (12, due_date.1 - 1) };
        }
        for due_date in due_dates.iter().rev() {
            self.insert_auto_income(due_date.0, due_date.1);
        }
    }

    fn has_auto_income_for_month(&self, month: u32, year: i32) -> bool {
        let description_matcher = format!("'%% {:0>2}/{}')", month, year);
        let mut stmt = self.con().prepare(&format!(
            "{}{}",
            "SELECT EXISTS(
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE ",
            description_matcher)).unwrap();
        let mut result = stmt.query([]).unwrap();
        let exists: i32 = result.next().unwrap().unwrap().get(0).unwrap();
        return exists == 1;
    }

    pub fn insert_auto_income(&self, month: u32, year: i32) {
        let description = format!("{} {:0>2}/{}", self.income_description(), month, year);
        let amount = self.income_amount();
        self.con().execute(
            "INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
                VALUES (?1, ROUND(?2, 2), 1, datetime('now'), 'Rust 1.61 Edition')",
            params![description, amount]);
    }

}

struct Setup<'a> {
    database: &'a mut Database
}

impl <'a> Setup<'a> {

    pub fn new(database: &'a mut Database) -> Self {
        Setup { database }
    }

    pub fn setup_on_first_run(&mut self) {
        if !Path::new(DB_FILE).exists() {
            self.initialize()
        }
    }

    fn initialize(&mut self) {
        util::print(&text_resources::setup_pre_database());
        self.database.connect();
        self.database.create_tables();
        util::print(&text_resources::setup_post_database());
        self.setup();
        util::println(&text_resources::setup_complete());
    }

    fn setup(&self) {
        let income_description = &util::read_config_input(&text_resources::setup_description(), "pocket money");
        let income_amount = &util::read_config_input(&text_resources::setup_income(), "100");
        let overdraft = &util::read_config_input(&text_resources::setup_overdraft(), "200");
        self.database.insert_configuration(CONF_INCOME_DESCRIPTION, income_description);
        self.database.insert_configuration(CONF_INCOME_AMOUNT, income_amount);
        self.database.insert_configuration(CONF_OVERDRAFT, overdraft);
        self.database.insert_auto_income(chrono::Local::today().month(), chrono::Local::today().year());
    }

}

struct Loop<'a> {
    database: &'a mut Database
}

impl <'a> Loop<'a> {

    const KEY_ADD: char = '+';
    const KEY_SUB: char = '-';
    const KEY_SHOW: char = '=';
    const KEY_HELP: char = '?';
    const KEY_QUIT: char = ':';

    pub fn new(database: &'a mut Database) -> Self {
        Loop { database }
    }

    pub fn looop(&mut self) {
        self.database.connect();
        self.database.insert_all_due_incomes();
        util::println(&text_resources::current_balance(self.database.balance()));
        self.handle_info();
        let mut looping = true;
        while looping {
            let input = util::input(&text_resources::enter_input());
            if input.len() == 1 {
                match util::first_char(&input) {
                    Loop::KEY_ADD => self.handle_add(),
                    Loop::KEY_SUB => self.handle_sub(),
                    Loop::KEY_HELP => self.handle_help(),
                    Loop::KEY_SHOW => self.handle_show(),
                    Loop::KEY_QUIT => looping = false,
                    _ => self.handle_info()
                }
            } else if input.len() > 1 && (util::first_char(&input) == Loop::KEY_ADD || util::first_char(&input) == Loop::KEY_SUB) {
                self.omg();
            } else {
                self.handle_info();
            }
        }
        self.database.disconnect();
        util::println(&text_resources::bye());
    }

    fn handle_add(&self) {
        self.add_to_ledger(1, &text_resources::income_booked());
    }

    fn handle_sub(&self) {
        self.add_to_ledger(-1, &text_resources::expense_booked());
    }

    fn add_to_ledger(&self, signum: i8, success_message: &str) {
        let description = util::input(&text_resources::enter_description());
        let amount = util::input(&text_resources::enter_amount()).parse::<f64>();
        let amount = match amount {
            Ok(amount) => amount,
            Err(_error) => 0.00
        };
        if amount > 0.0 {
            if signum == 1 || self.database.is_expense_acceptable(amount) {
                self.database.insert_into_ledger(&description, amount * signum as f64);
                util::println(success_message);
                util::println(&text_resources::current_balance(self.database.balance()));
            } else {
                util::println(&text_resources::error_too_expensive());
            }
        } else if amount < 0.0 {
            util::println(&text_resources::error_negative_amount());
        } else {
            util::println(&text_resources::error_zero_or_invalid_amount());
        }
    }

    fn omg(&self) {
        util::println(&text_resources::error_omg());
    }

    fn handle_info(&self) {
        util::print(&text_resources::info());
    }

    fn handle_help(&self) {
        util::print(&text_resources::help());
    }

    fn handle_show(&self) {
        util::print(&text_resources::formatted_balance(self.database.balance(), &self.database.transactions()));
    }

}

pub mod text_resources {

    pub fn banner() -> String {
        return r#"
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>Rust 1.61 Edition


"#.to_string();
    }

    pub fn info() -> String {
        return r#"
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

"#.to_string();
    }

    pub fn help() -> String {
        return r#"
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

"#.to_string();
    }

    pub fn setup_pre_database() -> String {
        return r#"
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
"#.to_string();
    }

    pub fn setup_post_database() -> String {
        return r#"
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

"#.to_string();
    }

    pub fn error_zero_or_invalid_amount() -> String {
        return "amount is zero or invalid -> action aborted".to_string();
    }

    pub fn error_negative_amount() -> String {
        return "amount must be positive -> action aborted".to_string();
    }

    pub fn income_booked() -> String {
        return "income booked".to_string();
    }

    pub fn expense_booked() -> String {
        return "expense booked successfully".to_string();
    }

    pub fn error_too_expensive() -> String {
        return "sorry, too expensive -> action aborted".to_string();
    }

    pub fn error_omg() -> String {
        return "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that".to_string();
    }

    pub fn enter_input() -> String {
        return "input > ".to_string();
    }

    pub fn enter_description() -> String {
        return "description (optional) > ".to_string();
    }

    pub fn enter_amount() -> String {
        return "amount > ".to_string();
    }

    pub fn setup_complete() -> String {
        return "setup complete, have fun".to_string();
    }

    pub fn bye() -> String {
        return "see ya".to_string();
    }

    pub fn current_balance(balance: f32) -> String {
        return format!(r#"
<TAB>current balance: {:.2}
"#, balance).to_string();
    }

    pub fn formatted_balance(balance: f32, formatted_last_transactions: &str) -> String {
        return format!(r#"{}
<TAB>last transactions (up to 30)
<TAB>----------------------------
{}
"#, current_balance(balance), formatted_last_transactions).to_string();
    }

    pub fn setup_description() -> String {
        return "enter description for regular income".to_string();
    }

    pub fn setup_income() -> String {
        return "enter regular income".to_string();
    }

    pub fn setup_overdraft() -> String {
        return "enter overdraft".to_string();
    }

    pub fn setup_template(description: &str, standard: &str) -> String {
        return format!("{} [default: {}] > ", description, standard).to_string();
    }

}

fn main() {
    util::print(&text_resources::banner());
    let mut database= Database::new();
    let mut setup = Setup::new(&mut database);
    setup.setup_on_first_run();
    let mut looop = Loop::new(&mut database);
    looop.looop();
}
