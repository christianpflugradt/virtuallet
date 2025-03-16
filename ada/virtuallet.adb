pragma Ada_2022;

with Ada.Calendar; use Ada.Calendar;
with Ada.Containers; use Ada.Containers;
with Ada.Containers.Vectors;
with Ada.Directories; use Ada.Directories;
with Ada.Long_Float_Text_IO; use Ada.Long_Float_Text_IO;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with Interfaces.C;
with SQLite;
with SQLite.Connections; use SQLite.Connections;
with SQLite.Statements; use SQLite.Statements;
with SQLite.Statements.Simple; use SQLite.Statements.Simple;

procedure Virtuallet is

DB_FILE : constant String := "../db_virtuallet.db";
CONF_INCOME_DESCRIPTION : constant String := "income_description";
CONF_INCOME_AMOUNT : constant String := "income_amount";
CONF_OVERDRAFT : constant String := "overdraft";
TAB : constant String := "<TAB>";

package Text_Resources is
  function Banner return String;
  function Info return String;
  function Help return String;
  function Setup_Pre_Database return String;
  function Setup_Post_Database return String;
  function Error_Zero_Or_Invalid_Amount return String;
  function Error_Negative_Amount return String;
  function Income_Booked return String;
  function Expense_Booked return String;
  function Error_Too_Expensive return String;
  function Error_Omg return String;
  function Enter_Input return String;
  function Enter_Description return String;
  function Enter_Amount return String;
  function Setup_Complete return String;
  function Bye return String;
  function Current_Balance(Balance : Long_Float) return String;
  function Formatted_Balance(Balance : Long_Float; Formatted_Last_Transactions : String) return String;
  function Setup_Description return String;
  function Setup_Income return String;
  function Setup_Overdraft return String;
  function Setup_Template(Description, Standard : String) return String;
end Text_Resources;

package Util is
  procedure Print(Str : String);
  procedure Print_Ln(Str : String);
  function Input(Prompt : String) return Unbounded_String;
  function Read_Config_Input(Prefix : String; Standard : String) return String;
  function String_To_Long_Float(Str : String) return Long_Float;
  function Long_Float_To_String(LF : Long_Float) return String;
  function Integer_To_String(I : Integer) return String;
  function Format_Month(Value : Integer) return String;
end Util;

