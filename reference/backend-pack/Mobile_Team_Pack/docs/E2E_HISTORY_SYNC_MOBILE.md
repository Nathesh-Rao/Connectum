# End-to-end: showing the past on a new device (for the mobile team)

Written 1 November 2026, against the backend and web code in this repository. Everything is checked in the code and by tests (names at the end). Companions: `E2E_ENCRYPTION.md` (the reference, section "History for a new device"), `E2E_SIMPLE_GUIDE.md` (plain words), `E2E_MOBILE_KIT.md` (checker and reference messages), the mobile Postman collection (folder 5, change 9).

**Updated 2 November 2026** for the mobile team's questions on the older-device side. Where to look: states, polling and limits → "When a device is late"; full real replies of both roles → "Real replies" (and `docs/e2e-sync-replies.json`); the bytes and the one-time key → "Handing on"; **test vectors with fixed inputs and the refused boxes → "Test vectors for the older-device side"**; which messages and the cursor → "What to hand on, exactly"; `put` and `done` behaviour → "Put and done: the rules"; sessions → "Sessions: exactly what happens"; consent → "Security and consent"; a script that acts as the new device → "Testing the two-device flow with one phone".

## In short

Today a phone (or browser) that is added to an account cannot open what was sent before: the message key is only inside the boxes made when the message was sent. Now **a device the person already uses hands the past on to the new one**, the way WhatsApp does it for a linked device. No code is typed by the person.

**The app must do these:**

1. **Reading (small, needed by every app, even one that never hands anything on).** A box in `keys` may now carry its **own one-time key**: `keys[<this device>] = {iv, w, ek}`. When `ek` is there, use **that** `ek` for the key agreement; when it is not, use the envelope's `ek` as always.
2. **Handing on, and the screens around it.** Know when this device is waiting, offer the older device's owner "Show your earlier messages on …?", and on Approve make the boxes and send them.

3. **Backup and restore (for the recovery code):** the same job with the recovery key as the target, and the other way round on a new device. See "Backup and restore" below.

Nothing else changes: sending, the "a box for every device" rule (`E2E_FRESH_DEVICES_CHANGE.md`), signatures, recovery and the alerts are as before. A client that only does (1) opens everything it is handed; it just never offers to hand the past on.

## The story, for the person

1. They sign in on a new phone. It makes its keys and registers as always. **New messages open at once.**
2. The phone shows: *"Your earlier messages are not shown here yet. Sign in on <their other device> and approve this device. Signing in there signs you out here, so sign in here again afterwards."* (see "One active session" below).
3. On their other device a card asks: *"Show your earlier messages on <new device>? This device was just added to your account. If it is yours, approve it. If you do not recognise it, remove it."* Buttons: **Approve**, **That is not me** (asks once more, then removes the device), **Later**.
4. Approve: the older device works through the person's messages in the background: *"1,240 messages done. Keep this window open until it finishes."* with **Stop**.
5. When it says **All set**, the new device (signed in again) shows the past. The "waiting" card is gone and the open conversation reads again.

The web app does exactly this (`chat-app/features/connectumChat/components/E2ESyncPrompt.jsx`); its texts are good to copy.

## One active session per person (read this)

Connectum allows **one active session per person**: signing in on another device signs the first one out (`session_replaced`). The consequence for this feature:

- The new phone signs in: the older device is signed out.
- The person signs in on the older device (email code) to approve: the new phone is signed out meanwhile.
- When the older device says **All set**, the person signs in on the new phone again.

Both devices keep their keys and their registration throughout (the keys are on the device, not in the session), so nothing is lost and nothing is registered twice. **Do not delete the device keys when a session ends.** A server setting for more than one session at a time would shorten this to one step; that is a company decision and is not built. If it is built later, nothing in the app changes except the texts.

## What the server gives you

| Action | Reply | Use |
|---|---|---|
| `e2e.status {id?}` | `devices[]`, each with `late` (true: still waiting) | The device that is `late` shows "waiting". `late` is false for the first device and every device that existed before this feature. The **recovery key** shows `late: true` until its backup is done, but it is never offered as a device to approve (see "When a device is late"). |
| `e2e.sync.pending {}` | `{waiting:[{id,label,ts}], helpers:[{id,label,ts,seen?}], recovery: null \| {id, backedUp}}` | `recovery` is where the backup stands (below). Both lists only count devices used in the last 30 days (a browser that lost its keys leaves a dead waiting device behind; it is not offered again). **Older device:** `waiting` not empty → show the offer (leave out your own id; it is never in `waiting` while you are not late). **New device:** `helpers` are the devices that can show it (seen in the last 30 days; empty: say none was active recently and point to the recovery code). The recovery key is in neither list. |
| `e2e.sync.page {cursor?}` | `{items:[{id,text}], next}` | The person's own encrypted messages (direct chats and groups they are in), newest first, each envelope already narrowed to **their own boxes**. Send `next` back as `cursor` until it is `null`. What they cleared stays cleared; deleted messages are left out. A page ends after the store page that reaches the limit (default 400 messages), so a long history is a few hundred calls. 600 calls per 10 minutes. **An app that keeps its own envelopes (your SQLite `messages.text`) may use those instead and skip this call.** |
| `e2e.sync.put {device, items:[{mid,iv,w,ek}]}` | `{stored}` | Hand the boxes over: 1 to 500 per call, 400 calls per 10 minutes. `device` is the waiting device's id, **or the recovery key's id (the backup)**: any device of the person is accepted, nobody else's. Errors: `not_found` (not one of your devices), `invalid` (the list is empty, longer than 500, or **any** item is malformed: each item needs a 22-character `mid`, `iv`, `w`, and `ek` as a 65-byte uncompressed P-256 point, all base64url), `rate_limited`. **A device does not have to be waiting: the server stores a box for any device of the person** (that is how a restore on a person's only device works), so "only for a waiting device" is a rule for the app, not something the server enforces. |
| `e2e.sync.done {device}` | `{done:true}` | After the last `put`: the device stops waiting; for the recovery key, `recovery.backedUp` becomes true. |
| event `e2e_devices_changed {user}` | | Sent to **the person's own devices** when a device is added, removed, or finishes: ask `e2e.sync.pending` (and `e2e.status`) again. Do not rely on it alone: while waiting, also ask every 30 seconds or so (the web app does). |

Real replies, in full: the next section and `docs/e2e-sync-replies.json`. The Postman collection (folder 5) has them too.

## When a device is late, and how often to ask

