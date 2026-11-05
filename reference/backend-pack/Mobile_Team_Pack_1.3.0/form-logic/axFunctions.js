// The catalog of everything a field rule can use: the operators and the functions of the Axpert expression language (axExpParser.js), each with what it does and a worked
// example. Shown in the Tstruct Builder ("Rule functions"). Every example is run against AX_SAMPLE by the tests, so what is written here is what the parser answers.
//   e: the example   r: what it gives (as text)   a: other names that do the same   n: a short note when something is easy to get wrong
export const AX_SAMPLE = {
  fields: { name: '  Asha Rao ', phone: '9876543210', email: 'asha@example.com', city: 'Pune', code: 'AB-12', note: '', age: 17, qty: 3, price: 250, amount: 1234567.5, joined: '2026-04-03', ends: '2026-04-30' },
  rows: { lineitem: ['Bolt', 'Nut', 'Bolt'], lineqty: [2, 3, 1], linerate: [10, 5, 40] },
};

export const AX_INTRO = [
  ['Write what must be true', 'A rule is a question about the field: the value is accepted when the answer is yes. Length(phone)=10 accepts a phone with ten characters.'],
  ['Use your fields by their id', 'Type a field\'s id as it is in the builder (capitals do not matter): age>=18, qty*price<=5000. A rule on one field can look at the others.'],
  ['Text, numbers and dates', 'Put text in double quotes: city="Pune". Dates are written day/month/year: "03/04/2026".'],
  ['Empty fields are not checked', 'A field left empty passes its rule; use Required to insist on a value. When another field is empty, a rule reads it as 0.'],
  ['Grid rows', 'Name the field in quotes for the row functions: GetRowCount("lineqty"). Total(lineqty) works either way. In a grid cell a rule sees its own row.'],
  ['The message', 'What you type under the rule is what people see when it fails. Without one they see "<field> is not valid".'],
];

export const AX_OPERATORS = [
  { s: '+  -  *  /', d: 'Add, subtract, multiply, divide.', e: 'qty*price', r: '750' },
  { s: '%', d: 'The remainder after dividing.', e: 'qty%2', r: '1' },
  { s: '^', d: 'Raise to a power.', e: '2^3', r: '8' },
  { s: '=  ==', d: 'Is equal to (text is compared as written).', e: 'city="Pune"', r: 'true' },
  { s: '!=', d: 'Is not equal to. (<> is not understood; use !=.)', e: 'city!="Goa"', r: 'true' },
  { s: '<  <=  >  >=', d: 'Smaller, at most, larger, at least.', e: 'age>=18', r: 'false' },
  { s: '&&', d: 'Both must be true.', e: 'age>=18 && qty>0', r: 'false' },
  { s: '||', d: 'Either may be true.', e: 'age>=18 || qty>0', r: 'true' },
  { s: '( )', d: 'Group parts so they are worked out first.', e: '(qty+1)*price', r: '1000' },
];

export const AX_CATEGORIES = ['Checks', 'Text', 'Numbers', 'Dates', 'Rows and totals', 'Money and formats', 'Advanced'];