package body Util is

  procedure Print(Str : String) is
    Result : Unbounded_String := To_Unbounded_String(Str);
    Pos : Natural := Index(Str, TAB);
  begin
    while Pos > 0 loop
      Result := To_Unbounded_String(To_String(Result)(1 .. Pos - 1) & ASCII.HT & To_String(Result)(Pos + 5 .. To_String(Result)'Length));
      Pos := Index(To_String(Result), TAB);
    end loop;
    Put(To_String(Result));
  end Print;

  procedure Print_Ln(Str : String) is
  begin
    Print(Str & ASCII.LF);
  end Print_Ln;

  function Input(Prompt : String) return Unbounded_String is
  begin
    Print(Prompt);
    return To_Unbounded_String(Get_Line);
  end Input;

  function Read_Config_Input(Prefix : String; Standard : String) return String is
    Inp : Unbounded_String := Input(Text_Resources.Setup_Template(Prefix, Standard));
  begin
    return (if Length(Inp) = 0 then Standard else To_String(Inp));
  end Read_Config_Input;

  function String_To_Long_Float(Str : String) return Long_Float is
  begin
    return Long_Float'Value(Str);
  exception
    when others => return 0.0;
  end String_To_Long_Float;

  function Long_Float_To_String(LF : Long_Float) return String is
    Buffer : String(1 .. 32);
    Last : Natural;
  begin
    Put(To => Buffer, Item => LF, Aft => 2, Exp => 0);
    return Trim(Buffer, Side => Left);
  end Long_Float_To_String;

  function Integer_To_String(I : Integer) return String is
    Img : constant String := Integer'Image(I);
  begin
    if Img(Img'First) = ' ' then
      return Img(Img'First + 1 .. Img'Last);
    else
      return Img;
    end if;
  end Integer_To_String;

  function Format_Month(Value : Integer) return String is
  begin
    return (if Value < 10 then "0" else "") & Integer_To_String(Value);
  end Format_Month;

end Util;

type Database is limited record
  Con : Connection;
end record;

function Create_Database return Database is (Con => <>);

procedure Connect(Db : out Database) is
begin
  Db.Con := Open(DB_FILE);
end Connect;

procedure Disconnect(Db : out Database) is
begin
  Close(Db.Con);
end Disconnect;

procedure Create_Tables(Db : Database) is
begin
  Exec(Db.Con, "" &
    "CREATE TABLE ledger (" &
    "       description TEXT," &
    "       amount REAL NOT NULL," &
    "       auto_income INTEGER NOT NULL," &
    "       created_by TEXT," &
    "       created_at TIMESTAMP NOT NULL," &
    "       modified_at TIMESTAMP)");
  Exec(Db.Con, "CREATE TABLE configuration (k TEXT NOT NULL, v TEXT NOT NULL)");
end Create_Tables;

procedure Insert_Configuration(Db : Database; Key, Value : SQLite.UTF_8_String) is
  Stmt : Statement := Prepare(Db.Con, "INSERT INTO configuration (k, v) VALUES (:key, :value)");
  Done : Boolean;
begin
  Bind_Text(Stmt, ":key", Key);
  Bind_Text(Stmt, ":value", Value);
  Done := Step(Stmt);
  Finalize(Stmt);
end Insert_Configuration;

procedure Insert_Into_Ledger(Db : Database; Description : SQLite.UTF_8_String; Amount : Long_Float) is
  Stmt : Statement := Prepare(Db.Con, "INSERT INTO ledger (description, amount, auto_income, created_at, created_by) " &
    "VALUES (:description, ROUND(:amount, 2), 0, datetime('now'), 'Ada 2022 Edition')");
  Done : Boolean;
begin
  Bind_Text(Stmt, ":description", Description);
  Bind_Float(Stmt, ":amount", Interfaces.C.double(Amount));
  Done := Step(Stmt);
  Finalize(Stmt);
end Insert_Into_Ledger;

function Balance(Db : Database) return Long_Float is
begin
  return Long_Float(Exec_Float(Db.Con, "SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM ledger"));
end Balance;

function Transactions(Db : Database) return String is
   Stmt : Statement := Prepare(Db.Con, "SELECT created_at, CAST(amount AS TEXT), description FROM ledger ORDER BY ROWID DESC LIMIT 30");
   Rows : Unbounded_String := To_Unbounded_String("");
begin
   while Step(Stmt) loop
      declare
        Created_At : SQLite.UTF_8_String := Column_Text(Stmt, 0);
        Amount : SQLite.UTF_8_String := Column_Text(Stmt, 1);
        Description : SQLite.UTF_8_String := Column_Text(Stmt, 2);
        Row_Text : String := TAB & Created_At & TAB & Amount & TAB & Description;
      begin
        Rows := Rows & To_Unbounded_String(Row_Text & ASCII.LF);
      end;
   end loop;
   Finalize(Stmt);
   return To_String(Rows);
end Transactions;

function Income_Description(Db : Database) return String is
begin
  return Exec_Text(Db.Con, "SELECT v FROM configuration WHERE k = '" & CONF_INCOME_DESCRIPTION & "'");
end Income_Description;

function Income_Amount(Db : Database) return Long_Float is
begin
  return Long_Float(Exec_Float(Db.Con, "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = '" & CONF_INCOME_AMOUNT & "'"));
end Income_Amount;

function Overdraft(Db : Database) return Long_Float is
begin
  return Long_Float(Exec_Float(Db.Con, "SELECT CAST(v AS DECIMAL) FROM configuration WHERE k = '" & CONF_OVERDRAFT & "'"));
end Overdraft;

function Is_Expense_Acceptable(Db : Database; Expense : Long_Float) return Boolean is
begin
  return Balance(Db) + Overdraft(Db) - Expense >= 0.0;
end Is_Expense_Acceptable;

procedure Insert_Auto_Income(Db : Database; Month, Year : Integer) is
  Stmt : Statement := Prepare(Db.Con, "INSERT INTO ledger (description, amount, auto_income, created_at, created_by) " &
    "VALUES (:description, ROUND(:amount, 2), 1, datetime('now'), 'Ada 2022 Edition')");
  Description : SQLite.UTF_8_String := Income_Description(Db) & " " & Util.Format_Month(Month) & "/" & Util.Integer_To_String(Year);
  Done : Boolean;
begin
  Bind_Text(Stmt, ":description", Description);
  Bind_Float(Stmt, ":amount", Interfaces.C.double(Income_Amount(Db)));
  Done := Step(Stmt);
  Finalize(Stmt);
end Insert_Auto_Income;

function Has_Auto_Income_For_Month(Db : Database; Month, Year : Integer) return Boolean is
  Description : String := "%% " & Util.Format_Month(Month) & "/" & Util.Integer_To_String(Year);
begin
  return Exec_Integer(Db.Con, "SELECT EXISTS( " &
                                 " SELECT auto_income FROM ledger " &
                                 " WHERE auto_income = 1 " &
                                 " AND description LIKE '" & Description & "')") = 1;
end Has_Auto_Income_For_Month;

procedure Insert_All_Due_Incomes(Db : Database) is
  Now : Time := Clock;
  Year : Year_Number;
  Month : Month_Number;
  Day : Day_Number;
  Seconds : Day_Duration;
  type Due_Date is record
    Month : Integer;
    Year  : Integer;
  end record;
  package Due_Date_Vec is new Ada.Containers.Vectors
    (Index_Type   => Natural,
    Element_Type => Due_Date);
  use Due_Date_Vec;
  Due_Dates : Vector := Empty_Vector;
  Current   : Due_Date;
begin
  Split(Now, Year, Month, Day, Seconds);
  Current := (Month => Integer(Month), Year => Integer(Year));
  while not Has_Auto_Income_For_Month(Db, Current.Month, Current.Year) loop
    Append(Due_Dates, Current);
    if Current.Month > 1 then
      Current.Month := Current.Month - 1;
    else
      Current.Month := 12;
      Current.Year  := Current.Year - 1;
    end if;
  end loop;
if Due_Date_Vec.Length(Due_Dates) > 0 then
   declare
      Lower : Natural := Due_Date_Vec.First_Index(Due_Dates);
      Upper : Natural := Lower + Natural(Due_Date_Vec.Length(Due_Dates)) - 1;
   begin
      for I in reverse Lower .. Upper loop
         declare
            Current_Due_Date : Due_Date := Due_Dates(I);
         begin
            Insert_Auto_Income(Db, Current_Due_Date.Month, Current_Due_Date.Year);
         end;
      end loop;
   end;
end if;
end Insert_All_Due_Incomes;

type Setup is limited record
  Db : Database;
end record;

function Create_Setup(Db : Database) return Setup is
begin
  return (Db => <>);
end Create_Setup;

procedure Set_Up(S : Setup) is
  Income_Description : String := Util.Read_Config_Input(Text_Resources.Setup_Description, "pocket money");
  Income_Amount : String := Util.Read_Config_Input(Text_Resources.Setup_Income, "100");
  Overdraft : String := Util.Read_Config_Input(Text_Resources.Setup_Overdraft, "200");
  Now : Time := Clock;
  Year : Year_Number;
  Month : Month_Number;
  Day : Day_Number;
  Seconds : Day_Duration;
begin
  Insert_Configuration(S.Db, CONF_INCOME_DESCRIPTION, Income_Description);
  Insert_Configuration(S.Db, CONF_INCOME_AMOUNT, Income_Amount);
  Insert_Configuration(S.Db, CONF_OVERDRAFT, Overdraft);
  Split(Now, Year, Month, Day, Seconds);
  Insert_Auto_Income(S.Db, Integer(Month), Integer(Year));
end Set_Up;

procedure Initialize(S : out Setup) is
begin
  Util.Print(Text_Resources.Setup_Pre_Database);
  Connect(S.Db);
  Create_Tables(S.Db);
  Util.Print(Text_Resources.Setup_Post_Database);
  Set_Up(S);
  Util.Print_Ln(Text_Resources.Setup_Complete);
end Initialize;

procedure Setup_On_First_Run(S : out Setup) is
begin
  if not Exists(DB_FILE) then
    Initialize(S);
  end if;
end Setup_On_First_Run;

type Looop is limited record
  Db : Database;
end record;

KEY_ADD : constant Character := '+';
KEY_SUB : constant Character := '-';
KEY_SHOW : constant Character := '=';
KEY_HELP : constant Character := '?';
KEY_QUIT : constant Character := ':';

function Create_Looop(Db : Database) return Looop is
begin
  return (Db => <>);
end Create_Looop;

procedure Omg(L : Looop) is
begin
  Util.Print_Ln(Text_Resources.Error_Omg);
end Omg;

procedure Add_To_Ledger(L : Looop; Signum : Integer; SuccessMessage : String) is
  Description : String := To_String(Util.Input(Text_Resources.Enter_Description));
  Amount : Long_Float := Util.String_To_Long_Float(To_String(Util.Input(Text_Resources.Enter_Amount)));
begin
  if Amount > 0.0 then
    if Signum = 1 or Is_Expense_Acceptable(L.Db, Amount) then
      Insert_Into_Ledger(L.Db, Description, Amount * Long_Float(Signum));
      Util.Print_Ln(SuccessMessage);
      Util.Print(Text_Resources.Current_Balance(Balance(L.Db)));
    else
      Util.Print_Ln(Text_Resources.Error_Too_Expensive);
    end if;
  elsif amount < 0.0 then
    Util.Print_Ln(Text_Resources.Error_Negative_Amount);
  else
    Util.Print_Ln(Text_Resources.Error_Zero_Or_Invalid_Amount);
  end if;
end Add_To_Ledger;

procedure Handle_Add(L : Looop) is
begin
  Add_To_Ledger(L, 1, Text_Resources.Income_Booked);
end Handle_Add;

procedure Handle_Sub(L : Looop) is
begin
  Add_To_Ledger(L, -1, Text_Resources.Expense_Booked);
end Handle_Sub;

procedure Handle_Show(L : Looop) is
begin
  Util.print(Text_Resources.Formatted_Balance(Balance(L.Db), Transactions(L.Db)));
end Handle_Show;

procedure Handle_Info(L : Looop) is
begin
  Util.print(Text_Resources.Info);
end Handle_Info;

procedure Handle_Help(L : Looop) is
begin
  Util.print(Text_Resources.Help);
end Handle_Help;

procedure Loooop(L : out Looop) is
  Looping : Boolean := True;
  Unbounded_Input : Unbounded_String;
begin
  Connect(L.Db);
  Insert_All_Due_Incomes(L.Db);
  Util.Print(Text_Resources.Current_Balance(Balance(L.Db)));
  Handle_Info(L);
  while Looping loop
    Unbounded_Input := Util.Input(Text_Resources.Enter_Input);
    declare
      Inp : constant String := To_String(Unbounded_Input);
    begin
      if Inp'Length = 1 then
        case Inp(1) is
          when KEY_ADD  => Handle_Add(L);
          when KEY_SUB  => Handle_Sub(L);
          when KEY_SHOW => Handle_Show(L);
          when KEY_HELP => Handle_Help(L);
          when KEY_QUIT => Looping := False;
          when others   => Handle_Info(L);
        end case;
      elsif Inp'Length > 0 and then (Inp(1) = KEY_ADD or else Inp(1) = KEY_SUB) then
        Omg(L);
      else
        Handle_Info(L);
      end if;
    end;
  end loop;
  Disconnect(L.Db);
  Util.Print_Ln(Text_Resources.Bye);
end Loooop;

package body Text_Resources is

  function Banner return String is
  begin
    return ASCII.LF &
"<TAB> _                                 _   _" & ASCII.LF &
"<TAB>(_|   |_/o                        | | | |" & ASCII.LF &
"<TAB>  |   |      ,_  _|_         __,  | | | |  _ _|_" & ASCII.LF &
"<TAB>  |   |  |  /  |  |  |   |  /  |  |/  |/  |/  |" & ASCII.LF &
"<TAB>   \_/   |_/   |_/|_/ \_/|_/\_/|_/|__/|__/|__/|_/" & ASCII.LF &
"" & ASCII.LF &
"<TAB>Ada 2022 Edition" & ASCII.LF & ASCII.LF & ASCII.LF;
  end Banner;

  function Info return String is
  begin
    return ASCII.LF &
"<TAB>Commands:" & ASCII.LF &
"<TAB>- press plus (+) to add an irregular income" & ASCII.LF &
"<TAB>- press minus (-) to add an expense" & ASCII.LF &
"<TAB>- press equals (=) to show balance and last transactions" & ASCII.LF &
"<TAB>- press question mark (?) for even more info about this program" & ASCII.LF &
"<TAB>- press colon (:) to exit" & ASCII.LF & ASCII.LF;
  end Info;

  function Help return String is
  begin
    return ASCII.LF &
"<TAB>Virtuallet is a tool to act as your virtual wallet. Wow..." & ASCII.LF &
"<TAB>Virtuallet is accessible via terminal and uses a Sqlite database to store all its data." & ASCII.LF &
"<TAB>On first start Virtuallet will be configured and requires some input" & ASCII.LF &
"<TAB>but you already know that unless you are currently studying the source code." & ASCII.LF &
"" & ASCII.LF &
"<TAB>Virtuallet follows two important design principles:" & ASCII.LF &
"" & ASCII.LF &
"<TAB>- shit in shit out" & ASCII.LF &
"<TAB>- UTFSB (Use The F**king Sqlite Browser)" & ASCII.LF &
"" & ASCII.LF &
"<TAB>As a consequence everything in the database is considered valid." & ASCII.LF &
"<TAB>Program behaviour is unspecified for any database content being invalid. Ouch..." & ASCII.LF &
"" & ASCII.LF &
"<TAB>As its primary feature Virtuallet will auto-add the configured income on start up" & ASCII.LF &
"<TAB>for all days in the past since the last registered regular income." & ASCII.LF &
"<TAB>So if you have specified a monthly income and haven't run Virtuallet for three months" & ASCII.LF &
"<TAB>it will auto-create three regular incomes when you boot it the next time if you like it or not." & ASCII.LF &
"" & ASCII.LF &
"<TAB>Virtuallet will also allow you to add irregular incomes and expenses manually." & ASCII.LF &
"<TAB>It can also display the current balance and the 30 most recent transactions." & ASCII.LF &
"" & ASCII.LF &
"<TAB>The configured overdraft will be considered if an expense is registered." & ASCII.LF &
"<TAB>For instance if your overdraft equals the default value of 200" & ASCII.LF &
"<TAB>you won't be able to add an expense if the balance would be less than -200 afterwards." & ASCII.LF &
"" & ASCII.LF &
"<TAB>Virtuallet does not feature any fancy reports and you are indeed encouraged to use a Sqlite-Browser" & ASCII.LF &
"<TAB>to view and even edit the database. When making updates please remember the shit in shit out principle." & ASCII.LF &
"" & ASCII.LF &
"<TAB>As a free gift to you I have added a modified_at field in the ledger table. Feel free to make use of it." & ASCII.LF & ASCII.LF;
  end Help;

  function Setup_Pre_Database return String is
  begin
    return ASCII.LF &
"<TAB>Database file not found." & ASCII.LF &
"<TAB>Database will be initialized. This may take a while... NOT." & ASCII.LF;
  end Setup_Pre_Database;

  function Setup_Post_Database return String is
  begin
    return ASCII.LF &
"<TAB>Database initialized." & ASCII.LF &
"<TAB>Are you prepared for some configuration? If not I don't care. There is no way to exit, muhahahar." & ASCII.LF &
"<TAB>Press enter to accept the default or input something else. There is no validation" & ASCII.LF &
"<TAB>because I know you will not make a mistake. No second chances. If you f**k up," & ASCII.LF &
"<TAB>you will have to either delete the database file or edit it using a sqlite database browser." & ASCII.LF & ASCII.LF;
  end Setup_Post_Database;

  function Error_Zero_Or_Invalid_Amount return String is ("amount is zero or invalid -> action aborted");
  function Error_Negative_Amount return String is ("amount must be positive -> action aborted");
  function Income_Booked return String is ("income booked");
  function Expense_Booked return String is ("expense booked successfully");
  function Error_Too_Expensive return String is ("sorry, too expensive -> action aborted");
  function Error_Omg return String is ("OMFG RTFM YOU FOOL you are supposed to only enter + or - not anything else after that");
  function Enter_Input return String is ("input > ");
  function Enter_Description return String is ("description (optional) > ");
  function Enter_Amount return String is ("amount > ");
  function Setup_Complete return String is ("setup complete, have fun");
  function Bye return String is ("see ya");

  function Current_Balance(Balance : Long_Float) return String is
  begin
     return ASCII.LF & "<TAB>current balance: " & Util.Long_Float_To_String(Balance) & ASCII.LF & ASCII.LF;
  end Current_Balance;

  function Formatted_Balance(Balance : Long_Float; Formatted_Last_Transactions : String) return String is
  begin
     return "<TAB>" & Current_Balance(Balance) &
"<TAB>last transactions (up to 30)" & ASCII.LF &
"<TAB>----------------------------" & ASCII.LF &
Formatted_Last_Transactions & ASCII.LF;
  end Formatted_Balance;

  function Setup_Description return String is ("enter description for regular income");
  function Setup_Income return String is ("enter regular income");
  function Setup_Overdraft return String is ("enter overdraft");
  function Setup_Template(Description, Standard : String) return String is (Description & " [default: " & Standard & "] > ");

end Text_Resources;

  My_Database : Database := Create_Database;
  My_Setup : Setup := Create_Setup(My_Database);
  My_Looop : Looop := Create_Looop(My_Database);
begin
  Util.Print(Text_Resources.Banner);
  Setup_On_First_Run(My_Setup);
  Loooop(My_Looop);
end Virtuallet;
