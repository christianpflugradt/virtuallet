module pkg_util

    use pkg_text_resources
    implicit none
    character(len=*), parameter :: &
        DB_FILE = '../db_virtuallet.db', &
        CONF_INCOME_DESCRIPTION = 'income_description', &
        CONF_INCOME_AMOUNT = 'income_amount', &
        CONF_OVERDRAFT = 'overdraft'

    type due_date
        integer :: month, year
    end type

contains

    subroutine prnt(msg)
        character(len=*), intent(in) :: msg
        write(*, '(a)', advance='no') msg
    end subroutine

    subroutine prntln(msg)
        character(len=*), intent(in) :: msg
        write(*, '(a)') msg
    end subroutine

    function input(msg) result(res)
        character(len=*), intent(in) :: msg
        character(len=999999) :: inp
        character(len=:), allocatable :: res
        call prnt(msg)
        read(*, '(A)') inp
        res = trim(inp)
    end function input

    function read_config_input(description, standard) result(res)
        character(len=*), intent(in) :: description, standard
        character(len=:), allocatable :: inp, res
        inp = input(setup_template(description, standard))
        if (len(inp) == 0) then
            res = standard
        else
            res = inp
        end if
    end function read_config_input

    function real_to_str(num) result(res)
        real(kind=8), intent(in) :: num
        character(len=99) :: str
        character(len=:), allocatable :: res
        write(str, '(f90.2)') num
        res = trim(adjustl(str))
    end function real_to_str

    character(len=8) function current_date() result(res)
        call date_and_time(date=res)
    end function current_date

    character(len=2) function current_month() result(res)
        character(len=8) :: date
        date = current_date()
        res = date(5:6)
    end function current_month

    character(len=4) function current_year() result(res)
        character(len=8) :: date
        date = current_date()
        res = date(1:4)
    end function current_year

end module pkg_util

module pkg_database

    use, intrinsic :: iso_c_binding, only: c_ptr, c_null_ptr
    use :: sqlite
    use :: pkg_text_resources
    use :: pkg_util
    implicit none

    type, public :: Database
        type(c_ptr) :: db = c_null_ptr
    contains
        procedure :: connect
        procedure :: disconnect
        procedure :: create_tables
        procedure :: insert_configuration
        procedure :: insert_into_ledger
        procedure :: balance
        procedure :: transactions
        procedure :: format_current_row
        procedure :: income_description
        procedure :: income_amount
        procedure :: overdraft
        procedure :: is_expense_acceptable
        procedure :: insert_all_due_incomes
        procedure :: insert_auto_income
        procedure :: has_auto_income_for_month
    end type Database

