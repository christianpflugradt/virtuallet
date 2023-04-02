{-# Language OverloadedStrings #-}
import Control.Applicative
import Control.Exception
import Control.Monad
import qualified Data.Text as T
import Database.SQLite.Simple
import Data.Char
import Data.String
import Data.Time
import Data.Typeable
import System.Directory
import System.IO
import Text.Printf
import Text.Read

data KeyValueField = KeyValueField T.Text T.Text deriving(Show)
instance ToRow KeyValueField where
    toRow (KeyValueField key value) = toRow (key, value)

data DescriptionAmountField = DescriptionAmountField T.Text Float deriving(Show)
instance ToRow DescriptionAmountField where
    toRow (DescriptionAmountField description amount) = toRow (description, amount)

data FloatField = FloatField { _float :: Float } deriving(Show)
instance FromRow FloatField where
    fromRow = FloatField <$> field

data IntField = IntField { _int :: Int } deriving(Show)
instance FromRow IntField where
    fromRow = IntField <$> field

data TextField = TextField { _text :: T.Text } deriving(Show)
instance FromRow TextField where
    fromRow = TextField <$> field
instance ToRow TextField where
    toRow (TextField _text) = toRow (Only _text)

data TransactionsField = TransactionsField { _createdAt :: T.Text, _amount :: Float, _description :: T.Text } deriving(Show)
instance FromRow TransactionsField where
    fromRow = TransactionsField <$> field <*> field <*> field

_DB_FILE = "../db_virtuallet.db"
_CONF_INCOME_DESCRIPTION = "income_description"
_CONF_INCOME_AMOUNT = "income_amount"
_CONF_OVERDRAFT = "overdraft"
_TAB = "<TAB>"

-- util

prnt = putStr . T.unpack . T.replace _TAB "\t" . T.pack
prntln = prnt . (++ "\n")

input prefix = do
    prnt prefix
    hFlush stdout
    response <- getLine
    return response :: IO String

readConfigInput description standard = do
    response <- input $ setupTemplate description standard
    if T.all isSpace . fromString $ response then pure standard else pure response

yearMonthDay = fmap (toGregorian . localDay . zonedTimeToLocalTime) getZonedTime

fst3 (x,_,_) = x
snd3 (_,x,_) = x

-- database

connect = open _DB_FILE
disconnect con = do close con

createTables con = execute_ con "CREATE TABLE ledger ( \
            \ description TEXT, \
            \ amount REAL NOT NULL, \
            \ auto_income INTEGER NOT NULL, \
            \ created_by TEXT, \
            \ created_at TIMESTAMP NOT NULL, \
            \ modified_at TIMESTAMP)" >>
    execute_ con "CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)"

insertConfiguration con key value = execute con "INSERT INTO configuration (k, v) VALUES (?, ?)" (KeyValueField key value)

insertIntoLedger con description amount = execute con "INSERT INTO ledger (description, amount, auto_income, created_at, created_by) \
        \ VALUES (?, ROUND(?, 2), 0, datetime('now'), 'GHC 9.4 Edition')" (DescriptionAmountField description amount)

balance con = do
    result <- query_ con "SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger" :: IO [FloatField]
    return (_float (head result))

transactions con = do
    result <- query_ con "SELECT created_at, amount, description FROM ledger ORDER BY ROWID DESC LIMIT 30" :: IO [TransactionsField]
    return (unlines (map (\row -> printf "\t%s\t%02f\t%s" (_createdAt row) (_amount row) (_description row)) result))

incomeDescription con = do
    result <- query con "SELECT v FROM configuration WHERE k = ?" (TextField _CONF_INCOME_DESCRIPTION) :: IO [TextField]  
    return (_text (head result))

incomeAmount con = do
    result <- query con "SELECT CAST(v AS FLOAT) FROM configuration WHERE k = ?" (TextField _CONF_INCOME_AMOUNT) :: IO [FloatField]  
    return (_float (head result))

overdraft con = do
    result <- query con "SELECT CAST(v AS FLOAT) FROM configuration WHERE k = ?" (TextField _CONF_OVERDRAFT) :: IO [FloatField]  
    return (_float (head result))

isExpenseAcceptable con expense = do
    bal <- balance con
    ovr <- overdraft con
    return (bal + ovr - expense >= 0)

insertAllDueIncomes con = do
    (y,m,_) <- yearMonthDay
    dueDates <- collectDueIncomes con m y (pure [])
    mapM (\dueDate -> insertAutoIncome con (fst dueDate) (snd dueDate)) dueDates
    
collectDueIncomes con month year dues = do
    dueDates <- dues
    hasAutoIncome <- hasAutoIncomeForMonth con month year
    case hasAutoIncome of
        True -> return dueDates
        False -> collectDueIncomes
                    con
                    (if month == 1 then 12 else (month-1))
                    (if month == 1 then (year-1) else year)
                    (pure ((month, year) : dueDates))

insertAutoIncome con month year = do
    description <- incomeDescription con
    amount <- incomeAmount con
    execute con "INSERT INTO ledger (description, amount, auto_income, created_at, created_by) \
            \ VALUES (?, ROUND(?, 2), 1, datetime('now'), 'GHC 9.4 Edition')"
        (DescriptionAmountField (T.pack $ printf "%s %02d/%d" description month year) amount)

hasAutoIncomeForMonth con month year = do
    let statement = "SELECT EXISTS( \
        \ SELECT auto_income FROM ledger \
        \ WHERE auto_income = 1 \
        \ AND description LIKE " ++ (printf "'%% %02d/%d')" month year)
    result <- query_ con (Query . T.pack $ statement) :: IO [IntField]
    return (_int (head result) == 1)

-- setup

setupOnFirstRun = do
    databaseExists <- doesFileExist _DB_FILE
    unless databaseExists initialize

initialize = do
    prnt setupPreDatabase
    con <- connect
    createTables con
    prnt setupPostDatabase
    setup con
    prntln setupComplete

setup con = do
    incomeDescription <- readConfigInput setupDescription "pocket money"
    incomeAmount <- readConfigInput setupIncome "100"
    incomeOverdraft <- readConfigInput setupOverdraft "200"
    insertConfiguration con _CONF_INCOME_DESCRIPTION (fromString incomeDescription)
    insertConfiguration con _CONF_INCOME_AMOUNT (fromString incomeAmount)
    insertConfiguration con _CONF_OVERDRAFT (fromString incomeOverdraft)
    (y,m,_) <- yearMonthDay
    insertAutoIncome con m y
    
-- loop

_KEY_ADD = "+"
_KEY_SUB = "-"
_KEY_SHOW = "="
_KEY_HELP = "?"
_KEY_QUIT = ":"

loop = do
    con <- connect
    insertAllDueIncomes con
    balanceVal <- balance con
    prntln . currentBalance $ balanceVal
    handleInfo
    innerLoop con
    disconnect con    
    prntln bye

innerLoop con = do
    inp <- input enterInput
    unless (inp == _KEY_QUIT) $ do
        innerLoopAction con (T.pack inp)
        innerLoop con

innerLoopAction con inp
    | inp == _KEY_ADD = handleAdd con
    | inp == _KEY_SUB = handleSub con
    | inp == _KEY_SHOW = handleShow con
    | inp == _KEY_HELP = handleHelp
    | (T.take 1 inp) == (T.take 1 _KEY_ADD) || (T.take 1 inp) == (T.take 1 _KEY_SUB) = omg
    | otherwise = handleInfo

handleAdd con = do addToLedger con 1 incomeBooked
handleSub con = do addToLedger con (-1) expenseBooked

addToLedger con signum successMessage = do
    description <- input enterDescription
    amountStr <- input enterAmount
    let amount = maybe 0 (\x->x) (readMaybe amountStr :: Maybe Float)
    acceptable <- isExpenseAcceptable con amount
    innerAddToLedger con description amount acceptable signum successMessage
    
innerAddToLedger con description amount acceptable signum successMessage
    | amount < 0 = prntln errorNegativeAmount
    | amount == 0 = prntln errorZeroOrInvalidAmount
    | acceptable = do
        insertIntoLedger con (T.pack description) (amount * (fromIntegral signum))
        prntln successMessage
        balanceVal <- balance con
        prntln (currentBalance balanceVal)
    | otherwise = prntln errorTooExpensive

omg = prntln errorOmg
handleInfo = prnt info
handleHelp = prnt help
handleShow con = do
    trans <- transactions con
    balanceVal <- balance con
    prntln (formattedBalance balanceVal trans)

-- text resources

banner = "\n\
\<TAB> _                                 _   _\n\
\<TAB>(_|   |_/o                        | | | |\n\
\<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_\n\
\<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |\n\
\<TAB>   \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/\n\
\\n\
\<TAB>GHC 9.4 Edition\n\
\\n\
\\n\
\"

info = "\n\
\<TAB>Commands:\n\
\<TAB>- press plus (+) to add an irregular income\n\
\<TAB>- press minus (-) to add an expense\n\
\<TAB>- press equals (=) to show balance and last transactions\n\
\<TAB>- press question mark (?) for even more info about this program\n\
\<TAB>- press colon (:) to exit\n\
\\n\
\"

help = "\n\
\<TAB>Virtuallet is a tool to act as your virtual wallet. Wow...\n\
\<TAB>Virtuallet is accessible via terminal and uses a Sqlite database to store all its data.\n\
\<TAB>On first start Virtuallet will be configured and requires some input\n\
\<TAB>but you already know that unless you are currently studying the source code.\n\
\\n\
\<TAB>Virtuallet follows two important design principles:\n\
\\n\
\<TAB>- shit in shit out\n\
\<TAB>- UTFSB (Use The F**king Sqlite Browser)\n\
\\n\
\<TAB>As a consequence everything in the database is considered valid.\n\
\<TAB>Program behaviour is unspecified for any database content being invalid. Ouch...\n\
\\n\
\<TAB>As its primary feature Virtuallet will auto-add the configured income on start up\n\
\<TAB>for all days in the past since the last registered regular income.\n\
\<TAB>So if you have specified a monthly income and haven't run Virtuallet for three months\n\
\<TAB>it will auto-create three regular incomes when you boot it the next time if you like it or not.\n\
\\n\
\<TAB>Virtuallet will also allow you to add irregular incomes and expenses manually.\n\
\<TAB>It can also display the current balance and the 30 most recent transactions.\n\
\\n\
\<TAB>The configured overdraft will be considered if an expense is registered.\n\
\<TAB>For instance if your overdraft equals the default value of 200\n\
\<TAB>you won't be able to add an expense if the balance would be less than -200 afterwards.\n\
\\n\
\<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser\n\
\<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle.\n\
\\n\
\<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.\n\
\\n\
\"

setupPreDatabase = "\n\
\<TAB>Database file not found.\n\
\<TAB>Database will be initialized. This may take a while... NOT.\n\
\"

setupPostDatabase = "\n\
\<TAB>Database initialized.\n\
\<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.\n\
\<TAB>Press enter to accept the default or input something else. There is no validation\n\
\<TAB>because I know you will not make a mistake. No second chances. If you f**k up,\n\
\<TAB>you will have to either delete the database file or edit it using a sqlite database browser.\n\
\\n\
\"

errorZeroOrInvalidAmount = "amount is zero or invalid -> action aborted"
errorNegativeAmount = "amount must be positive -> action aborted"
incomeBooked = "income booked"
expenseBooked = "expense booked successfully"
errorTooExpensive = "sorry, too expensive -> action aborted"
errorOmg = "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that"
enterInput = "input > "
enterDescription = "description (optional) > "
enterAmount = "amount > "
setupComplete = "setup complete, have fun"
bye = "see ya"

currentBalance balanceVal = "\n" ++ "<TAB>current balance: " ++ (show balanceVal) ++ "\n"

formattedBalance balance formattedLastTransactions = (currentBalance balance) ++ "\n\
\<TAB>last transactions (up to 30)\n\
\<TAB>----------------------------\n" ++ formattedLastTransactions

setupDescription = "enter description for regular income"
setupIncome = "enter regular income"
setupOverdraft = "enter overdraft"
setupTemplate description standard = description ++ " [default: " ++ standard ++ "] > "

main = do
    prnt banner
    setupOnFirstRun
    loop
