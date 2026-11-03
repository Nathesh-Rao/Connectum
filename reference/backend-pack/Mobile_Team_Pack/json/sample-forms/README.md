# Sample forms: one per feature

For building and testing the mobile form logic. Twelve small forms (and four more that need an API: see the end), each showing one feature, plus the numbers to expect. They are known to work: `connectum-backend/test/connectum_sample_forms_test.mjs` loads them into an organisation and sends the records of `cases.json`, and `tests/frontend/sampleForms.test.mjs` runs the shared form logic over the same cases.

## Load them (an administrator, a TEST organisation)

You need an **administrator's session token** for the test organisation: sign in with the account calls of the Postman collection (folder 2, then folder 3 to enter the organisation) as the organisation's administrator; the reply of entering the organisation carries the `token`. The administrator is the person who can open the Admin console.

```
node tools/sample-forms/load.mjs --base http://HOST:PORT --user ADMIN_NAME --token ADMIN_SESSION_TOKEN
```

It saves each form (`admin.tstruct.save`), makes an option for it (`<name>_option`, so people can open and fill it), and adds three colours to `sample_colour`. Running it again saves the forms over themselves and adds no records twice. Needs Node 22 or newer. If you would rather build them in the form studio, each `.json` file is exactly what the studio saves (open the form in Admin console, Forms): `FORM_FIELD_TYPES.md` explains every setting, and `FIELD_RULES.md`, `FIELD_DEFAULTS.md`, `FETCH_RULES.md` the builder screens.

## The forms

| Form | Feature | Try |
|---|---|---|
| `sample_calc` | **calc**: `total` = `qty*price`; `group` is a drop down worked out by `IIF(age>18,"Adult","Minor")`; `stamp` is a hidden number worked out by `qty*1000+age` | Quantity 3, price 2.5, age 20: total 7.5, group Adult, stamp 3020. Age 18 is Minor. Leave the age empty: the group and the stamp stay empty. |
| `sample_rule` | **rule**: phone `Length(phone)=10`, age `age>=18`, email `CheckEmail(email)`, finish date `Val(finish)>=Val(start)` | Phone `123`: "The phone must have 10 digits". An empty field is not checked. The finish may equal the start. |
| `sample_condition` | **condition** and a switch: the car number only when "Do you have a car?" is Yes; "Please say why" when the kind is Other **or** Sick | Say No: no car number asked. Say Yes: it is required. |
| `sample_cascade` | **cascading drop down** (`dependsOn`): the person list narrows to the chosen department | Choose a department: only its people. Needs people in the organisation. |
| `sample_colour` | a small list of colours (Red R-01, Green G-02, Blue B-03) | read by the next two forms |
| `sample_fetch` | **fetch**: the colour code is fetched from `sample_colour` for the colour chosen | Choose Red: the code R-01 appears. |
| `sample_selection` | **selection** (one, and several) from the colour records, and a **fill** (`pickCode`) from the chosen colour | Pick Green: the code G-02 fills in. |
| `sample_toggle` | **toggle**: "I agree" (required), "newsletter" defaulting to No | Saved as the text Yes or No. |
| `sample_file` | **file**: one photo (required) and up to ten documents | Upload first (`POST /api/sd/files`), then send the ids. |
| `sample_grid` | **grid with a total**: item, quantity, rate, a line total per row, and a grand total outside the grid | 2 x 10 and 5 x 1.5: line totals 20 and 7.5, grand total 27.5. |
| `sample_dates` | **date and time**: a date with limits, today filled in, a time, and a date a week later (`AddToDate(joined,7)`) | 2026-12-28 gives 2027-01-04. |
| `sample_types` | one field of **every basic kind** (text, email, url, mobile, numbers, date, time, location, barcode, payment, Auto Generate) | See what each is saved as in `FORM_FIELD_TYPES.md`. |

## The expected numbers: `cases.json`

For each form, `cases.json` has up to three kinds of case:

- `calc`: values in, what the form logic works out (`expect`; `absent` for a value that must stay empty; `rows` for the cells of a grid's rows). Run your engine over these.
- `rules`: a field and the values, and the message a person sees (`null`: the rule is met).
- `server`: a record sent to `tstruct.submit`, and either what is saved (`stored`) or the messages of `error.details.fields`. These are the server's own words.

The `note` on a case explains a surprise (the server saves a total it was sent, and never runs a rule). **The server does not run calculations or rules**; only the app does (`FORM_LOGIC_FOR_MOBILE.md`, section 6).

## The samples that need an API: `needs-setup/`

A drop down fed by a list API and a value fetched from a Get API need an API behind them. Four more files in `needs-setup/`: two API definitions (`api_sample_list.json`, `api_sample_person.json`) and two forms (`sample_api_choice.json`, `sample_api_fetch.json`). `{{API_BASE}}` in the definitions is the address of the service. To try them without a service of your own:

```
node tools/sample-forms/stand-in-api.mjs 8765                     # a tiny service: /list and /person (answers { status: "ok", rows | data })
node tools/sample-forms/load.mjs --base http://HOST:PORT --user ADMIN --token TOKEN --api-base http://127.0.0.1:8765
```

The Connectum server has to be able to reach the service, and the shared servers refuse private addresses unless `CONNECTUM_API_ALLOW_PRIVATE=1`: **this works against a server on your own machine, not against the shared test server.** There, give `--api-base` the address of a service the server can reach.

What the server answers (checked by `connectum_sample_forms_test.mjs`): `form.options` for `sample_api_choice` / `pick` gives the three rows with `cacheSec: 120` (the API's own) and an `etag`; for `sample_api_fetch` / `employeeName` with `values:{code:"E1"}` it gives one row `{value:"Asha Rao", record:{Employee_Name:"Asha Rao", city:"Pune"}}`, and the app fills `city` from the same record; with `code` empty it answers `waiting: true`, with `code` `NONE` no row. The server saves what it is sent (a typed name is never overruled) and refuses a choice the list does not offer.

## Not covered

A choice from an **Axpert data source** or an **Axpert form** needs an Axpert connection in the organisation, so there is no sample for it; the replies have the same shape as the API ones (`form.options`), and `FORM_LOGIC_FOR_MOBILE.md` section 7 applies.
