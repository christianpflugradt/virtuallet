(load "~/quicklisp/setup.lisp")
(asdf:load-system :sqlite)
(use-package :sqlite)
(use-package :iter)

(defconstant CONF-INCOME-DESCRIPTION "income_description")
(defconstant CONF-INCOME-AMOUNT "income_amount")
(defconstant CONF-OVERDRAFT "overdraft")
(defconstant DB-FILE "../db_virtuallet.db")
(defconstant TAB "<TAB>")

(defun prnt (str)
    (format t (replace-all str TAB "~4@T"))
    (= 0 0))

(defun prntln (str)
    (prnt (format nil "~a~%" str)))

(defun input (prefix)
    (prnt prefix)
    (prnt " > ")
    (finish-output)
    (read-line))

(defun input-number (prefix)
    (handler-case
        (with-input-from-string (inp (input prefix)) (+ 0 (read inp)))
        (error (c) 0)))

(defun read-config-input (description default)
    (let ((inp (input (setup-template description default))))
        (if (= (length inp) 0) default inp)))

(defun replace-all (str old new)
    (let ((pos (search old str)))
        (if pos
            (replace-all
                (concatenate 'string (subseq str 0 pos) new (subseq str (+ pos (length old)) (length str)))
                old
                new)
            str)))

(defun current-month ()
    (multiple-value-bind (a b c d month year g h i) (get-decoded-time) month))

(defun current-year ()
    (multiple-value-bind (a b c d month year g h i) (get-decoded-time) year))

(defclass database ()
    ((dbcon :initform nil :accessor dbcon)))

(defun create-database ()
    (make-instance 'database))

(defmethod connect-db ((d database))
    (if (not (dbcon d)) (setf (dbcon d) (connect DB-FILE))))

(defmethod disconnect-db ((d database))
    (disconnect (dbcon d)))

(defmethod create-tables ((d database))
    (execute-non-query (dbcon d) "
        CREATE TABLE ledger (
            description TEXT,
            amount REAL NOT NULL,
            auto_income INTEGER NOT NULL,
            created_by TEXT,
            created_at TIMESTAMP NOT NULL,
            modified_at TIMESTAMP)
    ")
    (execute-non-query (dbcon d) "CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)"))

(defmethod insert-configuration ((d database) key value)
    (execute-non-query (dbcon d) "INSERT INTO configuration (k, v) VALUES (?, ?)" key value))

(defmethod insert-into-ledger ((d database) description amount)
    (execute-non-query (dbcon d) "
        INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
        VALUES (?, ROUND(?, 2), 0, datetime('now'), 'SBCL 2.1 Edition')" description amount))

(defmethod balance ((d database))
    (execute-single (dbcon d) "SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger"))

(defmethod income-description ((d database))
    (execute-single (dbcon d) "SELECT v FROM configuration WHERE k = ?" CONF-INCOME-DESCRIPTION))

(defmethod income-amount ((d database))
    (execute-single (dbcon d) "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?" CONF-INCOME-AMOUNT))

(defmethod overdraft ((d database))
    (execute-single (dbcon d) "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = ?" CONF-OVERDRAFT))

(defmethod transactions ((d database))
    (let
        ((formatted "")
        (lines (execute-to-list (dbcon d)
            "SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30")))
        (loop for line in lines do
            (loop for element in line do
                (setq formatted (concatenate
                    'string
                    formatted
                    TAB
                    (if (stringp element) element (format nil "~f" element)))))
            (setq formatted (format nil "~a~%" formatted)))
        formatted))

(defmethod is-expense-acceptable ((d database) expense)
    (> (- (+ (balance d) (overdraft d)) expense) 0))

(defmethod insert-auto-income ((d database) month year)
    (let ((description (format nil "~a ~a/~d"
            (income-description d)
            (format nil "~2,'0d" month)
            year))
        (amount (income-amount d)))
        (execute-non-query (dbcon d) "
            INSERT INTO ledger (description, amount, auto_income, created_at, created_by)
            VALUES (?, ROUND(?, 2), 1, datetime('now'), 'SBCL 2.1 Edition')" description amount)))

(defmethod insert-all-due-incomes ((d database))
    (let ((due-dates (collect-due-dates d (list (list (current-month) (current-year))))))
        (loop for due-date in due-dates do
            (if due-date (insert-auto-income d (first due-date) (second due-date))))))

(defmethod collect-due-dates ((d database) due-dates)
    (let ((last-due-date (first (reverse due-dates))))
        (if (has-auto-income-for-month d (first last-due-date) (second last-due-date))
            (cdr (reverse due-dates))
            (let ((due-date
                    (if (> (first last-due-date) 1)
                        (list (- (first last-due-date) 1) (second last-due-date))
                        (list 12 (- (second last-due-date) 1)))))
                (collect-due-dates d (append due-dates (list due-date)))))))

(defmethod has-auto-income-for-month ((d database) month year)
    (let ((description (format nil "~a ~a/~d"
            (income-description d)
            (format nil "~2,'0d" month)
            year)))
        (= 1 (execute-single (dbcon d) "
            SELECT CAST(EXISTS(
                SELECT auto_income FROM ledger
                WHERE auto_income = 1
                AND description LIKE ?) AS DECIMAL)" description))))

(defclass setup ()
    ((db :initarg :db :reader db)))

(defun create-setup(db)
    (make-instance 'setup :db db))

(defmethod setup-on-first-run ((s setup))
    (if (not (probe-file DB-FILE))
        (initialize s)))

(defmethod initialize ((s setup))
    (prnt (setup-pre-database))
    (connect-db (db s))
    (create-tables (db s))
    (prnt (setup-post-database))
    (set-up s)
    (prntln (setup-complete)))

(defmethod set-up ((s setup))
    (let ((descriptionInput (read-config-input (setup-description) "pocket money"))
        (amountInput (read-config-input (setup-income) "100"))
        (overdraftInput (read-config-input (setup-overdraft) "200")))
        (insert-configuration (db s) CONF-INCOME-DESCRIPTION descriptionInput)
        (insert-configuration (db s) CONF-INCOME-AMOUNT amountInput)
        (insert-configuration (db s) CONF-OVERDRAFT overdraftInput)
        (insert-auto-income (db s) (current-month) (current-year))))

(defclass looop ()
    ((db :initarg :db :reader db)
    (KEY-ADD :initform "+" :reader KEY-ADD)
    (KEY-SUB :initform "-" :reader KEY-SUB)
    (KEY-SHOW :initform "=" :reader KEY-SHOW)
    (KEY-HELP :initform "?" :reader KEY-HELP)
    (KEY-QUIT :initform ":" :reader KEY-QUIT)))

(defun create-looop (db)
    (make-instance 'looop :db db))

(defmethod looop ((l looop))
    (connect-db (db l))
    (insert-all-due-incomes (db l))
    (prntln (current-balance (balance (db l))))
    (handle-info l)
    (let ((done nil))
        (loop
            (when done (return))
            (setq done (handle-input l (input (enter-input))))))
    (disconnect-db (db l)))

(defmethod handle-input ((l looop) inp)
    (if
        (not (cond
            ((string= inp (KEY-ADD l)) (handle-add l))
            ((string= inp (KEY-SUB l)) (handle-sub l))
            ((string= inp (KEY-SHOW l)) (handle-show l))
            ((string= inp (KEY-HELP l)) (handle-help l))
            ((string= inp (KEY-QUIT l)) (prntln (bye)))))
        (if (and
                (> (length inp) 1)
                (or
                    (string= (subseq inp 0 1) (KEY-ADD l))
                    (string= (subseq inp 0 1) (KEY-SUB l))))
            (omg l)
            (handle-info l)))
    (string= inp (KEY-QUIT l)))

(defmethod handle-add ((l looop))
    (add-to-ledger l 1 (income-booked)))

(defmethod handle-sub ((l looop))
    (add-to-ledger l -1 (expense-booked)))

 (defmethod add-to-ledger ((l looop) signum success-message)
    (let
        ((description (input (enter-description)))
        (amount (input-number (enter-amount))))
        (cond
            ((> amount 0)
                (if (or (= signum 1) (is-expense-acceptable (db l) amount))
                    (progn
                        (insert-into-ledger (db l) description (* amount signum))
                        (prntln success-message)
                        (prntln (current-balance (balance (db l)))))
                    (prntln (error-too-expensive))))
            ((< amount 0) (prntln (error-negative-amount)))
            ((= amount 0) (prntln (error-zero-or-invalid-amount))))))

(defmethod handle-show ((l looop))
    (prnt (formatted-balance (balance (db l)) (transactions (db l)))))

(defmethod handle-info((l looop))
    (prnt (info)))

(defmethod handle-help ((l looop))
    (prnt (help)))

(defmethod omg ((l looop))
    (prntln (error-omg)))

;;;; text-resources

(defun banner ()
    (string "
<TAB> _                                 _   _
<TAB>(_|   |_/o                        | | | |
<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_
<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |
<TAB>   \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/

<TAB>SBCL 2.1 Edition


"))

(defun info ()
    (string "
<TAB>Commands:
<TAB>- press plus (+) to add an irregular income
<TAB>- press minus (-) to add an expense
<TAB>- press equals (=) to show balance and last transactions
<TAB>- press question mark (?) for even more info about this program
<TAB>- press colon (:) to exit

"))

(defun help ()
    (string "
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

"))

(defun setup-pre-database ()
    (string "
<TAB>Database file not found.
<TAB>Database will be initialized. This may take a while... NOT.
"))

(defun setup-post-database ()
    (string "
<TAB>Database initialized.
<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.
<TAB>Press enter to accept the default or input something else. There is no validation
<TAB>because I know you will not make a mistake. No second chances. If you f**k up,
<TAB>you will have to either delete the database file or edit it using a sqlite database browser.

"))

(defun setup-complete ()
    (string "setup complete, have fun"))

(defun error-omg ()
    (string "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that"))

(defun error-zero-or-invalid-amount ()
    (string "amount is zero or invalid -> action aborted"))

(defun error-negative-amount ()
    (string "amount must be positive -> action aborted"))

(defun income-booked ()
    (string "income booked"))

(defun expense-booked ()
    (string "expense booked successfully"))

(defun error-too-expensive ()
    (string "sorry, too expensive -> action aborted"))

(defun enter-input ()
    (string "input"))

(defun enter-description ()
    (string "description (optional)"))

(defun enter-amount ()
    (string "amount"))

(defun bye ()
    (string "see ya"))

(defun current-balance (val)
    (format nil "
<TAB>current balance: ~f
" val))

(defun formatted-balance (balance formatted)
    (concatenate 'string (current-balance balance) "
<TAB>last transactions (up to 30)
<TAB>----------------------------
" formatted "
"))

(defun setup-description ()
    (string "enter description for regular income"))

(defun setup-income ()
    (string "enter regular income"))

(defun setup-overdraft ()
    (string "enter overdraft"))

(defun setup-template (description standard)
    (concatenate 'string description " [default: " standard "]"))

;;;; main

(prnt (banner))
(defvar db (create-database))
(setup-on-first-run (create-setup db))
(looop (create-looop db))
