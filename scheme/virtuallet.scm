(import (chicken file))
(import (chicken io))
(import (chicken string))
(import (chicken time))
(import (chicken time posix))
(import format)
(import sql-de-lite)

(define CONF-INCOME-DESCRIPTION "income_description")
(define CONF-INCOME-AMOUNT "income_amount")
(define CONF-OVERDRAFT "overdraft")
(define DB-FILE "../db_virtuallet.db")
(define TAB "<TAB>")

;;;; util

(define (prnt str)
    (display (string-translate* str `((,TAB . "\u0009") ("\\n" . "\u000A")) )))

(define (prntln str)
    (prnt (format "~A~%" str)))

(define (input prefix)
    (prnt prefix)
    (prnt " > ")
    (read-line))

(define (read-config-input description default)
    (let ((inp (input (setup-template description default))))
        (if (= (string-length inp) 0) default inp)))

(define (current-month)
    (+ 1 (vector-ref (seconds->local-time (current-seconds)) 4)))

(define (current-year)
    (+ 1900 (vector-ref (seconds->local-time (current-seconds)) 5)))

(define (for-each-item lst fun)
    (if (> (length lst) 0)
        (begin
            (fun (car lst))
            (for-each-item (cdr lst) fun))))

;;;; database

(define (connect-db)
    (open-database DB-FILE))

(define (disconnect-db db)
    (close-database db))

(define (create-tables db)
    (exec (sql db "
        CREATE TABLE ledger (
            description TEXT,
            amount REAL NOT NULL,
            auto_income INTEGER NOT NULL,
            created_by TEXT,
            created_at TIMESTAMP NOT NULL,
            modified_at TIMESTAMP)
    "))
    (exec (sql db "CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)")))

(define (insert-configuration db key value)
    (exec (sql db (conc "INSERT INTO configuration (k, v) VALUES ('" key "', '" value "')"))))

(define (insert-into-ledger db description amount)
    (exec (sql db (conc "
        INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
        VALUES ('" description "', ROUND(" amount ", 2), 0, datetime('now'), 'CHICKEN Scheme 5.3 Edition')
    "))))

(define (balance db)
    (query fetch-value (sql db "SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger")))

(define (income-description db)
    (query fetch-value (sql db (conc "SELECT v FROM configuration WHERE k = '" CONF-INCOME-DESCRIPTION "'"))))

(define (income-amount db)
    (query fetch-value (sql db (conc "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = '" CONF-INCOME-AMOUNT "'"))))

(define (overdraft db)
    (query fetch-value (sql db (conc "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = '" CONF-OVERDRAFT "'"))))

(define (transactions db)
    (let (
        (formatted "")
        (lines (query fetch-all
            (sql db "SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30"))))
        (for-each-item lines
            (lambda (line)
                (set! formatted
                    (conc
                        formatted TAB
                        (list-ref line 0) TAB
                        (list-ref line 1) TAB
                        (list-ref line 2) "\u000A"))))
        formatted))

(define (is-expense-acceptable db expense)
    (> (- (+ (balance db) (overdraft db)) expense) 0))

(define (insert-auto-income db month year)
    (let ((description (format "~a ~a/~d"
            (income-description db)
            (format "~2,'0d" month)
            year))
        (amount (income-amount db)))
        (exec (sql db (conc "
            INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
            VALUES ('" description "', ROUND(" amount ", 2), 1, datetime('now'), 'CHICKEN Scheme 5.3 Edition')
        ")))))

(define (insert-all-due-incomes db)
    (let ((due-dates (collect-due-dates db (list (list (current-month) (current-year))))))
        (for-each-item due-dates
            (lambda (due-date)
                (if due-date (insert-auto-income db (list-ref due-date 0) (list-ref due-date 1)))))))

(define (collect-due-dates db due-dates)
    (let ((last-due-date (list-ref (reverse due-dates) 0)))
        (if (has-auto-income-for-month db (list-ref last-due-date 0) (list-ref last-due-date 1))
            (cdr (reverse due-dates))
            (let ((due-date
                    (if (> (list-ref last-due-date 0) 1)
                        (list (- (list-ref last-due-date 0) 1) (list-ref last-due-date 1))
                        (list 12 (- (list-ref last-due-date 1) 1)))))
                (collect-due-dates db (append due-dates (list due-date)))))))

(define (has-auto-income-for-month db month year)
    (let ((description (format "~a ~a/~d"
             (income-description db)
             (format "~2,'0d" month)
             year)))
        (= 1 (query fetch-value (sql db (conc "
            SELECT CAST(EXISTS(
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE '" description "') AS DECIMAL)
        "))))))

;;;; setup

(define (setup-on-first-run)
    (if (not (file-exists? DB-FILE))
        (initialize (connect-db))))

(define (initialize db)
    (prnt (setup-pre-database))
    (create-tables db)
    (prnt (setup-post-database))
    (setup db)
    (disconnect-db db)
    (print (setup-complete)))

(define (setup db)
    (let (
        (description-input (read-config-input (setup-description) "pocket money"))
        (amount-input (read-config-input (setup-income) "100"))
        (overdraft-input (read-config-input (setup-overdraft) "200")))
        (insert-configuration db CONF-INCOME-DESCRIPTION description-input)
        (insert-configuration db CONF-INCOME-AMOUNT amount-input)
        (insert-configuration db CONF-OVERDRAFT overdraft-input)
        (insert-auto-income db (current-month) (current-year))))

;;;; loop

(define KEY-ADD #\+)
(define KEY-SUB #\-)
(define KEY-SHOW #\=)
(define KEY-HELP #\?)
(define KEY-QUIT #\:)

(define (loop)
    (let ((db (connect-db)))
        (insert-all-due-incomes db)
        (prntln (current-balance (balance db)))
        (handle-info)
        (handle-input db (input (enter-input)))
        (disconnect-db db)))

(define (handle-input db inp)
    (if
        (not (and
            (= (string-length inp) 1)
            (cond
                ((char=? (string-ref inp 0) KEY-ADD) (handle-add db))
                ((char=? (string-ref inp 0) KEY-SUB) (handle-sub db))
                ((char=? (string-ref inp 0) KEY-SHOW) (handle-show db))
                ((char=? (string-ref inp 0) KEY-HELP) (handle-help))
                ((char=? (string-ref inp 0) KEY-QUIT) (prntln (bye))))))
        (if (and
                (> (string-length inp) 1)
                (or
                    (char=? (string-ref inp 0) KEY-ADD)
                    (char=? (string-ref inp 0) KEY-SUB)))
            (omg)
            (handle-info)))
    (if (not (and (= (string-length inp) 1) (char=? (string-ref inp 0) KEY-QUIT)))
        (handle-input db (input (enter-input)))
        #t))

(define (handle-add db)
    (add-to-ledger db 1 (income-booked)))

(define (handle-sub db)
    (add-to-ledger db -1 (expense-booked)))

(define (add-to-ledger db signum success-message)
    (let
        ((description (input (enter-description)))
        (amount (string->number (input (enter-amount)))))
        (if (eq? amount #f) (set! amount 0))
        (cond
            ((> amount 0)
                (if (or (= signum 1) (is-expense-acceptable db amount))
                    (begin
                        (insert-into-ledger db description (* amount signum))
                        (prntln success-message)
                        (prntln (current-balance (balance db))))
                    (prntln (error-too-expensive))))
            ((< amount 0) (prntln (error-negative-amount)))
            ((= amount 0) (prntln (error-zero-or-invalid-amount))))))

(define (handle-show db)
    (prnt (formatted-balance (balance db) (transactions db))))

(define (handle-info)
    (prnt (info)))

(define (handle-help)
    (prnt (help)))

(define (omg)
    (prntln (error-omg)))

;;;; text-resources

(define (banner)
    "
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/

<TAB>CHICKEN Scheme 5.3 Edition


")

(define (info)
    "
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

")

(define (help)
    "
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
<TAB>you won''t be able to add an expense if the balance would be less than -200 afterwards.

<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser
<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.

<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.

")

(define (setup-pre-database)
    "
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
")

(define (setup-post-database)
    "
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

")

(define (setup-complete)
    "setup complete, have fun")

(define (error-omg)
    "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that")

(define (error-zero-or-invalid-amount)
    "amount is zero or invalid -> action aborted")

(define (error-negative-amount)
    "amount must be positive -> action aborted")

(define (income-booked)
    "income booked")

(define (expense-booked)
    "expense booked successfully")

(define (error-too-expensive)
    "sorry, too expensive -> action aborted")

(define (enter-input)
    "input")

(define (enter-description)
    "description (optional)")

(define (enter-amount)
    "amount")

(define (bye)
    "see ya")

(define (current-balance val)
    (conc "
<TAB>current balance: " val "
"))

(define (formatted-balance balance formatted)
    (conc (current-balance balance) "
<TAB>last transactions (up to 30)
<TAB>----------------------------
" formatted "
"))

(define (setup-description)
    "enter description for regular income")

(define (setup-income)
    "enter regular income")

(define (setup-overdraft)
    "enter overdraft")

(define (setup-template description standard)
    (conc description " [default: " standard "]"))

;;;; main

(prnt (banner))
(setup-on-first-run)
(loop)
