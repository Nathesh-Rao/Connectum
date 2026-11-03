# Field types and the value each one is saved as

Written 2 November 2026 from the server code (`connectum-backend/src/forms/sd_config_values.erl`, `check_type`) and checked by `connectum-backend/test/connectum_sample_forms_test.mjs` against `docs/sample-forms/cases.json` (form `sample_types` has one field of every basic kind). A record is sent with `tstruct.submit {name, values:{field: value}}`; a refused value comes back as `invalid_values` with `error.details.fields` (`{field: message}`; a cell of a grid is `section.row.field`, rows from 0). The server never runs a field's `rule` or `calc` (see `FORM_LOGIC_FOR_MOBILE.md`).

**Send plain JSON values: text as text, numbers as digits and a point (no thousands commas), dates as `yyyy-mm-dd`, times as `HH:MM`.** The parser the app runs works with dates as `dd/mm/yyyy`; the form logic converts at the edge, so what you send and what is saved is always `yyyy-mm-dd`.

## Every type

| Type | The person | Send | Saved as | Refused with |
|---|---|---|---|---|
| `text` | Short or large text | text, at most 5000 characters | the text as sent | "Too long (max 5000 characters)." |
| `email` | Email | text | trimmed, lower case | "Enter a valid email address." |
| `url` | Web address | text starting `http://` or `https://`, no spaces | as sent | "Enter a valid http(s) URL." |
| `mobile` | Mobile number | text; spaces and dashes are taken out | digits (with the `+` kept): `98765 43210` becomes `9876543210`, `+91 98765 43210` becomes `+919876543210`. With `withCountryCode` the `+` is required | "Enter a valid mobile number." / "Include the country code, e.g. +91..." |
| `wholenumber` | Whole number | a number or text of digits | a JSON integer (`"42"` becomes `42`, `7.0` becomes `7`) | "Enter a whole number." / "Must be at least N." / "Must be at most N." (`min`, `max`) |
| `number` | Decimal number | a number or text such as `"12.50"` | a JSON number (`12.5`) | "Enter a number." (`"1,250.50"` is refused) / the same limits |
| `date` | Date | text `yyyy-mm-dd` | as sent | "Use the format YYYY-MM-DD." / "That date doesn't exist." / "Must be on or after yyyy-mm-dd" (`min`, `max` the same way) |
| `time` | Time | text `HH:MM` (24 hour), seconds `HH:MM:SS` allowed | as sent | "Use the format HH:MM." |
| `slot` | A booking time | text `yyyy-mm-dd HH:MM` | as sent | "Choose a time from the list." (the form names the person or thing booked with `of`) |
| `location` | A place | an object `{lat, lng, address?}` or the text `"lat,lng"` | an object `{lat, lng}` plus `address` when there is one | "Enter coordinates as {lat,lng}." (latitude -90 to 90, longitude -180 to 180; the address must be text) |
| `barcode` | A scanned barcode or QR | text | as sent | "Too long (max 5000 characters)." |
| `payment` | A payment | an object `{amount, method?, status?}`: `amount` a number or digits (not negative), `method` one of the form's `methods` (default Cash, Card, UPI; any capitals), `status` `paid` or `pending` (default `pending`) | `{amount, method, status, currency?}` with the method in the form's own spelling and the form's `currency` added | "Enter the amount." / "The amount cannot be negative." / "Choose paid or pay later." / "Choose how it was paid." / "Choose a payment method from the list." |
| `file` | An attachment | the id of a file already uploaded (`POST /api/sd/files?name=...`, the reply's `file.id`), or a list of ids when the field takes several | the list of ids (one id for a single file) | "Attach a file." / "Attach at most 1 file." (at most 10 when `multi`) / "That file is no longer there. Attach it again." |
| `toggle` | A switch | `true`, `false`, or text: `yes`, `no`, `y`, `n`, `t`, `f`, `true`, `false`, `on`, `off` (any capitals, spaces round it) | the text **`Yes`** or **`No`** | "Choose Yes or No." |
| `list` | A drop down | fixed options: one of the options exactly; fed from the organisation's data (`source`): one of its names (any capitals) | the option (a list kept in the form's own spelling), or the **list's own spelling** | "Choose one of the listed options." / "Choose one from the organisation's list." |
| `list` with `multi` | Several of a drop down | a list of options; with `allowAll` and a data source, the text `"All"` | the list (duplicates removed for a data source) | "Choose only from the listed options." / "Choose only from the organisation's list." |
| `selection` | A drop down fed from another form, a data source or an API | one text, at most 500 characters; with `multi`, a list of at most 50 (each up to 500), a lone text counts as a list of one | the text, or the de-duplicated list | "Too long." / "Choose from the listed options." / "Choose at most 50 items." / "That is not one of the choices on offer." (a choice from a query source is matched against what the source offers) |
| `fill` | A field filled from the choice in another field (`fillFrom`, `sourceProp`) | text, at most 500 characters | as sent | "Too long." |
| `autogenerate` | A number the system makes (`prefix`, `suffix`, `digits`, `start`, `resetEvery`) | **do not send it** | text such as `INV-0017`, made when the record is saved, one more each time | (never refused) |

`selection` is what the builder used to call "Select from API" (there is one Drop Down in the builder now). A form cannot be saved with a type that is not in this table.

## Settings every field can have

| Setting | Meaning |
|---|---|
| `required` | The field must have a value (when it is shown). "This field is required." |
| `hidden` | Not shown. An ordinary hidden field's value is ignored; one whose value is made for the person (`calc`, `fetch`, `fill`, `autogenerate`) is still taken, checked and saved. |
| `readOnly` | The person cannot change it. A new record gets the field's fixed `default` whatever was sent (a read-only field with no fixed default keeps the value the form put there: today, the time now, the place); an edit keeps what the record had. |
| `default`, `defaultNow` | A value the form starts with; `defaultNow` (date, time, location) starts with now or here. |
| `min`, `max` | Limits for number, whole number, date and time. |
| `rule` `{expr, message}` | A check in the expression language, **run by the app only**. |
| `calc` `{expr}` | An auto value, **worked out by the app only** (text, whole number, number, date and list fields). |
| `fetch` `{type, ...}` | One value fetched from another form or a Get API (**the app asks**; the server keeps what it is sent). |
| `condition` | Show the field only when: `{field, op, value}` with `op` one of `eq`, `ne`, `gt`, `lt`, `gte`, `lte`, `in`, `between`, `notempty`, or `{all:[...]}` / `{any:[...]}`. Numbers compare as numbers, everything else as text. A field that is not shown is not checked and not saved. A section can have a condition too. |
| `section` | The section the field belongs to; a section with `grid: true` holds rows, each row has the section's fields (at most 200 rows; an empty row is left out). |
| `multi` | Several values (a list, a selection, a file). |
| `dependsOn` | A cascading list: `{field, prop}`, keep those whose profile `prop` (`department`, `branch`, `designation`, `city`) matches the value of that field. |

## What is not done by the server

The server does not work out `calc`, does not run `rule`, does not fetch for `fetch` or `fill`, and does not apply `dependsOn` to what is saved (a person from another department is still checked only against the organisation's list). The app does these before it sends. See `FORM_LOGIC_FOR_MOBILE.md`, section 6.
