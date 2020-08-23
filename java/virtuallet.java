import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Scanner;

public class virtuallet {

    static final String DB_FILE = "../db_virtuallet.db";
    static final String CONF_INCOME_DESCRIPTION = "income_description";
    static final String CONF_INCOME_AMOUNT = "income_amount";
    static final String CONF_OVERDRAFT = "overdraft";

    public static void main(String... args) {
        final var database = new Database();
        final var setup = new Setup(database);
        final var loop = new Loop(database);
        Util.printLine(TextResources.banner());
        try {
            setup.setupOnFirstRun();
            loop.loop();
        } catch (SQLException throwables) {
            throwables.printStackTrace();
            Util.print("Ouch that hurt...");
        }
    }

}

class Database {

    private Connection connection;

    void connect() throws SQLException {
        if (connection == null) {
            connection = DriverManager.getConnection(String.format("jdbc:sqlite:%s", virtuallet.DB_FILE));
        }
    }

    void disconnect() throws SQLException {
        connection.close();
    }

    private void executeStatement(final String sql) throws SQLException {
        try (var statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    void createTables() throws SQLException {
        executeStatement(" CREATE TABLE ledger ( "
                    + " description TEXT, "
                    + " amount REAL NOT NULL, "
                    + " auto_income INTEGER NOT NULL, "
                    + " created_at TIMESTAMP NOT NULL, "
                    + " modified_at TIMESTAMP) ");
        executeStatement(" CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL) ");
    }

    void insertConfiguration(final String key, final Object value) throws SQLException {
        executeStatement(String.format(" INSERT INTO configuration (k, v) VALUES ('%s', '%s') ", key, value));
    }

    void insertIntoLedger(final String description, final BigDecimal amount) throws SQLException {
        executeStatement(String.format(" INSERT INTO ledger (description, amount, auto_income, created_at, modified_at) "
                        + " VALUES ('%s', %f, %d, '%s', '%s')",
                description, amount.doubleValue(), 0, Util.isoDateString(LocalDateTime.now()), null));
    }

    BigDecimal balance() throws SQLException {
        try (var statement = connection.createStatement()) {
            final var result = statement.executeQuery(" SELECT SUM(amount) FROM ledger ");
            return result.next() ? result.getBigDecimal(1).setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO;
        }
    }

    String transactions() throws SQLException {
        try (var statement = connection.createStatement()) {
            final var result = statement.executeQuery(
                    " SELECT created_at, amount, description FROM ledger ORDER BY created_at DESC LIMIT 30 ");
            final var rows = new ArrayList<String>();
            while (result.next()) {
                rows.add("        " + String.join("\t", Arrays.asList(
                        result.getString(1),
                        result.getBigDecimal(2).setScale(2, RoundingMode.HALF_UP).toString(),
                        result.getString(3)
                )));
            }
            return String.join("\n", rows);
        }
    }

    private String incomeDescription() throws SQLException {
        try (var statement = connection.createStatement()) {
            final var result = statement.executeQuery(String.format(
                    " SELECT v FROM configuration WHERE k = '%s'", virtuallet.CONF_INCOME_DESCRIPTION));
            return result.next() ? result.getString(1) : "pocket money";
        }
    }

    private BigDecimal incomeAmount() throws SQLException {
        try (var statement = connection.createStatement()) {
            final var result = statement.executeQuery(String.format(
                    " SELECT v FROM configuration WHERE k = '%s'", virtuallet.CONF_INCOME_AMOUNT));
            return result.next() ? result.getBigDecimal(1) : BigDecimal.valueOf(100);
        }
    }

    private BigDecimal overdraft() throws SQLException {
        try (var statement = connection.createStatement()) {
            final var result = statement.executeQuery(String.format(
                    " SELECT v FROM configuration WHERE k = '%s'", virtuallet.CONF_INCOME_AMOUNT));
            return result.next() ? result.getBigDecimal(1) : BigDecimal.valueOf(200);
        }
    }

    boolean isExpenseAcceptable(final BigDecimal expense) throws SQLException {
        return balance().add(overdraft()).subtract(expense).signum() != -1;
    }

    void insertAllDueIncomes() throws SQLException {
        class MonthAndYear {
            final int month;
            final int year;
             MonthAndYear(int month, int year) {
                 this.month = month;
                 this.year = year;
             }
        }
        final var dueDates = new ArrayList<MonthAndYear>();
        var dueDate = new MonthAndYear(
                LocalDateTime.now().getMonth().getValue(),
                LocalDateTime.now().getYear());
        while (!hasAutoIncomeForMonth(dueDate.month ,dueDate.year)) {
            dueDates.add(dueDate);
            dueDate = new MonthAndYear(
                    dueDate.month > 1 ? dueDate.month - 1 : 12,
                    dueDate.month > 1 ? dueDate.year : dueDate.year - 1);
            Collections.reverse(dueDates);
            dueDates.forEach(due -> insertAutoIncome(due.month, due.year));
        }
    }

    void insertAutoIncome(final int month, final int year) {
        try {
            final var description = String.format("%s %02d/%d", incomeDescription(), month, year);
            final var amount = incomeAmount();
            executeStatement(String.format(" INSERT INTO ledger (description, amount, auto_income, created_at) "
                    + "VALUES ('%s', %f, %d, '%s') ", description, amount.doubleValue(), 1, Util.isoDateStringNow()));
        } catch (SQLException throwables) {
            throw new RuntimeException(throwables);
        }
    }

    boolean hasAutoIncomeForMonth(final int month, final int year) throws SQLException {
        try (var statement = connection.createStatement()) {
            final var result = statement.executeQuery(String.format(
                    " SELECT EXISTS( "
                            + " SELECT auto_income FROM ledger "
                            + " WHERE auto_income = 1 "
                            + " AND description LIKE '%s')", String.format("%% %02d/%d", month, year)));
            return result.next() && result.getBigDecimal(1).signum() == 1;
        }
    }

}

class Loop {

    private static final String KEY_ADD = "+";
    private static final String KEY_SUB = "-";
    private static final String KEY_SHOW = "=";
    private static final String KEY_HELP = "?";
    private static final String KEY_QUIT = ":";

    private final Database database;

    Loop(final Database database) {
        this.database = database;
    }

    void loop() throws SQLException {
        database.connect();
        database.insertAllDueIncomes();
        Util.printLine(TextResources.currentBalance(database.balance()));
        handleInfo();
        var looping = true;
        while (looping) {
            final var input = Util.input(TextResources.enterInput());
            if (KEY_ADD.equals(input)) {
                handleAdd();
            } else if (KEY_SUB.equals(input)) {
                handleSub();
            } else if (KEY_SHOW.equals(input)) {
                handleShow();
            } else if (KEY_HELP.equals(input)) {
                handleHelp();
            } else if (KEY_QUIT.equals(input)) {
                looping = false;
            } else if (Util.firstCharMatches(input, KEY_ADD) || Util.firstCharMatches(input, KEY_SUB)) {
                omg();
            } else {
                handleInfo();
            }
        }
        database.disconnect();
        Util.printLine(TextResources.bye());
    }

    private static void omg() {
        Util.printLine(TextResources.errorOmg());
    }

    private void handleAdd() throws SQLException {
        addToLedger(1, TextResources.incomeBooked());
    }

    private void handleSub() throws SQLException {
        addToLedger(-1, TextResources.expenseBooked());
    }

    private void addToLedger(final int signum, final String successMessage) throws SQLException {
        final var description = Util.input(TextResources.enterDescription());
        final var amount = new BigDecimal(Util.input(TextResources.enterAmount()));
        if (amount.signum() == 1) {
            if (signum == 1 || database.isExpenseAcceptable(amount)) {
                database.insertIntoLedger(description, amount.multiply(BigDecimal.valueOf(signum)));
                Util.print(successMessage);
            } else {
                Util.print(TextResources.errorTooExpensive());
            }
        } else if (amount.signum() == -1) {
            Util.print(TextResources.errorNegativeAmount());
        } else {
            Util.print(TextResources.errorZeroOrInvalidAmount());
        }
    }

    private void handleShow() throws SQLException {
        Util.printLine(TextResources.formattedBalance(database.balance(), database.transactions()));
    }

    private static void handleInfo() {
        Util.printLine(TextResources.info());
    }

    private static void handleHelp() {
        Util.printLine(TextResources.help());
    }

}

class Setup {

    private final Database database;

    Setup(final Database database) {
        this.database = database;
    }

    void setupOnFirstRun() throws SQLException {
        if (Files.notExists(Paths.get(virtuallet.DB_FILE))) {
            initialize();
        }
    }

    private void initialize() throws SQLException {
        Util.printLine(TextResources.setupPreDatabase());
        database.connect();
        database.createTables();
        Util.printLine(TextResources.setupPostDatabase());
        setup();
        Util.printLine(TextResources.setupComplete());
    }

    private void setup() throws SQLException {
        final var incomeDescription = Util.readConfigInput(TextResources.setupDescription(), "pocket money");
        final var incomeAmount = Util.readConfigInput(TextResources.setupIncome(), 100);
        final var overdraft = Util.readConfigInput(TextResources.setupOverdraft(), 200);
        database.insertConfiguration(virtuallet.CONF_INCOME_DESCRIPTION, incomeDescription);
        database.insertConfiguration(virtuallet.CONF_INCOME_AMOUNT, incomeAmount);
        database.insertConfiguration(virtuallet.CONF_OVERDRAFT, overdraft);
        database.insertAutoIncome(LocalDate.now().getMonthValue(), LocalDate.now().getYear());
    }

}

class Util {

    private static final Scanner in = new Scanner(System.in);

    static void print(final String message) {
        System.out.print(message);
    }

    static void printLine(final String message) {
        print(String.format("%s%s", message, System.lineSeparator()));
    }

    static String input(final String message) {
        print(message);
        return in.nextLine();
    }

    static boolean firstCharMatches(final String str1, final String str2) {
        return str1 != null && str2 != null && !str1.isEmpty() && !str2.isEmpty() && str1.charAt(0) == str2.charAt(0);
    }

    static String isoDateStringNow() {
        return isoDateString(LocalDateTime.now());
    }

    static String isoDateString(final LocalDateTime dateTime) {
        return dateTime.format(DateTimeFormatter.ISO_DATE_TIME);
    }

    static String readConfigInput(final String description, final Object standard) {
        final var input = input(TextResources.setupTemplate(description, standard.toString()));
        return input.isBlank() ? standard.toString() : input;
    }

}

class TextResources {

    static String banner() {
        return "\n"
                + "     _                                 _   _\n"
                + "    (_|   |_/o                        | | | |\n"
                + "      |   |      ,_  _|_         __,  | | | |  _ _|_\n"
                + "      |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |\n"
                + "       \\_/   |_/   |_/|_/ \\_/|_/\\_/|_/|__/|__/|__/|_/\n"
                + "\n"
                + "    Java 11 Edition\n"
                + "\n\n";
    }

    static String info() {
        return "\n"
                + "        Commands:\n"
                + "        - press plus (+) to add an irregular income\n"
                + "        - press minus (-) to add an expense\n"
                + "        - press equals (=) to show balance and last transactions\n"
                + "        - press question mark (?) for even more info about this program\n"
                + "        - press colon (:) to exit\n";
    }

    static String help() {
        return "\n"
                + "        Virtuallet is a tool to act as your virtual wallet. Wow...\n"
                + "        Virtuallet is accessible via terminal and uses a Sqlite database to store all its data.\n"
                + "        On first start Virtuallet will be configured and requires some input\n"
                + "        but you already know that unless you are currently studying the source code.\n"
                + "\n"
                + "        Virtuallet follows two important design principles:\n"
                + "\n"
                + "        - shit in shit out\n"
                + "        - UTFSB (Use The F**king Sqlite Browser)\n"
                + "\n"
                + "        As a consequence everything in the database is considered valid.\n"
                + "        Program behaviour is unspecified for any database content being invalid. Ouch...\n"
                + "\n"
                + "        As its primary feature Virtuallet will auto-add the configured income on start up\n"
                + "        for all days in the past since the last registered regular income.\n"
                + "        So if you have specified a monthly income and haven't run Virtuallet for three months\n"
                + "        it will auto-create three regular incomes when you boot it the next time if you like it or not.\n"
                + "\n"
                + "        Virtuallet will also allow you to add irregular incomes and expenses manually.\n"
                + "        It can also display the current balance and the 30 most recent transactions.\n"
                + "\n"
                + "        The configured overdraft will be considered if an expense is registered.\n"
                + "        For instance if your overdraft equals the default value of 200\n"
                + "        you won't be able to add an expense if the balance would be less than -200 afterwards.\n"
                + "\n"
                + "        Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser\n"
                + "        to view and even edit the database. When making updates please remember the shit in shit out principle.\n"
                + "\n"
                + "        As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it.\n";
    }

    static String setupPreDatabase() {
        return "\n"
                + "        Database file not found.\n"
                + "        Database will be initialized. This may take a while... NOT.";
    }

    static String setupPostDatabase() {
        return "\n"
                + "        Database initialized.\n"
                + "        Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar.\n"
                + "        Press enter to accept the default or input something else. There is no validation\n"
                + "        because I know you will not make a mistake. No second chances. If you f**k up,\n"
                + "        you will have to either delete the database file or edit it using a sqlite database browser.\n";
    }

    static String errorZeroOrInvalidAmount() {
        return "amount is zero or invalid -> action aborted\n";
    }

    static String errorNegativeAmount() {
        return "amount must be positive -> action aborted\n";
    }

    static String incomeBooked() {
        return "income booked\n";
    }

    static String expenseBooked() {
        return "expense booked successfully\n";
    }

    static String errorTooExpensive() {
        return "sorry, too expensive -> action aborted\n";
    }

    static String errorOmg() {
        return "OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that\n";
    }

    static String enterInput() {
        return "input > ";
    }

    static String enterDescription() {
        return "description (optional) > ";
    }

    static String enterAmount() {
        return "amount > ";
    }

    static String setupComplete() {
        return "setup complete, have fun\n";
    }

    static String bye() {
        return "see ya\n";
    }

    static String currentBalance(final BigDecimal balance) {
        return String.format("        current balance: %s\n", balance);
    }

    static String formattedBalance(final BigDecimal balance, final String formattedLastTransactions) {
        return String.format("\n"
                + "        current balance: %s\n"
                + "\n"
                + "        last transactions (up to 30)\n"
                + "        ----------------------------\n"
                + "%s\n", balance, formattedLastTransactions);
    }

    static String setupDescription() {
        return "enter description for regular income";
    }

    static String setupIncome() {
        return "enter regular income";
    }

    static String setupOverdraft() {
        return "enter overdraft";
    }

    static String setupTemplate(final String description, final String standard) {
        return String.format("%s [default: %s] > ", description, standard);
    }

}