- A device is **`late`** when it is registered for a person who **already had a device** (the recovery key does not count as one). It is marked at registration.
- It stops being late when **any older device calls `e2e.sync.done {device: <its id>}`**. Nothing else ends it: not time, not a sign-in, not the boxes themselves. Storing boxes without calling `done` leaves it late.
- **Never late:** the first device of a person, every device that existed before this feature, and the recovery key (the recovery key shows `late: true` in `e2e.status` until its backup is done, but it is never in `waiting`; its state is `recovery.backedUp` in `e2e.sync.pending`).
- **Removing** the device (`e2e.remove`) also ends it: the device is gone.
- A waiting device nobody used for 30 days is no longer listed in `waiting` (it may still be removed).
- **How often to ask:** while a device is late, `e2e.sync.pending` about **every 30 seconds**, and at once on the event `e2e_devices_changed`. `e2e.status`, `e2e.sync.pending` and `e2e.sync.done` have **no limit of their own** (only the general per-connection limit); the limits that exist are below.

| Call | Limit (per person) |
|---|---|
| `e2e.sync.put` | 400 calls per 10 minutes, 1 to 500 items per call |
| `e2e.sync.page` | 600 calls per 10 minutes |
| `e2e.devices` | 600 calls per 10 minutes |
| `e2e.register` | 30 per hour |
| `e2e.recovery.get` | 30 per hour; `e2e.recovery.set` 10 per hour |

All answer `rate_limited` when the limit is passed; wait and retry the same batch.

## Real replies

Captured from a running server (throwaway people and devices; ids and keys differ every run, the shapes are what matters). All of them, including the failures and a long history with cursors, are in **`docs/e2e-sync-replies.json`** (made by `node tools/e2e-kit/capture-sync-replies.mjs`).

