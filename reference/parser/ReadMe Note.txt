## AxExpReactParser.jsx Usage Guide

This release provides the formula parser module only. It does not include a form, UI, or field data. Add `AxExpReactParser.jsx` to your
application's source folder, then import its functions using the relative path for your project:

```jsx
import {
  RegisterVariable,
  GetValue,
  Evaluate,
  dateFormat,
  SetDateFormat
} from './AxExpReactParser.jsx';
```
Above 5 functions have been published in Parser which can be called from React pages as explained below.  

1. "RegisterVariable" function: This function can be register 1 or n number of variables to the parser, the format of the registering
 variables as follows.  

Data format, Each array entry describes one variable on one row:

- `n`: variable name
- `v`: its value
- `rno`: row number


 Ex.:
let _reactFieldArray = [
  { n: 'quantity', v: '2', rno: '1' },
  { n: 'unitPrice', v: '10', rno: '1' },
  { n: 'invoiceDate', v: '03/04/2026', rno: '1' },
  { n: 'quantity', v: '3', rno: '2' },
  { n: 'unitPrice', v: '5', rno: '2' }
];
reactFieldArray = RegisterVariable(reactFieldArray,_reactFieldArray);

Note: 1. Add a variable or update its value for the same name and row. This function returns a new array, so use the returned array.
 Names are case-insensitive and stored trimmed and lowercase; for example, `QUANTITY` and `quantity` refer to the same variable on the same row.
      2. Your application creates and updates the field data, then passes it to the parser. The examples below use `reactFieldArray` for 
that data array; you can use a different variable name if you prefer.
      3. For Variables from a table, use row numbers starting at `1` and incrementing for each row (`1`, `2`, ...). For fields that are not 
from a table, and for variables, use `1` as the default `rno`.


2. "GetValue" function: This fucntion used to get variable value from the parser. 
Ex.: const quantity = GetValue(reactFieldArray, 'QUANTITY', '1'); // '2'

Note: Read a variable by name and row. The name lookup is case-insensitive. The function returns `undefined` when no matching name and 
row are found.

3. "Evaluate" function: Call Evaluate with the formula text, the destination field name, the row number to calculate,
 and a context object containing reactFieldArray. The destination name (such as `lineTotal`, `status`, or `lastDay`) identifies
  the field being calculated. Evaluate returns the result but does not save it; use `RegisterVariable` to add or update that 
  destination field in the array. Date formulas use the parser-wide format unless the context includes a `dateFormat` override.

 Ex's.: Below 3 steps a,b and c shows how to register the value, evaluate the expression and get the value back to the react page.
 a. reactFieldArray = RegisterVariable(reactFieldArray, {
  n: 'lineTotal',
  v: 200,
  rno: 1
});

 b. const lineTotal = Evaluate(
  'quantity * unitPrice',
  'lineTotal',
  1,
  { reactFieldArray }
); 

c. After Evaluate function, GetValue function can be used to evaluated variables to registered as shown in the example below.
ex.: const savedLineTotal = GetValue(reactFieldArray, 'lineTotal', rowNo); // '20'


Below points are the additional examples for evaluate function for your reference.


reactFieldArray = RegisterVariable(reactFieldArray, {
  n: 'status',
  v: true,
  rno: 1
});

const status = Evaluate(
  'IIF(quantity>0,{available},{empty})',
  true,
  1,
  { reactFieldArray }
);

----------

reactFieldArray = RegisterVariable(reactFieldArray, {
  n: 'lastDay',
  v: 31,
  rno: 1
});

const lastDay = Evaluate(
  'LastDayOfMonth(invoiceDate)',
  31,
  1,
  { reactFieldArray }
); // '30/04/2026' with the default format

-----------

reactFieldArray = RegisterVariable(reactFieldArray, {
  n: 'totalQuantity',
  v: 100,
  rno: 1
});

const totalQuantity = Evaluate('Total(quantity)', 'totalQuantity', rowNo, { reactFieldArray }); // 5
reactFieldArray = RegisterVariable(reactFieldArray, {
  n: 'totalQuantity',
  v: 100,
  rno: 1
});


4. "SetDateFormat" function: The parser-wide `dateFormat` defaults to `dd/mm/yyyy`. Call `SetDateFormat` before evaluating date
 formulas to change the format. Supported formats are `dd/mm/yyyy` and `mm/dd/yyyy`. The exported `dateFormat` value reflects the 
 current setting.

Ex.: a. SetDateFormat('dd/mm/yyyy');
const dayFirst = Evaluate('LastDayOfMonth(invoiceDate)', 'lastDay', '1', {
  reactFieldArray
}); // '30/04/2026'

b. SetDateFormat('mm/dd/yyyy');
const monthFirst = Evaluate('LastDayOfMonth(invoiceDate)', 'lastDay', '1', {
  reactFieldArray
}); // '03/31/2026'
Note: `invoiceDate` set to `03/04/2026`, the same formula gives different results depending on the configured format:

