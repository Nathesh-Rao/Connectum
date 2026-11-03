# End-to-end encryption in Connectum, in plain words

For everyone on the team: product, support, mobile, web. No maths. The exact rules are in `E2E_ENCRYPTION.md`; this page is the story.

## The idea in four lines

1. When you send a chat message, your phone or browser **locks it** before it leaves the device.
2. Only the devices of the people in that chat have a key that opens it.
3. **Our server only carries the locked message.** It cannot read it, and neither can anyone who gets into the server's database.
4. Reading, writing and locking all happen **on the device**. The person should never have to think about it.

## The pieces

| Piece | What it is, in plain words |
|---|---|
| **Device** | One browser or one phone. Every device makes **its own** pair of keys the first time you sign in on it. A person can have up to 10 devices. |
| **Padlock** | The *public* half of a device's key. The server keeps everyone's padlocks. Anybody may look one up. |
| **Key** | The *private* half. It stays on the device and is never sent anywhere. |
| **The safe** | Every message is locked in its own little safe, with a brand new combination each time. |
| **A box per device** | The combination is copied into **one small box for every device** of everybody in the chat (and for your own other devices). Each box can only be opened by the device it is made for. |
| **The stamp** | The sender's device also stamps the message (a signature), so nobody can pretend to be the sender or change a word. |
| **Envelope** | The safe + the boxes + the stamp, sent as the message text (it starts with `e2e1:`). |

## What happens when Ann writes to Bob

1. Ann's app asks the server: "which devices do Bob and I have right now?" (the list of padlocks).
2. It locks the message and makes **a box for each of those devices**.
3. It sends the envelope. The server checks that it is addressed properly and that **every person has at least one box**. It does not look inside.
4. Bob's device finds **its own box**, opens it with its key, checks the stamp, and opens the safe. Bob reads the message.
5. Notifications and previews ("Ann: hello") are made **on Bob's device** after it opens the message, so even previews do not show our server any words.
6. Photos, voice notes and GIFs are locked on the device before they are uploaded. The key to them travels inside the locked message.

## The grey message, and why you sometimes get it

> 🔒 *Sent before this browser was set up for encryption, so it can't be opened here. Approve this device on another device you already use and it will show here, or open it on the device you used then, or enter your recovery code under the lock at the top of a chat (if you switched recovery on before it was sent).*

It means one thing: **the envelope had no box for this device.** There are only a few ways that can happen.

| Why | How to tell | Is it a bug? | What helps today |
|---|---|---|---|
| **1. This device is new.** First sign-in on this browser or phone, or the browser's site data was cleared, or it was a private window. A new device starts with new keys and nobody made a box for it in older messages. | The message is older than this device. | No, it is how end-to-end works. | **Approve this new device on one you already use: the earlier messages then appear here by themselves** (next sections). Or open the message on the device you used then. Or use the recovery code, **if recovery was switched on before the message was sent**. |
| **2. The sender's app used an old list of your devices.** Your device already existed, but the sender's app did not know about it yet (a list kept for a few minutes, or a tab or app left open for a long time), so it made no box for it. | This device was already signed in when the message was sent. | It was a bug in the sender's app. **The server now refuses such a message** (`e2e_stale_devices`) and the app sends it again by itself, so it should no longer reach anyone. If you still see it for a message sent after this change, that is a new bug: tell us. | Messages sent **before** this change stay unreadable on that device. For new ones nothing is needed. |
| **3. You removed a device** in the lock dialog, then signed in on it again. | You pressed Remove on it. | No. | Same as 1. |
| **4. A client is not following the format** (for example a different signature form). The envelope is not readable by anyone else. | Several people cannot read the same sender's messages. | **Yes**, in that client. | The checker names the exact step that fails. |

## The recovery code and the backup (done, 1 November 2026)

Recovery is **one more device that lives on the server in a locked form**. A person switches it on once and gets a long code (26 characters), shown once. Two things then happen:

- every message **sent from then on** also gets a box for the recovery key, as for any device;
- the app **backs up the earlier messages**: it locks each old message for the recovery key too, with a progress bar. This is the same job as showing the past to a new device, with the recovery key as the target.

If the person **loses every device**, they sign in on a new one and type the code. All the messages come back, and the new device then locks the past **for itself**, so it no longer needs the code. This is what WhatsApp's encrypted backup does. There is **no file in a cloud**: the backup is a small locked box next to each message, in the same place as the messages, and it opens only with the recovery key, which opens only with the code. The server, the company and the storage provider cannot open it.

What it costs the person: **keep one code**. If every device and the code are lost, nothing can be brought back (WhatsApp is the same). To make that code easy to switch on, the app suggests it once, after a device has been in use for a day ("Back up your messages", with "Not now"). A recovery switched on before this feature shows "Your earlier messages are not backed up yet" with a button to finish it.

## When a device is added to an account

A new device can read every message sent to that account from then on, so people must be able to notice one that is not theirs. The owner gets an item in their notification panel on all their devices ("A new device was added to your encrypted messages", naming it, and saying how to remove it). Somebody who writes to that person is told once by their app. A person's very first device is not announced, and neither is switching on recovery. This does not stop an attacker, but it stops one from going unnoticed.

## A new device is shown the past (done, 1 November 2026)

This is how WhatsApp, Signal and Telegram do it for a linked computer or tablet: **a device you already use hands the past to the new one**. Nobody types a code.

1. You sign in on a new phone or browser. It makes its own keys, as always. Messages **from now on** open on it at once.
2. It shows a small card: *"Your earlier messages are not shown here yet."* It is **waiting**.
3. On a device you already use, a card asks: *"Show your earlier messages on Chrome on Windows? If you do not recognise it, remove it."* You press **Approve**.
4. That device opens each old message with its own key, locks the message key again **for the new device** (a new box, made with a new one-time key), and gives the boxes to the server. It shows progress ("1,240 messages done") and a "keep this window open" line.
5. The server keeps each new box **next to the message** and adds it to the message **only when it is served to that device**. The new device's cards disappear by themselves and the conversations read again: the grey lines open.

Why this is safe: a box is a locked box that only the new device can open. The server learns nothing it could not see before, the sender's signature does not cover the boxes (so it still verifies), and the older device only ever does this **after the person pressed Approve**. Somebody who stole your session and added their own device cannot read your past, because only your own older device holds the keys to hand it on. They are told by the alert in the previous section, and you can press **That is not me**, which removes the device.

**One thing to know:** Connectum allows **one active session per person**. When you sign in on the new device, the older one is signed out ("signed in elsewhere"). So the steps are: sign in on the new device; sign in on the older device and press Approve (the new device is signed out meanwhile); when it says **All set**, sign in on the new one again. Nothing is lost: both keep their keys. If the company allows more than one session at a time (a setting for the CTO, not built), this becomes one step shorter.

**What it cannot do:**
- A person with **one device only** who loses it has nobody to hand the past on. For them the **recovery code and its backup** (the section above) are the way. Without recovery, nothing can be brought back.
- Messages the older device itself cannot open (sent before *it* existed) cannot be handed on; they stay grey.
- What the person **cleared** stays cleared, and deleted messages are not handed on.

## Where things are

| What | Where |
|---|---|
| The exact rules and the code, file by file | `E2E_ENCRYPTION.md` |
| A checker and reference messages for other clients (the Flutter app) | `tools/e2e-kit/`, `E2E_MOBILE_KIT.md`, `e2e-test-vectors.json` |
| Tests | backend `connectum_e2e_*_test`, browser tests, `tests/frontend/e2eKit.test.mjs` |
| The lock dialog | the lock at the top of a chat: your devices, a safety number to compare with the other person, and recovery |

## Words you will hear

- **Device id**: a name for one browser or phone, 32 letters and digits.
- **Wrap**: make one box for one device.
- **Envelope**: the sent text: safe, boxes, stamp.
- **Signature**: the stamp. **P-256, AES-GCM, HKDF**: the standard ingredients; you do not need to know them.