**The older device** (Ann's laptop), after her phone was added. `e2e.status {id: <its own id>}` and `e2e.sync.pending {}`:

```json
{
  "ok": true,
  "data": {
    "devices": [
      {
        "ecdh": "BLZvZxf1yMLPfFiH7UcqCjzGUF3bjzUkeXdcdflPyR_L-FiGHWul5ElaC2fI-R7UPhI_3te0D9D8LbYKJ46P1A4",
        "id": "1bd6d3cab2c42004583acba1701e9188",
        "label": "Ann laptop",
        "late": false,
        "sign": "BKyhmTPguMtrkfbFdJsS6lvcp_n7Uq0dYPszAltYDbi03Xfr3GRU_dU9Gsg7bu-wOPR9zy1MU_rAn5li-v8pwuw",
        "ts": 1793596324053
      },
      {
        "ecdh": "BOQJnZfvgr1HnO7dJUih9Rm9wkAz-4BuBQga9J5OZwwcHo5GLGtRldUT-Tv01eQE5zW2arRoBkurX_O5AdONm_U",
        "id": "1d16eaa4acaa62ed9be52613c71088e0",
        "label": "Ann phone",
        "late": true,
        "sign": "BA8C9wL0gVWSAOMzhzehJY_uft6fdBlqjXDVHElkpi-tsJ4oiy9nue3W90DVaGsVmgSyMc1uguTtNcUx2M7y86Q",
        "ts": 1793596324566
      }
    ],
    "maxDevices": 10,
    "mode": "optional",
    "recovery": false
  }
}
```

```json
{
  "ok": true,
  "data": {
    "helpers": [
      {
        "id": "1bd6d3cab2c42004583acba1701e9188",
        "label": "Ann laptop",
        "seen": 1793596324593,
        "ts": 1793596324053
      }
    ],
    "recovery": null,
    "waiting": [
      {
        "id": "1d16eaa4acaa62ed9be52613c71088e0",
        "label": "Ann phone",
        "ts": 1793596324566
      }
    ]
  }
}
```

`waiting` is not empty: offer "Show your earlier messages on **Ann phone**?". `helpers` is the devices that can show the past (the laptop itself is in it; it is never in `waiting` while it is not late).

**The new device** (Ann's phone), asking the same questions with its own id:

```json
{
  "ok": true,
  "data": {
    "devices": [
      {
        "ecdh": "BLZvZxf1yMLPfFiH7UcqCjzGUF3bjzUkeXdcdflPyR_L-FiGHWul5ElaC2fI-R7UPhI_3te0D9D8LbYKJ46P1A4",
        "id": "1bd6d3cab2c42004583acba1701e9188",
        "label": "Ann laptop",
        "late": false,
        "sign": "BKyhmTPguMtrkfbFdJsS6lvcp_n7Uq0dYPszAltYDbi03Xfr3GRU_dU9Gsg7bu-wOPR9zy1MU_rAn5li-v8pwuw",
        "ts": 1793596324053
      },
      {
        "ecdh": "BOQJnZfvgr1HnO7dJUih9Rm9wkAz-4BuBQga9J5OZwwcHo5GLGtRldUT-Tv01eQE5zW2arRoBkurX_O5AdONm_U",
        "id": "1d16eaa4acaa62ed9be52613c71088e0",
        "label": "Ann phone",
        "late": true,
        "sign": "BA8C9wL0gVWSAOMzhzehJY_uft6fdBlqjXDVHElkpi-tsJ4oiy9nue3W90DVaGsVmgSyMc1uguTtNcUx2M7y86Q",
        "ts": 1793596324566
      }
    ],
    "maxDevices": 10,
    "mode": "optional",
    "recovery": false
  }
}
```

```json
{
  "ok": true,
  "data": {
    "helpers": [
      {
        "id": "1bd6d3cab2c42004583acba1701e9188",
        "label": "Ann laptop",
        "seen": 1793596324593,
        "ts": 1793596324053
      }
    ],
    "recovery": null,
    "waiting": [
      {
        "id": "1d16eaa4acaa62ed9be52613c71088e0",
        "label": "Ann phone",
        "seen": 1793596324644,
        "ts": 1793596324566
      }
    ]
  }
}
```

Its own entry in `devices` has `late: true` (show "waiting"); `helpers` names who can help ("Ann laptop"). When `helpers` is empty, say none of the other devices was active recently and point to the recovery code.

**`e2e.sync.page`** (first page of a short history, three of its items shown; each `text` is the whole envelope with only this person's own boxes in `keys`):

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": 4,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"odHm3_K54IdnsutZQP3xH1gNtz01BWbZyUKYSjgtOQAOO95P3ZpPBKP9YR9Hczr02Zd74T7Tj21AbeYWHtbb0BLfeMiolif1_O2v2t7WQXE\",\"dev\":\"1bd6d3cab2c42004583acba1701e9188\",\"ek\":\"BHE3k1tRa9Sx4u0CkP2S0203yNDCv-wRoUsMc_T9BY7rYmkw47bzykluLJ5UuPPVU3jUXKhQR7Q1tWhtn1vrkwE\",\"from\":\"annxwjq\",\"iv\":\"8b07n3OyPdKbyc3H\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"2OET0_0jcErYtAr4\",\"w\":\"QdQsQZ4oKOSWFTYgKSKLkoiN27AuizRi5RzWwQYzsstOK8Y-8N2TNQYweW4SDr7p\"}},\"mid\":\"VqT66SZssfLIaGFS_fdhMQ\",\"sig\":\"sBcIRdnwZObBleTPC96deQy-plRnt8TBwGxRlILmKVz_OEk92eNEa9fv_rsHp7ocG8WFId9ZzXVWD97_25fe4g\",\"ts\":1793596324508,\"v\":1}"
      },
      {
        "id": 3,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"IqqpmKDerhNaQMep8EshYbFwva8ehD_IMlVqompOXai4njdW8dLpeXBaEO0fhlWy25Syc1AQnmlRflmXdo7Xd8xNr6_y5mD0FFfI5z6E9HU\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BFIKTwa7FKPoCZzZD2zDUr2RCrvGJo6zcNnFqRKz6db_oE2Lu0oBXiO0FYVIMA169o8EieT8M1lZv1twizpPhCw\",\"from\":\"bobxwjq\",\"iv\":\"7HugE_EnJrABbsml\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"Qhe3F-Qv2vrFXc9f\",\"w\":\"3qWUo8YKeivHDhSRlSfKBTZtkPftR1h1lW7ZxPULtT9q4cfCebbOIkM_hwL23ZYq\"}},\"mid\":\"RdOuKJYc_xG-pK7HVCdfgQ\",\"sig\":\"jAHjtNA_N1hXn45PlWk1MHv1rFLCHeVKR8Ze2nuJQiuA2Hn0wwRecvuKV8mC2QVeUZzQ3rvVzW1H7KM16KQcGQ\",\"ts\":1793596324392,\"v\":1}"
      },
      {
        "id": 2,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"NdsGmOiE23KhL9Y0YgCq0oHcR3kJexyezTUncSz6pUEOz7Qo28H7lBHKpP6boZosRl6JMYqHi3UvvvmHZQNc78fs_dSQ6ZgnvwwUIn1RLwM\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BC7h2UMGjjaXmEfOI-ZN_vTTPU55hUeVbv6RApR8EBhbl0sdpcR2nZ3KrNyFZBRT_GbyarUP_JgPAm7oS7IAky4\",\"from\":\"bobxwjq\",\"iv\":\"OWOkR1oTgHv8xjeO\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"MvO2rXGRZhMd1fhp\",\"w\":\"2D1M2MAJ3QzG6490mnl1mLgn1qhkSAcu7XToH9P_QvXLM6ujNMJ178m1oHJ9ZNTW\"}},\"mid\":\"W1h8D6Ehk6x6qLm5vAjSAg\",\"sig\":\"m3HHNEqXTya5iYDbsrHRjLw2XJupZBY7lqKH4naX0Ij8w2jWGtEYX8yTvDKcHbt4eYhaUOlU8sBpI0y-pp7Q3g\",\"ts\":1793596324277,\"v\":1}"
      }
    ],
    "next": null
  }
}
```

**A long history, with cursors** (the first 3 of 50 items shown; send `next` back as `cursor` exactly as it is):

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": 114,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"wWzLUVG6khlJzVfT17jao0VrU9WBy2Bu3nZ6t9EdfQ9Af0yisupvuV-3AXpVy43dEiVNvXxeHBriVyo0Q7KOVJywk-3TwOm10nzQXXUIGB0\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BKKR0QEIs8o0nc5RTauIOfxXwrXVpGnR7PXwectUWUp2Z5PseQ_vbrEkF7HraXOdogBBFAamPcmsFWQranHZlIg\",\"from\":\"bobxwjq\",\"iv\":\"wd2uhHZu7tQGvvY7\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"QDbNnYrFXtGh6ZYY\",\"w\":\"TTKgr9QJLQsVEpcPgAnDJE7_OIuGd9QtIXhatFqWYtPs_OE548OeGrH-nT7FyGMa\"},\"1d16eaa4acaa62ed9be52613c71088e0\":{\"iv\":\"62kXjFH7Cg-KvQiC\",\"w\":\"oIfo6dJB00UfgUyAJyNam0WeHb7I1Im0GIKKMMV9PwTv52JyAvZb_gzss0-T1r_6\"}},\"mid\":\"ulV_81kts6aGqBc_R9gCKA\",\"sig\":\"72Pe_OeCDJwPycpB_OKocAA_1cnsJjQHVQXyEdMx3pc37CsMO-opCDoMZ-Ccbt5-uVZbb2f4u1cKaGfw2uKy8w\",\"ts\":1793596341644,\"v\":1}"
      },
      {
        "id": 113,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"F2eWDrogD4Qh74AhdCY3tSAo1pwx5BEi5-dxc3tdtslFSJItG-NJicbRl7KTmvaci0J2M-YUcVmR9CUM82Y6qBb7UZL3NM4EJYnJ_bBJrPM\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BJ7E2GWaX99oiw1VyMmlv3kI_uYVWuinBlm37TB8BOB4AqB1jlUzHR5hJkREkmvDOvR4JRFAiDlunCJiZdiE4FY\",\"from\":\"bobxwjq\",\"iv\":\"uvYCVeQYRjsaJiPh\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"vaLNrD0ItXaSiSMe\",\"w\":\"8eTOr7uxicGY5Mtd6mtRkanRpx4faWIn6vXAtmNafcX9jPocS5E14UGER8zmKTL4\"},\"1d16eaa4acaa62ed9be52613c71088e0\":{\"iv\":\"kGrlYSriquNCVxnp\",\"w\":\"FMMBvtpDETPM3mzkb-I3nj3WxRx2bdIa4bTMxxvxwlN6La6LNEESocSnqQaGRYzJ\"}},\"mid\":\"XIFz0JbFSYJ_L8H0MeTfag\",\"sig\":\"45FK5iYF1LniXWwuRRV0U6PmBGh0rJ2g6JSE51pKkVPmQJp0k-TkXwAD83QTwTpNACEgY-0G45WFigrgcWeK2Q\",\"ts\":1793596341591,\"v\":1}"
      },
      {
        "id": 112,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"S9zsz2ouhSbktahKki2oCp1LZJRxNrfkkWixUsJiDdifbjCk1hbUj0CjbwnwP-BJOrqJuLXRAaJhNSvZTvB94vPyHEy6Zp0iTjZg2PomgFw\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BLyP-4RyFPyf_L5bj9Z9fyG0Zx0ixc4Ln9xSrh8SBUegc7ceZKdC4w7iVjhLtiw1ALoN_fB1SAXJj8WxLPeAsmc\",\"from\":\"bobxwjq\",\"iv\":\"N_4vL4JejvBaVskP\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"OaK8wYP-S3jbDBQe\",\"w\":\"2gm-FHTJ62rnOMJd-wE7vYjAnRWNWkucRdBpyyZVa34N_cgQ0wTy8JlJbSN7PqF-\"},\"1d16eaa4acaa62ed9be52613c71088e0\":{\"iv\":\"h6mZQEtU1IdHN8M3\",\"w\":\"1LvTalWjPayRayeZvBsCOh9UVFfi-BH2fFtpUYKr2gzoImeAabPLyo90bKDRGTlD\"}},\"mid\":\"IbHav9Lqill6iDvXqUitcA\",\"sig\":\"t8y01fdDACbU5rX1BKJfZhBughV0I2jPgp0C9JYuwzIuPSWAz3zwFqzRN5vrL9aYLh96gUzr9qK6wb9pJZdfpA\",\"ts\":1793596341535,\"v\":1}"
      }
    ],
    "next": {
      "b": 65,
      "c": 0
    },
    "_trimmed": "50 items in this page; the first 3 are shown"
  }
}
```

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": 14,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"9lCWGm4VkbhGKUiUJBxUbqDksNnzZaFquw06hePUJc7-fcdrTXKQngoslE-9R2xEZvU74KnlYDwAMkF6lfOY3ix7TDg1uAj17yk_gjR3BDY\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BDhJmPgYkERgOSrgioM71euyxEXwl8IvIR3bQtf-61D-1nxzTo-EiQlyO73-U972zYdOVJfWv0p3IbnZ5uI6Ibk\",\"from\":\"bobxwjq\",\"iv\":\"iRabuA2L9UjyEdqC\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"kBj9CcvQuhopyHvx\",\"w\":\"UD2pM-d4PL-f7KOm7pcfHXKCU9-hSeu4k_COzzRUvaa2yDqdNsT8OD-RhezEOUin\"},\"1d16eaa4acaa62ed9be52613c71088e0\":{\"iv\":\"aO8YhTP7Uxyn-8Ae\",\"w\":\"Zx1sv0jgxO2PzyRQh1hAzYUcreOdNq7mXT04CPvC1W5U6Pg9HvF9D1mfO0apKZHf\"}},\"mid\":\"WYg_MaHvXtS7AZGulHcfIQ\",\"sig\":\"6xvQYM2R2_aXIJpbmu8pUf_RplZEWkO1WUXB-dpIFJIRXamcjYtaPTiC7lZZNnBMhDCBBLLqLEmSfKhwTlU5VA\",\"ts\":1793596336079,\"v\":1}"
      },
      {
        "id": 13,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"_RoawYLjzK3OofLWcE6ns5uguikrxsl9Xwn_aI3rTJNQIJlobbPs5UKdNrMfa6fEbAH1ZFZyeXhoWJRvuFldkzMtVL4nWhnfepjrucOeEkQ\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BHwY5M2ryBEpeJFPyHVqUppAL3sd74u_PiwAPJMiLbBnCSIR-l3_GVB-Rj7TywCKJmOUOXKLIilMRwtj8_Dei3U\",\"from\":\"bobxwjq\",\"iv\":\"Hr5HFgDC6QUxzQYN\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"v4Ao0apJuCjecOvl\",\"w\":\"3jN4-SLOX4pRnbkpqPaP9m460mairOMFVv_6NX6KOu-UPPGcsSTFFP8Q9hdtk_WU\"},\"1d16eaa4acaa62ed9be52613c71088e0\":{\"iv\":\"cmitd77kavCc-AFe\",\"w\":\"1TKZQhiuYxNOlBWqunWNNqcpaF-8implJQI04uoIvHVUGmMZkTLsBdfRc_zEIST8\"}},\"mid\":\"rB_LMgDliCXUkg1gZfq98Q\",\"sig\":\"09XUpzfnz9FVLrH7ww4W8KBQnxPUiq9LxeDgoaPhkJNeL--h8JkhvK9owbAlPLOUYl1E4sJRaUKLev45KZimHw\",\"ts\":1793596336024,\"v\":1}"
      },
      {
        "id": 12,
        "text": "e2e1:{\"conv\":\"dm:annxwjq|bobxwjq\",\"ct\":\"GPJo-h1EWtlnsfTDrs_ZcXaQ3I07xwk5kioax5mCCp55Wu3YfzCyD_YEIBBQEZZ8FR1Is4iBBpNmkPysOJo6vmM9tBPLnNT4PasfyzEanYk\",\"dev\":\"e6c86326d6b01534aed4f542743273db\",\"ek\":\"BIF9omBYS3D_P_Zv1q9wh9BImFB4iYROou4eo-L0xImGNVtmwQ8Df-QRGHTfH5YQMksaRb21-dxo-1FJOyLaHT4\",\"from\":\"bobxwjq\",\"iv\":\"-wHeIyOnrGXf5xDJ\",\"keys\":{\"1bd6d3cab2c42004583acba1701e9188\":{\"iv\":\"1dqrNl0GjUlvsRwh\",\"w\":\"JmaFwcqQhivfivE2lyORXY3Xs3A0YvAIrpVOGfu8A8V-ijNR103IycN6ZA3wCXle\"},\"1d16eaa4acaa62ed9be52613c71088e0\":{\"iv\":\"kYdCgdDs7TQ0ZvxV\",\"w\":\"Io8pZj-ptRZiuFbPpfsIwOiUMIHD14c4q3iVFxj6xR9cEII-bWfumDRFLYG2gufx\"}},\"mid\":\"jZ-36TP0BYYfDAruROC7kw\",\"sig\":\"pCovsuS_mIsw5yB9S38xirnhdvfDug56CKeNZYhDNdOKfE8_Puk-mX7-rgztjLcnxZ4eOSQvsWsBxvyLvEo4UA\",\"ts\":1793596335969,\"v\":1}"
      }
    ],
    "next": null,
    "_trimmed": "14 items in this page; the first 3 are shown"
  }
}
```

**`e2e.sync.put`**, stored, the same message again, and the ways it fails:

```json
{
  "ok": true,
  "data": {
    "stored": 3
  }
}
```

```json
{
  "ok": false,
  "error": {
    "code": "invalid",
    "message": "Each item needs a message id (mid) and a wrap (iv, w, ek, base64url)."
  }
}
```

```json
{
  "ok": false,
  "error": {
    "code": "invalid",
    "message": "items must be a list of 1 to 500 wraps."
  }
}
```

```json
{
  "ok": false,
  "error": {
    "code": "not_found",
    "message": "No such device of yours."
  }
}
```

```json
{
  "ok": false,
  "error": {
    "code": "rate_limited",
    "message": "Too many history uploads; try again in a moment."
  }
}
```

**`e2e.sync.done`**, and the state after it:

```json
{
  "ok": true,
  "data": {
    "done": true
  }
}
```

```json
{
  "ok": true,
  "data": {
    "devices": [
      {
        "ecdh": "BLZvZxf1yMLPfFiH7UcqCjzGUF3bjzUkeXdcdflPyR_L-FiGHWul5ElaC2fI-R7UPhI_3te0D9D8LbYKJ46P1A4",
        "id": "1bd6d3cab2c42004583acba1701e9188",
        "label": "Ann laptop",
        "late": false,
        "sign": "BKyhmTPguMtrkfbFdJsS6lvcp_n7Uq0dYPszAltYDbi03Xfr3GRU_dU9Gsg7bu-wOPR9zy1MU_rAn5li-v8pwuw",
        "ts": 1793596324053
      },
      {
        "ecdh": "BOQJnZfvgr1HnO7dJUih9Rm9wkAz-4BuBQga9J5OZwwcHo5GLGtRldUT-Tv01eQE5zW2arRoBkurX_O5AdONm_U",
        "id": "1d16eaa4acaa62ed9be52613c71088e0",
        "label": "Ann phone",
        "late": false,
        "sign": "BA8C9wL0gVWSAOMzhzehJY_uft6fdBlqjXDVHElkpi-tsJ4oiy9nue3W90DVaGsVmgSyMc1uguTtNcUx2M7y86Q",
        "ts": 1793596324566
      }
    ],
    "maxDevices": 10,
    "mode": "optional",
    "recovery": false
  }
}
```

```json
{
  "ok": true,
  "data": {
    "helpers": [
      {
        "id": "1bd6d3cab2c42004583acba1701e9188",
        "label": "Ann laptop",
        "seen": 1793596324593,
        "ts": 1793596324053
      },
      {
        "id": "1d16eaa4acaa62ed9be52613c71088e0",
        "label": "Ann phone",
        "seen": 1793596324644,
        "ts": 1793596324566
      }
    ],
    "recovery": null,
    "waiting": []
  }
}
```

**"That is not me"**, and a `put` for the device afterwards:

```json
{
  "ok": true,
  "data": {
    "removed": true
  }
}
```

```json
{
  "ok": false,
  "error": {
    "code": "not_found",
    "message": "No such device of yours."
  }
}
```

## Reading a box that carries its own `ek`

Today: `shared = ECDH(my ECDH private key, envelope.ek)`. Now:

```
box = envelope.keys[myDeviceId]
ek  = box.ek ?? envelope.ek            // a box made later has its own, the sender's boxes do not
shared  = ECDH(myEcdhPrivateKey, ek)    // 32-byte X coordinate, as always
wrapKey = HKDF-SHA-256(ikm = shared, salt = base64url-decode(envelope.mid), info = "connectum-e2e-wrap|" + myDeviceId + "|" + envelope.dev)   // 32 bytes
msgKey  = AES-256-GCM-decrypt(key = wrapKey, iv = box.iv, aad = "e2e1-wrap|" + envelope.mid + "|" + myDeviceId, data = box.w)
```

`envelope.dev` is the **original sender's** device, also in a box made later (it is part of the key derivation, so a client that used the older device's id there would not open the box). The rest (message decryption, signature check) is unchanged; the signature never covered `keys`.

**Reference message:** `docs/e2e-test-vectors.json`, key `lateBox`: a device added after the message was sent, its private keys (throwaway), the envelope with its late box, and the intermediate values (`boxEk`, shared secret, wrap key, `hkdfInfo`, `wrapAad`). `node tools/e2e-kit/e2e-check.mjs` opens it step by step and names the first step that fails (`docs/E2E_MOBILE_KIT.md`).

## Handing on: making a box for the waiting device

For each envelope the older device can open (it has `keys[myDeviceId]`):

```
msgKey = (as above)                                   // the 32 raw bytes
eph    = new ECDH P-256 key pair                      // FRESH for every message: never reuse the sender's, never reuse across messages
shared = ECDH(eph.private, waitingDevice.ecdh)        // waitingDevice.ecdh: its public key from e2e.devices {users:[me]}
wrapKey = HKDF-SHA-256(ikm = shared, salt = base64url-decode(envelope.mid), info = "connectum-e2e-wrap|" + waitingDevice.id + "|" + envelope.dev)
iv     = 12 random bytes
w      = AES-256-GCM-encrypt(key = wrapKey, iv, aad = "e2e1-wrap|" + envelope.mid + "|" + waitingDevice.id, data = msgKey)   // 48 bytes with the tag
item   = { mid: envelope.mid, iv: b64u(iv), w: b64u(w), ek: b64u(eph.public as 65-byte uncompressed point) }
```

It is the same box as any other, with two differences: the one-time key is made by the older device, and it travels in the box (`ek`) instead of in the envelope. Send items in batches of up to 400 as you go (do not hold thousands in memory), then call `e2e.sync.done`.

Rules for the job:

- **Only after the person approved, on this device.** Never start it by itself, never on a push, never for a device that is not listed in `waiting`.
- **Skip, do not fail,** an envelope you have no box for (it was sent before this device existed) or whose box does not open. Count them; the web app shows no number for skipped ones.
- **Stopping half way is fine.** Do not call `done`. Everything stored stays; running it again writes the same boxes again (no duplicates) and finishes. Show a **Stop** button.
- **Look up the waiting device's key fresh** (`e2e.devices {users:[<me>]}`) and refuse if the device is no longer there or is the recovery key.
- **Keep the app awake and say so** ("Keep this window open"). A phone that suspends the job simply leaves the device waiting: the offer appears again next time.
- **Yield between batches** so the screen stays smooth, and show progress. For scale: the crypto of one message (open the box, make the new one) took 0.25 ms on a laptop (about 4,000 messages a second, measured here with the web app's code); a real run is mostly network calls (up to 400 boxes per call), and a phone will be slower than the laptop. We have not measured a phone.
- **Chains work:** a device that was itself shown the past can show it to the next (its box carries `ek`; open it as above, then make a new box). It can only hand on what it holds a box for.

## Test vectors for the older-device side

`docs/e2e-test-vectors.json` → **`rewrap`**. Prove the crypto on the phone with these **before any real send**. Every value is a throwaway; the older device's private key is in the file on purpose. The device and envelope the phone already passes (`recipient`, `envelope`, `lateBox`) are unchanged: the older device here is that `recipient`, and the stored message is that `envelope`.

**Positive cases** (`rewrap.positive[]`: a waiting device, and the recovery key as the target; the bytes and steps are the same, only the target differs). Each has:

- `input.envelope`: the stored envelope as the older device holds it (a box for the older device, no box for the target).
- `input.olderDevice`: `{id, ecdhPkcs8}`, the older device's id and private ECDH key (PKCS8, base64url; the raw scalar is `recipient.ecdh.d` in the same file).
- `input.target`: `{id, ecdh}`, the waiting device's id and **public** ECDH key (65-byte point, base64url).
- `input.fixed`: `{ephPrivateJwk, iv}`, the **one-time key and the iv, fixed so the output is the same every time**. `ephPrivateJwk` is a P-256 JWK (`d` is the private scalar, `x` and `y` the public point); in a real run you generate a fresh key and a random iv for every message.
- `expected.item`: **`{mid, iv, w, ek}`, the bytes your code must produce.** `expected.intermediates` has every value on the way: the older device's own `ownBoxEk`, `ownSharedSecretHex`, `ownWrapKeyHex`, `ownHkdfInfo`; then `msgKeyHex` (the 32-byte message key), `ephemeralPublic`, `sharedSecretHex`, `hkdfSaltHex`, `hkdfInfo`, `wrapKeyHex`, `wrapAad`.
- `expected.envelopeWithBox`: the envelope as the server would hand it to the waiting device, once the box is stored. `input.targetEcdhPkcs8` is the waiting device's private key, so you can open it and read the message (the reference text is in `expected.plaintextPayload` at the top of the same file).

The same numbers for the first case, so a mismatch can be found by comparing:

```
mid              4m1BDDbS54nDe_439URewQ
older device     e4a7c80875a31d2aac65f69c55501225
waiting device   5a7c237d891db44ee3cfd0c656f7a872
hkdfInfo         connectum-e2e-wrap|5a7c237d891db44ee3cfd0c656f7a872|7282251cafd6326cf79fadc1e6ea6eff
wrapAad          e2e1-wrap|4m1BDDbS54nDe_439URewQ|5a7c237d891db44ee3cfd0c656f7a872
{mid, iv, w, ek} {"mid": "4m1BDDbS54nDe_439URewQ", "iv": "atBD30TBT3dTBh7U", "w": "6RZGtxtIMPuV3WRYakcEBJC_gTt3jo6g_oo_bhxkdYyOJEmpXMmJax904Li46tn5", "ek": "BCn3Ps_cN5KGnG788TpX-DhV7cKjkJGU6HzcSbrm246T0GJ_eGbD09Y3CyjZifAk7T4DvhKmN9yhLXZ-TTrn3dE"}
```

**Negative cases** (`rewrap.negative[]`): each is the envelope **as the waiting device would be handed it**, with the waiting device's private key (`ecdhPkcs8`), and `expectFailsAt`, the step of the checker (`docs/E2E_MOBILE_KIT.md`) where it must stop. A client must refuse every one of these:

| Case | Why | Stops at |
|---|---|---|
| a box made for another message (wrong `mid`) | the HKDF salt and the additional data contain the message id | 5 open the box |
| the older device's id in the HKDF info | info is `connectum-e2e-wrap\|<waiting device>\|<envelope.dev>`: the ORIGINAL sender's device, not the device that made the box | 5 open the box |
| the older device's id in the additional data | aad is `e2e1-wrap\|<mid>\|<waiting device>` | 5 open the box |
| the box has no `ek` of its own | without it the reader uses the envelope's `ek` | 5 open the box |
| one bit of `w` changed | AES-GCM refuses it | 5 open the box |
| a good box, delivered in another conversation | the envelope's `conv` must be the conversation it arrived in | 2 conversation |
| an envelope with no box for this device | it was added after the message; nothing was handed on | 3 box for this device |

Two cases that are **not** crypto failures, so they are not in the negative list:

- **The recovery key as the target** is a normal, accepted target (the backup); it is the second positive case. The only difference is in the app: the recovery key is never offered as a device to approve, and `e2e.sync.done` for it sets `recovery.backedUp` instead of ending a `late`.
- **A device that is not waiting**: the server stores a box for any device of the person, so there is nothing to refuse. Not offering it is a rule of the app (only a device in `waiting`, only after the person approved).

**Run the vectors** (needs Node 22 or newer, no install):

```
node tools/e2e-kit/e2e-rewrap.mjs reference         # recomputes every positive case (same bytes out) and checks every bad box is refused
node tools/e2e-kit/e2e-rewrap.mjs check input.json  # checks a box YOUR client made (see docs/E2E_MOBILE_KIT.md)
```

`tools/e2e-kit/e2e-rewrap.mjs` is also the **reference implementation** in plain Web Crypto (`openOwnBox`, `lockFor`, `rewrap`); the app's own version is `rewrapEnvelope` in `chat-app/features/connectumChat/e2e/e2eCrypto.js` and `handOn` in `e2eClient.js`. `tests/frontend/e2eRewrapKit.test.mjs` proves the two give boxes that open with each other's code, in both directions.

## Backup and restore: a person who loses every device (new, 1 November 2026)

The same job, with the **recovery key as the target**. WhatsApp's encrypted backup, without a file in a cloud: the backup is a box per message next to the message, locked for the recovery key, which is locked by the person's code. Nobody but the person can open it.

**Backing up** (when the person turns recovery on, and from "Back them up now" if `e2e.sync.pending` says `recovery: {backedUp: false}`):

1. `e2e.devices {users:[me]}` gives the recovery key as a device with `recovery: true`: its public ECDH key and id are the target.
2. Run the hand-on job above with that device as the target: `e2e.sync.page` → for each envelope, **skip it if `keys[<recovery id>]` is already there** (messages sent after recovery was switched on; the served envelope shows it) → otherwise make the box → `e2e.sync.put {device: <recovery id>, items}` in batches → `e2e.sync.done {device: <recovery id>}`.
3. `e2e.status` shows the recovery key with `late: true` until `done`; the app shows "Your earlier messages are not backed up yet" and a button while it is. A new recovery key (a new code) starts again with nothing backed up. Recovery switched on before this feature is also "not backed up yet".

**Restoring** (a new device, the person types the code):

1. `e2e.recovery.get` → open the sealed key with the code (as before). Now every message backed up for the recovery key opens (the box carries its own `ek`, as above): the app reads with the recovery key.
2. Then **lock the past for this device**, so it no longer needs the code: the same job, **source = the recovery key** (its id and private ECDH key in place of this device's), **target = this device**: `e2e.sync.page` → open with the recovery key's box → box for this device → `e2e.sync.put {device: <this device>}` → `e2e.sync.done`. Skip messages that already have a box for this device.
3. If there are messages but the recovery key opens **none** of them (a code made again whose backup never finished), do not call `done`: tell the person "Your recovery code does not open any earlier message: they were not backed up for it." and leave the device waiting.
4. When it is done: drop the saved copy of the conversations once and read them again (as after a hand-on).

**Texts that work** (the web app's): "Backing up your earlier messages … N messages done. Keep this window open." / "Your earlier messages are backed up. If you ever lose every device, sign in on a new one and enter your recovery code." / "Bringing your earlier messages back" / "Your earlier messages are back. They open on this device now, without the code." The web app also suggests recovery **once**, after a device has been in use for a day ("Back up your messages. If you lose your phone, a recovery code brings your messages back on a new one. Only you have the code: not us, and not the company." with "Set it up" and "Not now"); it asks for the code on the waiting card ("Enter recovery code") whenever recovery is on.

**Security, in short:** the boxes for the recovery key open only with the recovery key's private half; that half is sealed with the 130-bit code and never leaves the device unsealed. A thief with only the session can fetch the sealed blob (rate-limited) but cannot open it, and cannot restore (`e2e.recovery.get` then a wrong code opens nothing). Turning recovery off deletes the key; its boxes are never served again.

## What the phone shows while it waits

- On a device with `late: true` (from `e2e.status` after signing in): the waiting card, with the names of `helpers` from `e2e.sync.pending`, or "none of your other devices was active recently; if you set up a recovery code, enter it".
- Messages from before are the grey line (`not_for_this_device`). The web app's text now reads: *"Sent before this browser was set up for encryption, so it can't be opened here. Approve this device on another device you already use and it will show here, or open it on the device you used then, or enter your recovery code …"*
- When `late` turns false (after the older device finished): **drop any saved copy of the conversations once and read them again** (the saved copy holds the envelopes without the new boxes). The web app remembers "was waiting" across a restart (a flag per device), because the person usually signs in again after the older device finished, with the copy still on the phone. Without that, the grey lines stay until the cache is rebuilt. This was a real bug found in the browser test.

## What to hand on, exactly

`e2e.sync.page` is the list. In order:

- **Which conversations:** every direct chat the person has and every group they are in, in a fixed order (sorted by conversation), so a cursor means the same thing on the next call. A conversation the person **cleared** ("delete for me") is only returned after the point they cleared it; a group they **left** is not returned.
- **Inside a conversation:** newest first.
- **What is in it:** every end-to-end envelope the person can see: messages they **sent**, messages they **received**, **replies**, **group** messages. An **edited** message comes as it is now (one item, the current envelope). **Not** in it: deleted messages, anything that was never encrypted, and forms (a form is not end-to-end).
- **Each item** is `{id, text}`; `text` is the envelope with `keys` narrowed to **this person's own boxes** (a box per device of theirs, and the late boxes already stored). Nothing of anybody else's.
- **Page size:** a page ends after the store page that reaches the limit, 400 messages by default, so a page holds between 50 and about 450 items (the long-history reply above shows 50 because the test server ran with a limit of 2). `next` is `null` on the last page, otherwise an object: **send it back as `cursor` exactly as it is** (treat it as opaque; it can change shape).
- **Using your own stored envelopes instead of `e2e.sync.page`** is fine, if you hold the **whole envelope with your own box**. A message you have no stored envelope for can only be had from `e2e.sync.page`. A message you hold no **box** for (it was sent before this device existed) is skipped, with either source.

## Put and done: the rules

| Question | Answer |
|---|---|
| Items per `put` | 1 to 500 (400 is a good size). More than 500, or none: `invalid`. |
| Calls | 400 `put` calls per 10 minutes per person (`rate_limited` after that). |
| Is a failure reported per item? | **No.** If any item is malformed the **whole call** is `invalid` and nothing from it is stored. Check each item before you send (22-character `mid`, base64url `iv` of 12 bytes, `w` of 48, `ek` a 65-byte uncompressed point). |
| What does `stored` count? | The items in the call, not the ones that were new. |
| The same `mid` twice (in one call, or in another)? | Safe. A device has **one box per message**; the later `put` replaces the earlier. |
| A `mid` that is not one of the person's messages? | The server does **not** check. It is stored and **never served** to anyone (a box is only added to an envelope its owner's device can already see). So a wrong `mid` costs nothing and does nothing. |
| The target is not the person's device | `not_found`. Another person's device: the same `not_found`. |
| The waiting device is **removed** during the job | `put` answers `not_found`: stop and close the card. |
| `done` is **never called** | The device stays `late` and is offered again. Stored boxes stay. |
| Can the job be **resumed**? | Yes: run it again. It rewrites boxes (the same message gets a new box), finishes, and calls `done`. Skip the messages whose envelope already has a box for the target if you want to do less (the web app does). |
| **New messages** arriving meanwhile | They already carry a box for the new device (it is registered), so there is nothing to hand on for them. |
| **Two older devices** helping at once | Safe. Each writes its own boxes; for a message both wrote, the last write is the one served, and either is valid. |
| `done` twice, or for a device that is not late | Harmless: `{done: true}`. For a device that is not the person's: `not_found`. |

## Sessions: exactly what happens

Connectum keeps **one active session per person**. Signing in anywhere else **ends the other session at once** (the other connection is sent `sd_event` `session_replaced` and its next call fails). There is no grace period and no "for how long": the first session stays out until the person signs in there again.

- The new phone signs in: the older device's session ends. The person signs in on the older device (email code) to approve: **the phone's session ends**. It stays out until the person signs in on it again, after the older device says "All set".
- The device keys and registrations live **on the device and in the server's device list**, not in the session, so nothing is lost or registered twice when a session ends. **Do not delete the keys when a session ends.** (`connectum_e2e_sync_rules_test` checks this: after a second sign-in the device list is identical.)
- **The older device must stay signed in during the whole hand-on.** If the new phone (or anything else) signs in as the same person meanwhile, the older device is signed out and the job stops; run it again later (see the table above).
- **There is no time limit to answer the offer.** `waiting` lists a device while it has been seen in the last 30 days; the offer stays until the person answers.

## Security and consent

- **"That is not me"** is `e2e.remove {id}` (not for the recovery key). The device is deleted: it leaves `waiting`, its registration is gone, and its boxes are never served again. The server records `e2e.device_removed`.
- **What the server records about approval:** the approval itself is **not** recorded when the person presses Approve (it is only an app screen). `e2e.history_shown {device}` is recorded when `e2e.sync.done` is called, and `e2e.device_added` when the device registered. The server cannot tell a person's approval from their own device calling `put`, which is why the rule "only after the person approved, on this device" is the app's.
- **Groups:** the per-box `ek` rule is the same for group envelopes (a box made later carries its own `ek`, in any envelope). The signature check does not change: the signature never covered `keys`, so a box can be added later without touching it.
- **Who can write boxes:** only the person, only for **their own** devices (`not_found` for anybody else's). A box can only ever be opened by the device whose private key it was made for, and the server never sees a message key.

## Edge cases and what to do

| Case | What happens | What the app does |
|---|---|---|
| Two older devices both show the offer | Either may approve; if both run, the same boxes are written twice | Nothing special. After `done` the other offer disappears (`e2e_devices_changed`, then `pending` is empty). |
| The person says Later | | Hide it for this run of the app; it comes back on the next start. |
| "That is not me" | | Ask once more, then `e2e.remove {id}` (not for the recovery key). The device is gone from `waiting`. |
| The waiting device is removed during the job | `put` answers `not_found` | Stop and close the card. |
| The job is interrupted (app killed, offline, `rate_limited`) | Device stays waiting; stored boxes stay | Offer again later. On `rate_limited` wait and retry the batch. |
| An empty history | `sync.page` returns no items | Call `done` anyway: the device stops waiting. |
| A message the older device cannot open | Skipped | Fine: it also stays grey on the new device. |
| A conversation the person cleared | Not in `sync.page` | Nothing: it stays cleared. |
| A group the person left | Not in `sync.page` | Nothing. |
| A device that was removed | Its late boxes are never served | Nothing. |
| A waiting device nobody used for 30 days | Not in `waiting` any more (it may still be removed in the lock dialog) | Nothing. |
| A first device lost, no other device | Nobody can hand on | The recovery code: it opens what was sent after recovery was switched on, and the earlier messages **if the backup finished** (see "Backup and restore"). |
| Mode `off` | The sync actions exist but there are no envelopes | Do not show the cards when `e2e.status` says `mode: off`. |
| Rate limits | `rate_limited` | Back off; `put` 400 calls and `page` 600 calls per 10 minutes per person. |

## Testing the two-device flow with one phone

`tools/e2e-kit/new-device.mjs` is a **stand-in for the new device**. You run the real older device (the phone) against it, so the older-device side is tested without a second phone. It makes its own keys (Web Crypto only), registers as a new device of a test person, and later reads what the phone handed on. Needs Node 22 or newer; the state file holds private keys, so use **test accounts** only.

```
node tools/e2e-kit/new-device.mjs register --base http://HOST:PORT --user NAME --token TOKEN --label "Kit phone"
node tools/e2e-kit/new-device.mjs status   --base ... --user NAME --token TOKEN [--wait 120]
node tools/e2e-kit/new-device.mjs read     --base ... --user NAME --token TOKEN [--expect N]
```

`TOKEN` is a session token of the person (from the sign-in flow; the same one the app uses). Because of the one-session rule each command needs a **fresh sign-in**, in the order of the real story:

| Step | Who | Expected |
|---|---|---|
| 1 | Test person P has messages (direct and group, both directions) from the web or the phone. | |
| 2 | Sign in as P, run **`register`**. | `registered device <id> ...; late: true; helpers: <the phone's label>` and "It is waiting". |
| 3 | Send P a new message from someone else. Sign in as P again, run **`read`**. | `1 opened, N with no box for this device`, exit code 1 and "Not everything opened": new messages open at once, the past is grey. |
| 4 | Sign in on the **phone**: `e2e.sync.pending` has `waiting: [{id: <the stand-in's id>, label: "Kit phone"}]`. The phone offers, P approves, the phone makes boxes (`e2e.sync.page`, then `e2e.sync.put`, then `e2e.sync.done`). | each `put` answers `{stored: n}`; `done` answers `{done: true}`. |
| 5 | Sign in as P again, run **`status --wait 30`**. | `"late": false`, exit code 0. |
| 6 | Run **`read --expect N`** (N = the number of encrypted messages P has). | one `PASS #id conv from user: text` line per message, `N opened, 0 with no box, 0 failed`, `OK`, exit code 0. |
| 7 | If a line says `FAIL #id <step>`: that is the step of the checker (`docs/E2E_MOBILE_KIT.md`) that failed, with a hint. A box made wrongly fails at **5 open the box**. | |

