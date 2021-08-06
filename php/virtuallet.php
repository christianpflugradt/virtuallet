<?php

const DB_FILE = '../db_virtuallet.db';
const CONF_INCOME_DESCRIPTION = 'income_description';
const CONF_INCOME_AMOUNT = 'income_amount';
const CONF_OVERDRAFT = 'overdraft';
const TAB = '<TAB>';

class Util {

    static function prnt(String $text): void {
        echo str_replace(TAB, "\t", $text);
    }

    static function prntLn(String $text): void {
        self::prnt("$text\n");
    }

    static function input(String $prefix): String {
        self::prnt($prefix . ' > ');
        return trim(fgets(STDIN));
    }

    static function read_config_input(String $prefix, String $default): String {
        $result = self::input(TextResources::setup_template($prefix, $default));
        return empty(trim($result)) ? $default : $result;
    }
    
}

class Database {

    private ?SQLite3 $db = null;

    function connect(): void {
        if (is_null($this->db)) {
            $this->db = new SQLite3(DB_FILE);
        }
    }

    function disconnect(): void {
        $this->db->close();
    }

    function create_tables(): void {
        $this->db->exec(<<<SQL
            CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL,
                auto_income INTEGER NOT NULL,
                created_by TEXT,
                created_at TIMESTAMP NOT NULL,
                modified_at TIMESTAMP
            )
SQL
        );
        $this->db->exec('CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)');
    }

    function insert_configuration(String $key, int|String $value): void {
        $this->db->exec("INSERT INTO configuration (k, v) VALUES ('$key', '$value')");
    }

    function insert_into_ledger(String $description, float $amount): void {
        $this->db->exec(<<<SQL
            INSERT INTO LEDGER (description, amount, auto_income, created_at, created_by)
            VALUES ('$description', ROUND($amount, 2), 0, datetime('now'), 'PHP 8.0 Edition')
SQL
        );
    }

    function balance(): float {
        return $this->db->query('SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger')->fetchArray()[0];
    }

    function transactions(): String {
        $formatted = '';
        $result = $this->db->query('SELECT created_at, CAST(amount AS TEXT), description FROM ledger ORDER BY ROWID DESC LIMIT 30');
        while ($row = $result->fetchArray()) {
            $formatted .= "\t" . implode("\t", [$row[0], $row[1], $row[2]]) . "\n";
        }
        return $formatted;
    }

    private function income_description(): String {
        return $this->db->query('SELECT v FROM configuration WHERE k = \'' . CONF_INCOME_DESCRIPTION . '\'')->fetchArray()[0];
    }

    private function income_amount(): float {
        return $this->db->query('SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = \'' . CONF_INCOME_AMOUNT . '\'')->fetchArray()[0];
    }

    private function overdraft(): float {
        return $this->db->query('SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = \'' . CONF_OVERDRAFT . '\'')->fetchArray()[0];
    }

    function is_expense_acceptable(float $expense): bool {
        return $expense <= $this->balance() + $this->overdraft();
    }

    function insert_all_due_incomes(): void {
        $dueDates = [];
        $dueDate = [date('m'), date('Y')];
        while (!$this->has_auto_income_for_month($dueDate[0], $dueDate[1])) {
            array_push($dueDates, $dueDate);
            $dueDate = $dueDate[0] > 1 ? [$dueDate[0] - 1, $dueDate[1]] : [12, $dueDate[1] - 1];
        }
        foreach (array_reverse($dueDates) as $dueDate) {
            $this->insert_auto_income($dueDate[0], $dueDate[1]);
        }
    }

    function insert_auto_income(int $month, int $year): void {
        $description = $this->income_description() . ' ' . sprintf('%02d', $month) . "/$year";
        $amount = $this->income_amount();
        $this->db->exec(<<<SQL
            INSERT INTO LEDGER (description, amount, auto_income, created_at, created_by) 
            VALUES ('$description', ROUND($amount, 2), 1, datetime('now'), 'PHP 8.0 Edition')
SQL
        );
    }

    function has_auto_income_for_month(int $month, int $year): bool {
        $description = $this->income_description() . ' ' . sprintf('%02d', $month) . "/$year";
        return $this->db->query(
            "SELECT COALESCE(EXISTS(SELECT auto_income FROM ledger WHERE auto_income = 1 AND description LIKE '$description'), 0)"
            )->fetchArray()['0'] > 0;
    }

}

class Setup {

    private Database $database;

    function __construct(Database $database) {
        $this->database = $database;
    }

    function setup_on_first_run(): void {
        if (!file_exists(DB_FILE)) {
            $this->setup();
        }
    }

    private function configure(): void {
        $incomeDescription = Util::read_config_input(TextResources::setup_description(), 'pocket money');
        $incomeAmount = Util::read_config_input(TextResources::setup_income(), 100);
        $overdraft = Util::read_config_input(TextResources::setup_overdraft(), 200);
        $this->database->insert_configuration(CONF_INCOME_DESCRIPTION, $incomeDescription);
        $this->database->insert_configuration(CONF_INCOME_AMOUNT, $incomeAmount);
        $this->database->insert_configuration(CONF_OVERDRAFT, $overdraft);
        $this->database->insert_auto_income(date('m'), date('Y'));
    }

