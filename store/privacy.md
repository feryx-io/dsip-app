# DSIP privacy policy

Effective: `<date of first publication>`. Publisher: `<publisher name>`, `<contact address>`.

DSIP is a phone and messenger built on the open DSIP protocol. It has no accounts with us, no analytics, no crash
reporting, no advertising and no tracking. The publisher runs no server that receives your calls or messages. What the
app sends goes to the services that carry them, which you choose in its settings, and is described below.

## On your device

- **Your identity's keys**: the identity key and the device key, kept in your device's own keystore (the Keychain on
  iOS and macOS, the Android Keystore, Windows' Credential Manager, the Secret Service on Linux), or, where there is
  none, in files only your user account can read. They never leave the device, except inside a recovery code you make
  yourself (sealed under your passphrase), or the welcome code you give a device you add (sealed to that device).
- **Your contacts, conversations and messages**, the names you give people, and the app's settings, in the app's own
  folder. The names you give people are never sent anywhere; a backup you copy yourself holds them, sealed under its
  passphrase.
- **The microphone** is used during calls only, to send your voice to the person you are talking to.

## What each service sees

**Your relay** (the one you set; it carries calls and is how others reach you while the app is open):
- your identity and device identifiers (DIDs);
- the identifiers of the people you call, and who calls you;
- when calls start and end;
- the name you chose, as you present it to others;
- your device's network address;
- each call's media description, which includes network addresses, unless sealing is turned on;
- the people who follow your presence, though not your presence itself, which is sealed.

**Your mailbox** (if you set one; it holds messages while you are offline):
- your identity and device identifiers;
- the identifiers of the people who write to you and of your conversations;
- the size and time of each message.

It cannot read your messages, which are encrypted end to end (MLS). An introduction from someone new is sealed to you
when your key is known to them.

**Hints nodes** (if you set any; they help others find your relay and mailbox when you have no domain of your own): a
public record that anyone can read. It holds your identity, the relay and mailbox you use, your devices' identifiers,
and the public half of your key agreement key, and it is renewed every 40 minutes while the app runs (each record lasts an hour).

**The person you call**:
- your device's network addresses, exchanged so the call's audio can flow directly;
- your identity;
- the name you present.

**The push gateway and Apple or Google** (phones only, when the app is built with a push gateway; it wakes a sleeping
phone for a call or a message):
- The gateway receives your phone's push token and a key made only for this purpose. It never learns your identity.
- When you are called, your relay asks the gateway to wake your phone, and Apple (APNs) or Google (FCM) delivers that.
- The push carries:
  - the kind of wake (a call, a call ended, or a message);
  - the relay or mailbox to connect to;
  - for a call, its session identifier and the caller's identity sealed so that only your phone can read it.
- Apple and Google see your push token and that data, and handle it under their own policies.

**Domains** (when you use an identity on a domain of your own, or call someone who does): the app fetches the
identity's document from that domain over HTTPS, and the domain sees your network address.

**Updates** (Windows, macOS and Linux only): the app checks GitHub, where its releases are published, for a newer
version about once an hour, and downloads it when you ask. GitHub sees your network address. Phones update through
their app stores.

**STUN servers** (only if you set one): they see your network address, to help calls connect.

## Children

DSIP is not directed at children under 13 and collects nothing from anyone.

## Your choices

- **Your data:** delete the app, or its folder, to delete everything it keeps on your device.
- **Services:** the services above are the ones you set in the app, and can be changed or removed at any time.
- **What others received:** what you already sent to other people, or to a relay or mailbox, is kept by them under their
  own policies.

## Changes

A change to this policy is published here with a new effective date, and noted in the app's release notes.