Exit codes: 0 good, 1 not good (still waiting, something failed, or fewer opened than expected), 2 wrong arguments. A person with no other device is not late when the stand-in registers (the stand-in is their first device): it says "there is nothing to hand on". Delete the state file to make a new stand-in.

The same story runs against the real server in `connectum-backend/test/connectum_e2e_kit_test.mjs` (22 checks), with the app's own older-device code on the other side.

## How to test it (acceptance list)

With the web app and a phone on the same test organisation, in this order:

1. Person P signs in on the web (first device). Send P a few direct and group messages, and have P send some. Check P reads them.
2. P signs in on the phone (new device). Expect: the phone is `late`, shows "waiting", new messages open at once, old ones are grey.
3. P signs in on the web again, sees the offer naming the phone, presses Approve, watches the progress to **All set**.
4. P signs in on the phone again. Expect: old messages in the direct chats **and groups** now open, both directions; the waiting card is gone; no grey line.
5. P clears a chat on the web and adds a third device: the cleared chat stays empty on it.
6. Press **Stop** half way, then run it again: it finishes, nothing is duplicated.
7. Add a device and press **That is not me**: it is removed and cannot be approved any more.
8. **Backup and restore:** turn recovery on (watch the backup finish), lose the app's data (or sign in on a clean phone with the old one gone), enter the code: the whole past comes back, direct chats and groups, and still opens after the code is forgotten. A wrong code is refused in words.
9. Check `docs/e2e-test-vectors.json` → `lateBox` with `tools/e2e-kit/e2e-check.mjs`, and a message the phone sent itself, on the web.

The same story is tested here, against the real server, with the app's own code: `connectum_e2e_sync_test.mjs` (72 checks: the flow, the refusals, long histories), `connectum_e2e_sync_rules_test.mjs` (34: what a page holds, put twice, a bad item, a job never finished, two older devices, the session), `connectum_e2e_kit_test.mjs` (22: the stand-in new device), `tests/frontend/e2eRewrapKit.test.mjs` (the vectors), and `tools/ui-audit/e2e-sync.e2e.mjs` (a real browser as the new and as the older device).

## What this does not do

- It does not make sessions concurrent (see above).
- It does not change anything for devices that existed before this feature: they never wait.