    private function setup(): void {
        Util::prntLn(TextResources::setup_pre_database());
        $this->database->connect();
        $this->database->create_tables();
        Util::prntLn(TextResources::setup_post_database());
        $this->configure();
        Util::prntLn(TextResources::setup_complete());
    }

}

class Loop {

    private const KEY_ADD = '+';
    private const KEY_SUB = '-';
    private const KEY_SHOW = '=';
    private const KEY_HELP = '?';
    private const KEY_QUIT = ':';

    private Database $database;

    function __construct(Database $database) {
        $this->database = $database;
    }

    function loop(): void {
        $this->database->connect();
        $this->database->insert_all_due_incomes();
        Util::prntLn(TextResources::current_balance($this->database->balance()));
        $this->handle_info();
        $looping = true;
        while ($looping) {
            $input = Util::input(TextResources::enter_input());
            switch ($input) {
                case self::KEY_ADD:
                    $this->handle_add();
                    break;
                case self::KEY_SUB:
                    $this->handle_sub();
                    break;
                case self::KEY_SHOW:
                    $this->handle_show();
                    break;
                case self::KEY_HELP:
                    $this->handle_help();
                    break;
                case self::KEY_QUIT:
                    $looping = false;
                    break;
                default:
                    if (!empty(trim($input)) && in_array(substr($input, 0, 1), [self::KEY_ADD, self::KEY_SUB])) {
                        self::omg();
                    } else {
                        $this->handle_info();
                    }
            }
        }
        $this->database->disconnect();
        Util::prntLn(TextResources::bye());
    }

    private static function omg(): void {
        Util::prntLn(TextResources::error_omg());
    }

    private function handle_add(): void {
        $this->add_to_ledger(1, TextResources::income_booked());
    }

    private function handle_sub(): void {
        $this->add_to_ledger(-1, TextResources::expense_booked());
    }

    private function add_to_ledger(int $signum, String $successMessage): void {
        $description = Util::input(TextResources::enter_description());
        $amount = floatval(Util::input(TextResources::enter_amount()));
        if ($amount > 0) {
            if ($signum == 1 || $this->database->is_expense_acceptable($amount)) {
                $this->database->insert_into_ledger($description, $amount * $signum);
                Util::prntLn($successMessage);
                Util::prntLn(TextResources::current_balance($this->database->balance()));
            } else {
                Util::prntLn(TextResources::error_too_expensive());
            }
        } else if ($amount < 0) {
            Util::prntLn(TextResources::error_negative_amount());
        } else {
            Util::prntLn(TextResources::error_zero_or_invalid_amount());
        }
    }

    private function handle_show(): void {
        Util::prntLn(TextResources::formatted_balance($this->database->balance(), $this->database->transactions()));
    }

    private function handle_info(): void {
        Util::prntLn(TextResources::info());
    }

    private function handle_help(): void {
        Util::prntLn(TextResources::help());
    }

}

class TextResources {

    static function banner(): String {
        return <<<TEXT

<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>PHP 8.0 Edition


TEXT;
    }

    static function info(): String {
        return <<<TEXT

<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

TEXT;
    }

    static function help(): String {
        return <<<TEXT

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

TEXT;
    }

    static function setup_pre_database(): String {
        return <<<TEXT

<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.

TEXT;
    }

    static function setup_post_database(): String {
        return <<<TEXT
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

TEXT;
    }

    static function error_zero_or_invalid_amount(): String {
        return 'amount is zero or invalid -> action aborted';
    }

    static function error_negative_amount(): String {
        return 'amount must be positive -> action aborted';
    }

    static function income_booked(): String {
        return 'income booked';
    }

    static function expense_booked(): String {
        return 'expense booked successfully';
    }

    static function error_too_expensive(): String {
        return 'sorry, too expensive -> action aborted';
    }

    static function error_omg(): String {
        return 'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that';
    }

    static function enter_input(): String {
        return 'input';
    }

    static function enter_description(): String {
        return 'description (optional)';
    }

    static function enter_amount(): String {
        return 'amount';
    }

    static function setup_complete(): String {
        return 'setup complete, have fun';
    } 

    static function bye(): String {
        return 'see ya';
    }

    static function current_balance(float $balance): String {
        return "\n\tcurrent balance: " . sprintf('%0.2f', $balance) . "\n ";
    }

    static function formatted_balance(float $balance, String $formatted_last_transactions): String {
        $current = self::current_balance($balance);
        return <<<TEXT
$current
<TAB>last transactions (up to 30)
<TAB>----------------------------
$formatted_last_transactions
TEXT;
    }

    static function setup_description(): String {
        return 'enter description for regular income';
    }

    static function setup_income(): String {
        return 'enter regular income';
    }

    static function setup_overdraft(): String {
        return 'enter overdraft';
    }

    static function setup_template(String $description, String $standard): String {
        return "$description [default: $standard]";
    }
    
}

Util::prntLn(TextResources::banner());
$database = new Database();
$setup = new Setup($database);
$loop = new Loop($database);
$setup->setup_on_first_run();
$loop->loop();
