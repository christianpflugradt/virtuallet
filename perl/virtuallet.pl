use DBI;
use Time::Piece;
use feature 'say';
use warnings FATAL => 'all';
use strict;

our $DB_FILE = '../db_virtuallet.db';
our $CONF_INCOME_DESCRIPTION = 'income_description';
our $CONF_INCOME_AMOUNT = 'income_amount';
our $CONF_OVERDRAFT = 'overdraft';
our $TAB = '<TAB>';

package util;

sub untab {
    my $content = shift;
    $content =~ s/$TAB/\t/ig;
    $content;
}

sub input {
    print shift;
    my $input = <STDIN>;
    chomp($input);
    $input
}

sub read_config_input {
    my ($description, $default) = @_;
    my $input = input(text_resources::setup_template($description, $default));
    length($input) ? $input : $default;
}

package database;

sub new {
    my $class = shift;
    my $self = { db_handle => undef };
    bless($self, $class);
    $self;
}

sub connect {
    my $self = shift;
    if (!defined $self->{db_handle}) {
        my $datasource_name = "DBI:SQLite:dbname=$DB_FILE";
        $self->{db_handle} = DBI->connect($datasource_name, '', '', undef);
    }
}

sub disconnect {
    my $self = shift;
    $self->{db_handle}->disconnect();
}

sub create_tables {
    my $self = shift;
    $self->{db_handle}->do(q(
        CREATE TABLE ledger (
                description TEXT,
                amount REAL NOT NULL,
                auto_income INTEGER NOT NULL,
                created_by TEXT,
                created_at TIMESTAMP NOT NULL,
                modified_at TIMESTAMP)
    ));
    $self->{db_handle}->do('CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)');
}

sub insert_configuration {
    my ($self, $key, $value) = @_;
    $self->{db_handle}->do("INSERT INTO configuration (k, v) VALUES ('$key', '$value')");
}

sub insert_into_ledger {
    my ($self, $description, $amount) = @_;
    $self->{db_handle}->do(qq(
        INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
        VALUES ('$description', ROUND($amount, 2), 0, datetime('now'), 'Perl Edition')
));
}

sub balance {
    my $self = shift;
    my ($result) = $self->{db_handle}->selectrow_array('SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger');
    $result;
}

sub transactions {
    my $self = shift;
    my $result = $self->{db_handle}->prepare('SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30');
    $result->execute();
    my $result_str = '';
    while (my @row = $result->fetchrow_array()) {
        $result_str = $result_str . "\t$row[0]\t$row[1]\t$row[2]\n";
    }
    substr($result_str, 0, -1);
}

sub income_description {
    my $self = shift;
    my ($result) = $self->{db_handle}->selectrow_array("SELECT v FROM configuration WHERE k = '$CONF_INCOME_DESCRIPTION'");
    $result;
}

sub income_amount {
    my $self = shift;
    my ($result) = $self->{db_handle}->selectrow_array("SELECT v FROM configuration WHERE k = '$CONF_INCOME_AMOUNT'");
    $result;
}

sub overdraft {
    my $self = shift;
    my ($result) = $self->{db_handle}->selectrow_array("SELECT v FROM configuration WHERE k = '$CONF_OVERDRAFT'");
    $result;
}

sub is_expense_acceptable {
    my ($self, $expense) = @_;
    ($self->balance() + $self->overdraft() - $expense) >= 0;
}

sub insert_all_due_incomes {
    my $self = shift;
    my @due_dates = ();
    my $now = Time::Piece->new();
    my @due_date = ($now->mon(), $now->year());
    while(!$self->has_auto_income_for_month($due_date[0], $due_date[1])) {
        @due_dates = (@due_dates, @due_date);
        @due_date = $due_date[0] > 1
            ? ($due_date[0] - 1, $due_date[1])
            : (12, $due_date[1] - 1);
    }
    @due_dates = reverse(@due_dates);
    my $due_dates = @due_dates;
    if($due_dates > 0) {
        for (0 .. $due_dates - 1) {
            if ($_ % 2 == 0) {
                $self->insert_auto_income($due_dates[$_ + 1], $due_dates[$_]);
            }
        }
    }
}

sub insert_auto_income {
    my $self = shift;
    my $month = sprintf("%02d", shift);
    my $year = shift;
    my $description = $self->income_description() . " $month/$year";
    my $amount = $self->income_amount();
    $self->{db_handle}->do(qq(
        INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
        VALUES ('$description', ROUND($amount, 2), 1, datetime('now'), 'Perl Edition')
));
}

sub has_auto_income_for_month {
    my $self = shift;
    my $month = sprintf("%02d", shift);
    my $year = shift;
    my ($result) = $self->{db_handle}->selectrow_array(qq(
        SELECT EXISTS(
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE '% $month/$year')
    ));
    $result;
}

package setup;

sub new {
    my $class = shift;
    my $self = { db => shift };
    bless($self, $class);
    $self;
}

sub setup_on_first_run {
    my $self = shift;
    if (!-e $DB_FILE) {
        $self->initialize();
    }
}

sub initialize {
    my $self = shift;
    say text_resources::setup_pre_database();
    $self->{db}->connect();
    $self->{db}->create_tables();
    say text_resources::setup_post_database();
    $self->setup();
    say text_resources::setup_complete();
}