contains

    subroutine connect(this)
        class(Database), intent(inout) :: this
        integer :: rc
        rc = sqlite3_open(DB_FILE, this%db)
    end subroutine connect

    subroutine disconnect(this)
        class(Database), intent(inout) :: this
        integer :: rc
        rc = sqlite3_close(this%db)
    end subroutine disconnect

    subroutine create_tables(this)
        class(Database), intent(inout) :: this
        character(len=:), allocatable :: err
        integer :: rc
        rc = sqlite3_exec(this%db, &
            'CREATE TABLE ledger ( &
                &description TEXT, &
                &amount REAL NOT NULL, &
                &auto_income INTEGER NOT NULL, &
                &created_by TEXT, &
                &created_at TIMESTAMP NOT NULL, &
                &modified_at TIMESTAMP)', c_null_ptr, c_null_ptr, err)
        rc = sqlite3_exec(this%db, 'CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)', &
            c_null_ptr, c_null_ptr, err)
    end subroutine create_tables

    subroutine insert_configuration(this, key, value)
        class(Database), intent(inout) :: this
        character(len=*), intent(in) :: key, value
        type(c_ptr) :: stmt
        integer :: rc
        rc = sqlite3_prepare_v2(this%db, &
            'INSERT INTO configuration (k, v) VALUES (?, ?)', stmt)
        rc = sqlite3_bind_text(stmt, 1, key)
        rc = sqlite3_bind_text(stmt, 2, value)
        rc = sqlite3_step(stmt)
        rc = sqlite3_finalize(stmt)
    end subroutine insert_configuration

    subroutine insert_into_ledger(this, description, amount)
        class(Database), intent(inout) :: this
        character(len=*), intent(in) :: description
        real(kind=8), intent(in) :: amount
        type(c_ptr) :: stmt
        integer :: rc
        rc = sqlite3_prepare_v2(this%db, &
                "INSERT INTO ledger (description, amount, auto_income, created_at, created_by) &
                    &VALUES (?, ?, 0, datetime('now'), 'Fortran 2018 Edition')", stmt)
        rc = sqlite3_bind_text(stmt, 1, description)
        rc = sqlite3_bind_double(stmt, 2, amount)
        rc = sqlite3_step(stmt)
        rc = sqlite3_finalize(stmt)
    end subroutine insert_into_ledger

    real(kind=8) function balance(this) result(res)
        class(Database), intent(inout) :: this
        type(c_ptr) :: stmt
        integer :: rc
        rc = sqlite3_prepare(this%db, 'SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger', stmt)
        rc = sqlite3_step(stmt)
        res = sqlite3_column_double(stmt, 0)
        rc = sqlite3_finalize(stmt)
    end function balance

    function transactions(this) result(res)
        class(Database), intent(inout) :: this
        character(len=:), allocatable :: row, res
        type(c_ptr) :: stmt
        integer :: rc
        rc = sqlite3_prepare(this%db, 'SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30', stmt)
        do while (sqlite3_step(stmt) /= SQLITE_DONE)
            row = this%format_current_row(stmt)
            res = res // TAB // row // LF
        end do
        rc = sqlite3_finalize(stmt)
    end function transactions

    function format_current_row(this, stmt) result(res)
        class(Database), intent(inout) :: this
        character(len=:), allocatable :: created_at, description, res
        real(kind=8), allocatable :: amount
        type(c_ptr) :: stmt
        integer :: rc
        created_at = sqlite3_column_text(stmt, 0)
        amount = sqlite3_column_double(stmt, 1)
        description = sqlite3_column_text(stmt, 2)
        res = created_at // TAB // real_to_str(amount) // TAB // description
    end function format_current_row

    function income_description(this) result(res)
        class(Database), intent(inout) :: this
        character(len=:), allocatable :: res
        type(c_ptr) :: stmt
        integer :: rc
        rc = sqlite3_prepare(this%db, 'SELECT v FROM configuration WHERE k = ?', stmt)
        rc = sqlite3_bind_text(stmt, 1, CONF_INCOME_DESCRIPTION)
        rc = sqlite3_step(stmt)
        res = sqlite3_column_text(stmt, 0)
        rc = sqlite3_finalize(stmt)
    end function income_description

    real(kind=8) function income_amount(this) result(res)
        class(Database), intent(inout) :: this
        type(c_ptr) :: stmt
        integer :: rc
        rc = sqlite3_prepare(this%db, 'SELECT v FROM configuration WHERE k = ?', stmt)
        rc = sqlite3_bind_text(stmt, 1, CONF_INCOME_AMOUNT)
        rc = sqlite3_step(stmt)
        res = sqlite3_column_double(stmt, 0)
        rc = sqlite3_finalize(stmt)
    end function income_amount

    real(kind=8) function overdraft(this) result(res)
        class(Database), intent(inout) :: this
        type(c_ptr) :: stmt
        integer :: rc
        rc = sqlite3_prepare(this%db, 'SELECT v FROM configuration WHERE k = ?', stmt)
        rc = sqlite3_bind_text(stmt, 1, CONF_OVERDRAFT)
        rc = sqlite3_step(stmt)
        res = sqlite3_column_double(stmt, 0)
        rc = sqlite3_finalize(stmt)
    end function overdraft

    logical function is_expense_acceptable (this, expense) result(res)
        class(Database), intent(inout) :: this
        real(kind=8), intent(in) :: expense
        res = (this%balance() + this%overdraft() - expense) >= 0
    end function is_expense_acceptable

    subroutine insert_all_due_incomes(this)
        class(Database), intent(inout) :: this
        type(due_date), dimension(:), allocatable :: due_dates, buffer
        type(due_date) :: current_due_date
        integer :: start_month, start_year, current_size, insert_index, retrieve_index
        character(len=2) :: month_str
        character(len=4) :: year_str
        current_size = 100
        insert_index = 1
        allocate(due_dates(1:current_size))
        month_str = current_month()
        year_str = current_year()
        read(month_str, *) start_month
        read(year_str, *) start_year
        current_due_date = due_date(start_month, start_year)
        do while (.not. this%has_auto_income_for_month(current_due_date%month, current_due_date%year))
            if (insert_index == current_size) then
                current_size = current_size + current_size/2 + 1
                call move_alloc(due_dates, buffer)
                allocate(due_dates(1:current_size))
                due_dates(:size(buffer)) = buffer(:size(buffer))
            end if
            due_dates(insert_index) = current_due_date
            insert_index = insert_index + 1
            if (current_due_date%month == 1) then
                current_due_date = due_date(12, current_due_date%year - 1)
            else
                current_due_date = due_date(current_due_date%month - 1, current_due_date%year)
            end if
        end do
        do retrieve_index = insert_index - 1, 1, -1
            write(month_str, '(i2.2)') due_dates(retrieve_index)%month
            write(year_str, '(i4)') due_dates(retrieve_index)%year
            call this%insert_auto_income(month_str, year_str)
        end do
    end subroutine insert_all_due_incomes

    subroutine insert_auto_income(this, month, year)
        class(Database), intent(inout) :: this
        character(len=2), intent(in) :: month
        character(len=4), intent(in) :: year
        character(len=:), allocatable :: description
        real(kind=8) :: amount
        type(c_ptr) :: stmt
        integer :: rc
        description = this%income_description() // ' ' // month // '/' // year
        amount = this%income_amount()
        rc = sqlite3_prepare_v2(this%db, &
                "INSERT INTO ledger (description, amount, auto_income, created_at, created_by) &
                        &VALUES (?, ?, 1, datetime('now'), 'Fortran 2018 Edition')", stmt)
        rc = sqlite3_bind_text(stmt, 1, description)
        rc = sqlite3_bind_double(stmt, 2, amount)
        rc = sqlite3_step(stmt)
        rc = sqlite3_finalize(stmt)
    end subroutine insert_auto_income

    logical function has_auto_income_for_month(this, month, year) result(res)
        class(Database), intent(inout) :: this
        integer, intent(in) :: month, year
        character(len=9) :: date_info
        character(len=2) :: month_str
        character(len=4) :: year_str
        type(c_ptr) :: stmt
        integer :: rc
        write(month_str, '(i2.2)') month
        write(year_str, '(i4)') year
        date_info = '% ' // month_str // '/' // year_str
        rc = sqlite3_prepare(this%db, 'SELECT EXISTS( &
            &SELECT auto_income FROM ledger &
            &WHERE auto_income = 1 &
            &AND description LIKE ?)', stmt)
        rc = sqlite3_bind_text(stmt, 1, date_info)
        rc = sqlite3_step(stmt)
        res = sqlite3_column_double(stmt, 0) == 1
        rc = sqlite3_finalize(stmt)
    end function has_auto_income_for_month

end module pkg_database

module pkg_setup

    use pkg_database
    use pkg_text_resources
    use pkg_util
    implicit none

    type, public :: Setup
        type(Database) :: database_obj
    contains
        procedure :: setup_on_first_run
        procedure :: initialize
        procedure :: set_up
    end type Setup

contains

    subroutine setup_on_first_run(this)
        class(Setup), intent(inout) :: this
        logical :: exists
        inquire(file=DB_FILE, exist=exists)
        if (.not. exists) then
            call this%initialize()
        end if
    end subroutine setup_on_first_run

    subroutine initialize(this)
        class(Setup), intent(inout) :: this
        call prnt(setup_pre_database())
        call this%database_obj%connect()
        call this%database_obj%create_tables()
        call prnt(setup_post_database())
        call this%set_up()
        call this%database_obj%disconnect()
        call prntln(setup_complete())
    end subroutine initialize

    subroutine set_up(this)
        class(Setup), intent(inout) :: this
        character(len=:), allocatable :: income_description, income_amount, overdraft
        income_description = read_config_input(setup_description(), 'pocket money')
        income_amount = read_config_input(setup_description(), '100')
        overdraft = read_config_input(setup_description(), '200')
        call this%database_obj%insert_configuration(CONF_INCOME_DESCRIPTION, income_description)
        call this%database_obj%insert_configuration(CONF_INCOME_AMOUNT, income_amount)
        call this%database_obj%insert_configuration(CONF_OVERDRAFT, overdraft)
        call this%database_obj%insert_auto_income(current_month(), current_year())
    end subroutine set_up

end module pkg_setup

module pkg_loop

    use pkg_database
    use pkg_text_resources
    use pkg_util

    implicit none
    character(len=1), parameter :: &
        KEY_ADD = '+', &
        KEY_SUB = '-', &
        KEY_SHOW = '=', &
        KEY_HELP = '?', &
        KEY_QUIT = ':'

    type, public :: Loop
        type(Database) :: database_obj
    contains
        procedure :: do_loop
        procedure :: handle_add
        procedure :: handle_sub
        procedure :: add_to_ledger
        procedure :: omg
        procedure :: handle_info
        procedure :: handle_help
        procedure :: handle_show
    end type Loop

contains

    subroutine do_loop(this)
        class(Loop), intent(inout) :: this
        character(len=:), allocatable :: inp
        logical :: looping = .true.
        call this%database_obj%connect()
        call this%database_obj%insert_all_due_incomes()
        call prntln(current_balance(real_to_str(this%database_obj%balance())))
        call this%handle_info()
        do while (looping)
            inp = input(enter_input())
            select case (inp)
                case (KEY_ADD)
                    call this%handle_add()
                case (KEY_SUB)
                    call this%handle_sub()
                case (KEY_SHOW)
                    call this%handle_show()
                case (KEY_HELP)
                    call this%handle_help()
                case (KEY_QUIT)
                    looping = .false.
                case default
                    if (len(inp) > 1 .and. (inp(1:1) == KEY_ADD .or. inp(1:1) == KEY_SUB)) then
                        call this%omg()
                    else
                        call this%handle_info()
                    end if
            end select
        end do
        call this%database_obj%disconnect()
        call prntln(bye())
    end subroutine do_loop

    subroutine handle_add(this)
        class(Loop), intent(inout) :: this
        call this%add_to_ledger(1, income_booked())
    end subroutine handle_add

    subroutine handle_sub(this)
        class(Loop), intent(inout) :: this
        call this%add_to_ledger(-1, expense_booked())
    end subroutine handle_sub

    subroutine add_to_ledger(this, signum, success_message)
        class(Loop), intent(inout) :: this
        integer, intent(in) :: signum
        character(len=*), intent(in) :: success_message
        character(len=:), allocatable :: description, inp
        real(kind=8) :: amount
        integer :: err
        description = input(enter_description())
        inp = input(enter_amount())
        read(inp, *, iostat=err) amount
        if (err /= 0) then
            amount = 0
        end if
        if (amount > 0) then
            if (signum == 1 .or. this%database_obj%is_expense_acceptable(amount)) then
                call this%database_obj%insert_into_ledger(description, amount * signum)
                call prntln(success_message)
                call prntln(current_balance(real_to_str(this%database_obj%balance())))
            else
                call prntln(error_too_expensive())
            end if
        else if (amount < 0) then
            call prntln(error_negative_amount())
        else
            call prntln(error_zero_or_invalid_amount())
        end if
    end subroutine add_to_ledger

    subroutine omg(this)
        class(Loop), intent(inout) :: this
        call prntln(error_omg())
    end subroutine omg

    subroutine handle_info(this)
        class(Loop), intent(inout) :: this
        call prnt(info())
    end subroutine handle_info

    subroutine handle_help(this)
        class(Loop), intent(inout) :: this
        call prnt(help())
    end subroutine handle_help

    subroutine handle_show(this)
        class(Loop), intent(inout) :: this
        call prnt(formatted_balance(real_to_str(this%database_obj%balance()), this%database_obj%transactions()))
    end subroutine handle_show

end module pkg_loop

module pkg_text_resources

    implicit none
    character(len=1), parameter :: TAB = char(9)
    character(len=*), parameter :: LF = new_line('a')

contains

    function banner() result(res)
        character(len=:), allocatable :: res
        res = LF // &
            TAB // ' _                                 _   _' // LF // &
            TAB // '(_|   |_/o                        | | | |' // LF // &
            TAB // '  |   |      ,_  _|_         __,  | | | |  _ _|_' // LF // &
            TAB // '  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |' // LF // &
            TAB // '   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/' // LF // LF // &
            TAB // 'Fortran 2018 Edition' // LF // LF // LF
    end function banner

    function info() result(res)
        character(len=:), allocatable :: res
        res = LF // &
            TAB // 'Commands:' // LF // &
            TAB // '- press plus (+) to add an irregular income' // LF // &
            TAB // '- press minus (-) to add an expense' // LF // &
            TAB // '- press equals (=) to show balance and last transactions' // LF // &
            TAB // '- press question mark (?) for even more info about this program' // LF // &
            TAB // '- press colon (:) to exit' // LF // LF
    end function info

    function help() result(res)
        character(len=:), allocatable :: res
        res = LF // &
            TAB // 'Virtuallet is a tool to act as your virtual wallet. Wow...' // LF // &
            TAB // 'Virtuallet is accessible via terminal and uses a Sqlite database to store all its data.' // LF // &
            TAB // 'On first start Virtuallet will be configured and requires some input' // LF // &
            TAB // 'but you already know that unless you are currently studying the source code.' // LF // LF // &
            TAB // 'Virtuallet follows two important design principles:' // LF // LF // &
            TAB // '- shit in shit out' // LF // &
            TAB // '- UTFSB (Use The F**king Sqlite Browser)' // LF // LF // &
            TAB // 'As a consequence everything in the database is considered valid.' // LF // &
            TAB // 'Program behaviour is unspecified for any database content being invalid. Ouch...' // LF // LF // &
            TAB // 'As its primary feature Virtuallet will auto-add the configured income on start up' // LF // &
            TAB // 'for all days in the past since the last registered regular income.' // LF // &
            TAB // 'So if you have specified a monthly income and haven''t run Virtuallet for three months' // LF // &
            TAB // 'it will auto-create three regular incomes when you boot &
                &it the next time if you like it or not.' // LF // LF // &
            TAB // 'Virtuallet will also allow you to add irregular incomes and expenses manually.' // LF // &
            TAB // 'It can also display the current balance and the 30 most recent transactions.' // LF // LF // &
            TAB // 'The configured overdraft will be considered if an expense is registered.' // LF // &
            TAB // 'For instance if your overdraft equals the default value of 200' // LF // &
            TAB // 'you won''t be able to add an expense if the balance would be less than -200 afterwards.' // LF // LF // &
            TAB // 'Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser' // LF // &
            TAB // 'to view and even edit the database. When making updates please &
                &remember the shit in shit out principle.' // LF // LF // &
            TAB // 'As a free gift to you I have added a modified_at field in the ledger table. &
                &Feel free to make use of it.' // LF // LF
    end function help

    function setup_pre_database() result(res)
        character(len=:), allocatable :: res
        res = LF // &
            TAB // 'Database file not found.' // LF // &
            TAB // 'Database will be initialized. This may take a while... NOT.' // LF
    end function setup_pre_database

    function setup_post_database() result(res)
        character(len=:), allocatable :: res
        res = LF // &
            TAB // 'Database initialized.' // LF // &
            TAB // 'Are you prepared for some configuration? If not I don''t care. &
                &There is no way to exit, muhahahar.' // LF // &
            TAB // 'Press enter to accept the default or input something else. There is no validation' // LF // &
            TAB // 'because I know you will not make a mistake. No second chances. If you f**k up,' // LF // &
            TAB // 'you will have to either delete the database file or edit it using a sqlite database browser.' // LF // LF
    end function setup_post_database

    function error_zero_or_invalid_amount() result(res)
        character(len=:), allocatable :: res
        res = 'amount is zero or invalid -> action aborted'
    end function error_zero_or_invalid_amount

    function error_negative_amount() result(res)
        character(len=:), allocatable :: res
        res = 'amount must be positive -> action aborted'
    end function error_negative_amount

    function income_booked() result(res)
        character(len=:), allocatable :: res
        res = 'income booked'
    end function income_booked

    function expense_booked() result(res)
        character(len=:), allocatable :: res
        res = 'expense booked successfully'
    end function expense_booked

    function error_too_expensive() result(res)
        character(len=:), allocatable :: res
        res = 'sorry, too expensive -> action aborted'
    end function error_too_expensive

    function error_omg() result(res)
        character(len=:), allocatable :: res
        res = 'OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that'
    end function error_omg

    function enter_input() result(res)
        character(len=:), allocatable :: res
        res = 'input > '
    end function enter_input

    function enter_description() result(res)
        character(len=:), allocatable :: res
        res = 'description (optional) > '
    end function enter_description

    function enter_amount() result(res)
        character(len=:), allocatable :: res
        res = 'amount > '
    end function enter_amount

    function setup_complete() result(res)
        character(len=:), allocatable :: res
        res = 'setup complete, have fun'
    end function setup_complete

    function bye() result(res)
        character(len=:), allocatable :: res
        res = 'see ya'
    end function bye

    function current_balance(balance) result(res)
        character(len=*), intent(in) :: balance
        character(len=:), allocatable :: res
        res = LF // TAB // 'current balance: ' // balance // LF
    end function current_balance

    function formatted_balance(balance, formatted_last_transactions) result(res)
        character(len=*), intent(in) :: balance, formatted_last_transactions
        character(len=:), allocatable :: res
        res = current_balance(balance) // LF // &
            TAB // 'last transactions (up to 30)' // LF // &
            TAB // '----------------------------' // LF // &
            formatted_last_transactions // LF
    end function formatted_balance

    function setup_description() result(res)
        character(len=:), allocatable :: res
        res = 'enter description for regular income'
    end function setup_description

    function setup_income() result(res)
        character(len=:), allocatable :: res
        res = 'enter regular income'
    end function setup_income

    function setup_overdraft() result(res)
        character(len=:), allocatable :: res
        res = 'enter overdraft'
    end function setup_overdraft

    function setup_template(description, standard) result(res)
        character(len=*), intent(in) :: description, standard
        character(len=:), allocatable :: res
        res = description // ' [default: ' // standard // '] > '
    end function setup_template

end module pkg_text_resources

program virtuallet

    use pkg_database
    use pkg_loop
    use pkg_setup
    use pkg_text_resources
    use pkg_util
    implicit none
    type(Database) :: database_obj
    type(Setup) :: setup_obj
    type(Loop) :: loop_obj

    call prnt(banner())
    database_obj = Database()
    setup_obj = Setup(database_obj)
    loop_obj = Loop(database_obj)
    call setup_obj%setup_on_first_run()
    call loop_obj%do_loop()

end program virtuallet