export const AX_FUNCTIONS = [
  // ---- Checks
  { c: 'Checks', f: 'IIF', sig: 'IIF(test, ifTrue, ifFalse)', d: 'Gives the second value when the test is true, otherwise the third.', e: 'IIF(age>=18,"Adult","Minor")', r: 'Minor' },
  { c: 'Checks', f: 'IsEmpty', a: ['IsEmptyValue', 'IsVarEmpty'], sig: 'IsEmpty(value)', d: 'T when the value is empty, F when it has something in it.', e: 'IsEmpty(Trim("  "))', r: 'T', n: 'It answers T or F (text). A field left empty reads as 0, so to test a field write note=0.' },
  { c: 'Checks', f: 'CheckEmail', sig: 'CheckEmail(value)', d: 'True when the value looks like an email address.', e: 'CheckEmail(email)', r: 'true' },
  { c: 'Checks', f: 'ChkUniqChar', sig: 'ChkUniqChar(text)', d: 'True when some character appears more than once in the text.', e: 'ChkUniqChar("AABC")', r: 'true' },
  { c: 'Checks', f: 'IsOperator', sig: 'IsOperator(character)', d: 'True when the character is an operator such as + - * / ^ = < >.', e: 'IsOperator("+")', r: 'true' },
  // ---- Text
  { c: 'Text', f: 'Length', a: ['GetLength'], sig: 'Length(text)', d: 'How many characters the text has.', e: 'Length(phone)', r: '10' },
  { c: 'Text', f: 'SubStr', sig: 'SubStr(text, start, count)', d: 'Part of the text, from the start position (the first character is 1). Leave out the count to take the rest.', e: 'SubStr(phone,1,2)', r: '98' },
  { c: 'Text', f: 'Upper', a: ['UpperCase'], sig: 'Upper(text)', d: 'The text in capitals.', e: 'Upper(city)', r: 'PUNE' },
  { c: 'Text', f: 'Lower', a: ['LowerCase'], sig: 'Lower(text)', d: 'The text in small letters.', e: 'Lower(city)', r: 'pune' },
  { c: 'Text', f: 'Trim', a: ['TrimAll'], sig: 'Trim(text)', d: 'The text without spaces at the start and the end.', e: 'Length(Trim(name))', r: '8' },
  { c: 'Text', f: 'TrimInBetwnSpaces', sig: 'TrimInBetwnSpaces(text)', d: 'The text with every space taken out.', e: 'TrimInBetwnSpaces(name)', r: 'AshaRao' },
  { c: 'Text', f: 'Str', a: ['GetVarValue'], sig: 'Str(value)', d: 'The value as text.', e: 'Str(qty)', r: '3' },
  { c: 'Text', f: 'Val', sig: 'Val(text)', d: 'The number in the text (commas are ignored). 0 when there is none.', e: 'Val("1,250.50")', r: '1250.5' },
  { c: 'Text', f: 'ExtractNum', sig: 'ExtractNum(text)', d: 'Only the digits of the text.', e: 'ExtractNum(code)', r: '12' },
  { c: 'Text', f: 'RemoveCommas', sig: 'RemoveCommas(text)', d: 'The text without commas.', e: 'RemoveCommas("1,250")', r: '1250' },
  { c: 'Text', f: 'FindCharPos', sig: 'FindCharPos(text, find)', d: 'Where the first match starts, counting from 0; -1 when it is not there.', e: 'FindCharPos(email,"@")', r: '4' },
  { c: 'Text', f: 'FindAndReplace', sig: 'FindAndReplace(text, find, replacement)', d: 'Every match replaced (capitals do not matter).', e: 'FindAndReplace(code,"-","/")', r: 'AB/12' },
  { c: 'Text', f: 'GetNthString', sig: 'GetNthString(text, position)', d: 'The text from that position on, counting from 0.', e: 'GetNthString(code,3)', r: '12' },
  { c: 'Text', f: 'GetSeperatorCount', sig: 'GetSeperatorCount(text, separator)', d: 'How many times the separator appears.', e: 'GetSeperatorCount("a,b,c",",")', r: '2' },
  { c: 'Text', f: 'LeftPad', sig: 'LeftPad(text, length, character)', d: 'Fills the left with the character until the text is that long (0 when none is given).', e: 'LeftPad("7",3,"0")', r: '007' },
  { c: 'Text', f: 'RightPad', sig: 'RightPad(text, length, character)', d: 'Fills the right with the character until the text is that long.', e: 'RightPad("7",3,"0")', r: '700' },
  { c: 'Text', f: 'Pad', sig: 'Pad(text, length, character)', d: 'Fills both sides in turn until the text is that long.', e: 'Pad("7",4,"*")', r: '**7*' },
  { c: 'Text', f: 'Stuff', sig: 'Stuff(text, insert, position)', d: 'Puts the insert into the text at the position.', e: 'Stuff("ABCD","-",2)', r: 'AB-CD' },
  { c: 'Text', f: 'StringPos', sig: 'StringPos(item, list, separator)', d: 'Where the item is in the list of values (from 0; -1 when it is not). The separator is a comma unless you give another.', e: 'StringPos("Pune","Goa,Pune,Delhi")', r: '1' },
  // ---- Numbers
  { c: 'Numbers', f: 'Abs', sig: 'Abs(number)', d: 'The number without its minus sign.', e: 'Abs(0-5)', r: '5' },
  { c: 'Numbers', f: 'Ceil', a: ['AxpCeil'], sig: 'Ceil(number)', d: 'Rounded up to a whole number.', e: 'Ceil(2.1)', r: '3' },
  { c: 'Numbers', f: 'Floor', a: ['AxpFloor'], sig: 'Floor(number)', d: 'Rounded down to a whole number.', e: 'Floor(2.9)', r: '2' },
  { c: 'Numbers', f: 'Round', sig: 'Round(number)', d: 'Rounded to the nearest whole number.', e: 'Round(2.5)', r: '3' },
  { c: 'Numbers', f: 'RoundOff', sig: 'RoundOff(number, places)', d: 'Rounded to that many decimal places.', e: 'RoundOff(3.14159,2)', r: '3.14' },
  { c: 'Numbers', f: 'FormatVal', sig: 'FormatVal(number, places)', d: 'The number with that many decimal places (2 when none is given).', e: 'FormatVal(2.5,2)', r: '2.5' },
  { c: 'Numbers', f: 'Rnd', sig: 'Rnd(number, step)', d: 'Rounded to the nearest step, the step given in hundredths: a step of 5 rounds to the nearest 0.05.', e: 'Rnd(12.34,5)', r: '12.35' },
  { c: 'Numbers', f: 'EvaluatePower', sig: 'EvaluatePower(number, power)', d: 'The number raised to the power.', e: 'EvaluatePower(2,10)', r: '1024' },
  { c: 'Numbers', f: 'GetInteger', sig: 'GetInteger(text)', d: 'The whole number at the start of the text. 0 when there is none.', e: 'GetInteger("42 items")', r: '42' },
  { c: 'Numbers', f: 'Mods', a: ['GetMod'], sig: 'Mods(number, divisor)', d: 'The remainder after dividing (0 when the divisor is 0).', e: 'Mods(17,5)', r: '2' },
  // ---- Dates
  { c: 'Dates', f: 'Date', sig: 'Date()', d: 'Today, where the person is (not the UTC date).', e: 'Length(Date())', r: '10' },
  { c: 'Dates', f: 'Time', sig: 'Time()', d: 'The time now, hours:minutes:seconds.', e: 'Length(Time())', r: '8' },
  { c: 'Dates', f: 'MakeDate', sig: 'MakeDate(day, month, year)', d: 'A date from its three parts.', e: 'MakeDate(3,4,2026)', r: '03/04/2026' },
  { c: 'Dates', f: 'ValidEncodeDate', sig: 'ValidEncodeDate(year, month, day)', d: 'A date from its three parts, year first.', e: 'ValidEncodeDate(2026,4,3)', r: '03/04/2026' },
  { c: 'Dates', f: 'DayOfDate', sig: 'DayOfDate(date)', d: 'The day of the month.', e: 'DayOfDate(joined)', r: '3' },
  { c: 'Dates', f: 'MonthOfDate', sig: 'MonthOfDate(date)', d: 'The month number (January is 1).', e: 'MonthOfDate(joined)', r: '4' },
  { c: 'Dates', f: 'YearOfDate', sig: 'YearOfDate(date)', d: 'The year.', e: 'YearOfDate(joined)', r: '2026' },
  { c: 'Dates', f: 'CMonthYear', sig: 'CMonthYear(date)', d: 'The month name and year.', e: 'CMonthYear(joined)', r: 'April 2026' },
  { c: 'Dates', f: 'Mandy', sig: 'Mandy(date)', d: 'The year and month together, as yyyymm.', e: 'Mandy(joined)', r: '202604' },
  { c: 'Dates', f: 'LastDayOfMonth', sig: 'LastDayOfMonth(date)', d: 'The last day of that date\'s month.', e: 'LastDayOfMonth(joined)', r: '30/04/2026' },
  { c: 'Dates', f: 'DaysInMonth', sig: 'DaysInMonth(date)  or  DaysInMonth(year, month)', d: 'How many days that month has.', e: 'DaysInMonth(2026,2)', r: '28' },
  { c: 'Dates', f: 'AddToDate', sig: 'AddToDate(date, days)', d: 'The date that many days later (a negative number goes back).', e: 'AddToDate(joined,10)', r: '13/04/2026' },
  { c: 'Dates', f: 'AddToMonth', sig: 'AddToMonth(date, months)', d: 'The date that many months later (the day is kept, or the last day of a shorter month).', e: 'AddToMonth(joined,1)', r: '03/05/2026' },
  { c: 'Dates', f: 'DaysElapsed', a: ['DateDiff'], sig: 'DaysElapsed(from, to)', d: 'How many days between two dates (never negative).', e: 'DaysElapsed(joined,ends)', r: '27' },
  { c: 'Dates', f: 'TimeElapsed', sig: 'TimeElapsed(from, to)', d: 'The gap between two dates in days, hours, minutes and seconds.', e: 'TimeElapsed(joined,ends)', r: '27 days, 0 hours, 0 minutes, 0 seconds' },
  { c: 'Dates', f: 'NetworkDays', sig: 'NetworkDays(from, to, holidays)', d: 'Working days (Monday to Friday) from one date to another, both included, less the number of holidays you give. -1 when "from" is after "to".', e: 'NetworkDays(joined,ends)', r: '20' },
  { c: 'Dates', f: 'Days360', sig: 'Days360(from, to, method)', d: 'Days between two dates on a 30-day-month year (the way banks count). Method true is the US way.', e: 'Days360(joined,ends)', r: '27' },
  { c: 'Dates', f: 'DToC', a: ['CToD'], sig: 'DToC(date)', d: 'The date written in the form\'s date format.', e: 'DToC(joined)', r: '03/04/2026' },
  // ---- Rows and totals
  { c: 'Rows and totals', f: 'Total', sig: 'Total(field)', d: 'The sum of a field over all the rows of a grid.', e: 'Total(lineqty)', r: '6', n: 'Use it on an ordinary field. Inside a grid cell a rule sees its own row.' },
  { c: 'Rows and totals', f: 'GetRowCount', sig: 'GetRowCount(field)', d: 'How many rows have a value in that field.', e: 'GetRowCount("lineqty")', r: '3' },
  { c: 'Rows and totals', f: 'GetValue', sig: 'GetValue(field, row)', d: 'The value of a field in a given row (the first row is 1).', e: 'GetValue("lineitem",2)', r: 'Nut' },
  { c: 'Rows and totals', f: 'GetMin', sig: 'GetMin(field)', d: 'The row number that holds the smallest value.', e: 'GetMin("lineqty")', r: '3' },
  { c: 'Rows and totals', f: 'GetMax', sig: 'GetMax(field)', d: 'The row number that holds the largest value.', e: 'GetMax("lineqty")', r: '2' },
  { c: 'Rows and totals', f: 'GetRow', sig: 'GetRow(field, value)', d: 'The first row where the field has that value; -1 when none does.', e: 'GetRow("lineitem","Nut")', r: '2' },
  { c: 'Rows and totals', f: 'Sum', sig: 'Sum(field, value, sumField)', d: 'Adds up one field over the rows where another field has a given value.', e: 'Sum("lineitem","Bolt","lineqty")', r: '3' },
  { c: 'Rows and totals', f: 'SumTill', sig: 'SumTill(field, value, sumField, lastRow)', d: 'The same as Sum, counting only up to a row.', e: 'SumTill("lineitem","Bolt","lineqty",1)', r: '2' },
  { c: 'Rows and totals', f: 'GetAllValues', sig: 'GetAllValues(field)', d: 'Every value of the field over the rows, one after another, with commas.', e: 'GetAllValues("lineitem")', r: 'Bolt,Nut,Bolt' },
  // ---- Money and formats
  { c: 'Money and formats', f: 'InsertCommas', sig: 'InsertCommas(number)', d: 'The number with two decimals and thousands separators (lakh style: 12,34,567.50).', e: 'InsertCommas(amount)', r: '12,34,567.50' },
  { c: 'Money and formats', f: 'FormatAmount', sig: 'FormatAmount(number, places, group)', d: 'The number with that many decimals; true as the third value adds thousands separators.', e: 'FormatAmount(amount,2,"T")', r: '12,34,567.50' },
  { c: 'Money and formats', f: 'FormatAccAmount', sig: 'FormatAccAmount(number, places, group)', d: 'The same in accounting style; add more values to show negatives in brackets or with a currency.', e: 'FormatAccAmount(1250,2,"T")', r: '1,250.00' },
  { c: 'Money and formats', f: 'AmtWord', sig: 'AmtWord(number)', d: 'An amount in words, in rupees.', e: 'AmtWord(1250)', r: 'Rupees One Thousand Two Hundred Fifty Only' },
  { c: 'Money and formats', f: 'CurrAmtWord', sig: 'CurrAmtWord(number, currency, subunit)', d: 'An amount in words with the currency and subunit names you give.', e: 'CurrAmtWord("12.50","Dollars ","cents")', r: 'Dollars Twelve and cents Fifty only' },
  // ---- Advanced
  { c: 'Advanced', f: 'Encode', sig: 'Encode(text)', d: 'The text encoded as base64.', e: 'Encode("hi")', r: 'aGk=' },
  { c: 'Advanced', f: 'Decode', sig: 'Decode(text)', d: 'Base64 text turned back into text.', e: 'Decode("aGk=")', r: 'hi' },
  { c: 'Advanced', f: 'ConvertMD5', sig: 'ConvertMD5(text)', d: 'The MD5 fingerprint of the text.', e: 'ConvertMD5("a")', r: '0cc175b9c0f1b6a831c399e269772661' },
  { c: 'Advanced', f: 'InfixToPostfix', sig: 'InfixToPostfix(expression)', d: 'An everyday expression written in postfix order.', e: 'InfixToPostfix("1+2*3")', r: '1 2 3 * +' },
  { c: 'Advanced', f: 'PostfixToInfix', sig: 'PostfixToInfix(expression)', d: 'A postfix expression written the everyday way.', e: 'PostfixToInfix("1 2 +")', r: '(1+2)' },
  { c: 'Advanced', f: 'PostfixEval', sig: 'PostfixEval(expression)', d: 'Works out a postfix expression.', e: 'PostfixEval("1 2 3 * +")', r: '7' },
  { c: 'Advanced', f: 'InputPrecedence', sig: 'InputPrecedence(operator)', d: 'The precedence of an operator when it is read.', e: 'InputPrecedence("*")', r: '7' },
  { c: 'Advanced', f: 'StackPrecedence', sig: 'StackPrecedence(operator)', d: 'The precedence of an operator already waiting.', e: 'StackPrecedence("*")', r: '8' },
  { c: 'Advanced', f: 'RegVar', sig: 'RegVar(name, type, value)', d: 'Keeps a named value for the rest of the session. It gives nothing back.', e: 'RegVar("x","n",5)', r: '' },
];