sub setup {
    my $self = shift;
    my $income_description = util::read_config_input(text_resources::setup_description(), 'pocket money');
    my $income_amount = util::read_config_input(text_resources::setup_income(), 100);
    my $overdraft = util::read_config_input(text_resources::setup_overdraft(), 200);
    $self->{db}->insert_configuration($CONF_INCOME_DESCRIPTION, $income_description);
    $self->{db}->insert_configuration($CONF_INCOME_AMOUNT, $income_amount);
    $self->{db}->insert_configuration($CONF_OVERDRAFT, $overdraft);
    my $now = Time::Piece->new();
    $self->{db}->insert_auto_income($now->mon(), $now->year());
}

package loop;

sub new {
    my $class = shift;
    my $self = {
        db      => shift,
        KEY_ADD => '+',
        KEY_SUB => '-',
        KEY_SHOW => '=',
        KEY_HELP => '?',
        KEY_QUIT => ':',
    };
    bless($self, $class);
    $self;
}

sub loop {
    my $self = shift;
    $self->{db}->connect();
    $self->{db}->insert_all_due_incomes();
    say text_resources::current_balance($self->{db}->balance());
    $self->handle_info();
    my $looping = 1;
    while($looping > 0) {
        my $inp = util::input(text_resources::enter_input());
        if ($inp eq $self->{KEY_ADD}) {
            $self->handle_add();
        } elsif ($inp eq $self->{KEY_SUB}) {
            $self->handle_sub();
        } elsif ($inp eq $self->{KEY_SHOW}) {
            $self->handle_show();
        } elsif ($inp eq $self->{KEY_HELP}) {
            $self->handle_help();
        } elsif ($inp eq $self->{KEY_QUIT}) {
            $looping = 0;
        } elsif (length($inp) && (substr($inp, 0, 1) eq $self->{KEY_ADD} || substr($inp, 0, 1) eq $self->{KEY_SUB})) {
            $self->omg();
        } else {
            $self->handle_info();
        }
    }
    $self->{db}->disconnect();
    say text_resources::bye();
}

sub omg {
    say text_resources::error_omg();
}

sub handle_add {
    my $self = shift;
    $self->add_to_ledger(1, text_resources::income_booked());
}

sub handle_sub {
    my $self = shift;
    $self->add_to_ledger(-1, text_resources::expense_booked());
}

sub add_to_ledger {
    my ($self, $signum, $success_message) = @_;
    my $description = util::input(text_resources::enter_description());
    my $amount = util::input(text_resources::enter_amount());
    if (Scalar::Util::looks_like_number($amount) && $amount > 0) {
       if ($signum == 1 || $self->{db}->is_expense_acceptable($amount)) {
           $self->{db}->insert_into_ledger($description, $amount * $signum);
           say $success_message;
           say text_resources::current_balance($self->{db}->balance());
       } else {
           say text_resources::error_too_expensive();
       }
    } elsif (Scalar::Util::looks_like_number($amount) && $amount < 0) {
        say text_resources::error_negative_amount();
    } else {
        say text_resources::error_zero_or_invalid_amount();
    }
}

sub handle_show {
    my $self = shift;
    say text_resources::formatted_balance($self->{db}->balance(), $self->{db}->transactions());
}

sub handle_info {
    say text_resources::info();
}

sub handle_help {
    say text_resources::help();
}

package text_resources;

sub banner {
    util::untab(<<EOF

<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/

<TAB>Perl v5.32 Edition


EOF
    );
}

sub info {
    util::untab(<<EOF

<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit
EOF
    );
}

sub help {
    util::untab(<<EOF

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
<TAB>So if you have specified a monthly income and haven\'t run Virtuallet for three months
<TAB>it will auto-create three regular incomes when you boot it the next time if you like it or not.

<TAB>Virtuallet will also allow you to add irregular incomes and expenses manually.
<TAB>It can also display the current balance and the 30 most recent transactions.

<TAB>The configured overdraft will be considered if an expense is registered.
<TAB>For instance if your overdraft equals the default value of 200
<TAB>you won\'t be able to add an expense if the balance would be less than -200 afterwards.

<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser
<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.

<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.
EOF
    );
}

sub setup_pre_database {
    util::untab(<<EOF
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
EOF
    );
}

sub setup_post_database {
    util::untab(<<EOF
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don\'t care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.
EOF
    );
}

sub error_zero_or_invalid_amount {
    'amount is zero or invalid -> action aborted';
}

sub error_negative_amount {
    'amount must be positive -> action aborted';
}

sub income_booked {
    'income booked';
}

sub expense_booked {
    'expense booked successfully';
}

sub error_too_expensive {
    'sorry, too expensive -> action aborted';
}

sub error_omg {
    'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that';
}

sub enter_input {
    'input > ';
}

sub enter_description {
    'description (optional) > ';
}

sub enter_amount {
    'amount > ';
}

sub setup_complete {
    'setup complete, have fun';
}

sub bye {
    'see ya';
}

sub current_balance {
    my $balance = sprintf('%.2f', shift);
    util::untab(<<EOF

<TAB>current balance: $balance
EOF
    );
}

sub formatted_balance {
    my $balance = sprintf('%.2f', shift);
    my $transactions = shift;
    util::untab(<<EOF

<TAB>current balance: $balance

<TAB>last transactions (up to 30)
<TAB>----------------------------
$transactions
EOF
    );
}

sub setup_description {
    'enter description for regular income';
}

sub setup_income {
    'enter regular income';
}

sub setup_overdraft {
    'enter overdraft';
}

sub setup_template {
    my $description = shift;
    my $default = shift;
    "$description [default: $default] > ";
}

package main;

my $db = database->new();
my $setup = setup->new($db);
my $loop = loop->new($db);

say text_resources::banner();
$setup->setup_on_first_run();
$loop->loop();
