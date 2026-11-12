# Tests on real devices

CI runs the app's code on every platform. It does not cover the parts that need hardware or the system's own UI:

- the camera reading a QR code off another screen;
- the system's save and open dialogs;
- a backup made on one platform and restored on another.

Run this list by hand before a release that changes any of them, and record what you saw in the table at the end.
Wakes by push have their own conditions: a push gateway and, on iOS, a signed build (README, "On a phone"). They are
not part of this list.

## What you need

- **Desktop:** the release's Windows setup, `.dmg`, AppImage or `.deb`. The first run warns because nothing is
  code-signed yet; README, "Releases", says how to get past it.
- **Android:** the release's `DSIP-vX.Y.Z-android.apk`, or, between releases, `app-release.apk` from the
  `dsip-app-android` artifact of a CI run on `main`; installed with `adb install` or from the phone's files.
- **iPhone:** `flutter run --release -d <iphone>` from a Mac with Xcode and your own development team. CI's build is
  unsigned and does not install.
- **Two identities:** each needs a relay to start with (any relay you run).

Use an install with no identity wherever a step says "fresh". On desktop, start the app with an empty identity folder.
On a phone, uninstall and reinstall, which clears the app's data.

## 1. Pairing by QR code

On each device, a code is shown as text and as a QR code. A phone has a **Scan** button beside the code field, and a
desktop has none.

How pairing works:

1. On the **new** device, choose **Join another device**. It shows a join code, its QR code and a check code.
2. On the device that **has** the identity, open **Settings → Add a device**. Scan or paste the join code, then choose
   **Make the welcome code**.
3. That device shows the welcome code, as text and as a large QR code, with the same check code.
4. On the new device, scan or paste the welcome code, then choose **Start**.

| # | New device | Has the identity | Check |
|---|---|---|---|
| 1.1 | phone | desktop | The phone scans the desktop's welcome QR off its screen. This is the case CI cannot reach: the welcome code is the large one, about 1,100 characters. |
| 1.2 | desktop | phone | On the same Wi-Fi, the phone scans the desktop's join QR, and the welcome code reaches the desktop by itself: the phone says "Sent", and the desktop says "Received from" with the identity's name. Allow the firewall's prompt on Windows and macOS, and note whether it showed. Repeat with the phone on mobile data instead: the phone says it could not reach the device, and shows the welcome code to type or paste. |
| 1.3 | phone | phone | Android scans iPhone and iPhone scans Android, in both directions. |
| 1.4 | phone | phone | 1.1 again with the showing device in dark mode, at low brightness, and from about 30 cm and 60 cm away. |

For each:

- [ ] When both devices are on one network, the welcome code goes across by itself, whichever device is new. On an
  iPhone, the first time asks to use the local network; refused, the code is shown to scan or type instead.
- [ ] The first **Scan** asks for the camera. If you refuse, the app says the camera is not available and you can still
  paste the code.
- [ ] The scanner takes only the right code. Show it some other QR code first (any URL): it keeps scanning and does
  not fill the field.
- [ ] The check codes on the two devices match.
- [ ] After **Start**, the new device's **Settings** shows the same identity. A call to the identity from the other
  identity rings on the new device.
- [ ] Back out of the scanner without scanning: the field is unchanged.

## 2. Saving a backup as a file

Give a name to at least one contact and follow at least one identity first, so the file holds the sealed names
(`DSIPC1-…`). Then open **Settings → Identity backup → Back up**, enter a passphrase twice, and choose **Save as a
file**.

| Platform | The dialog is | Also save to |
|---|---|---|
| Windows | the system's Save dialog | — |
| macOS | the system's Save sheet; the sandbox allows writing where you choose | iCloud Drive |
| Linux | the desktop portal's dialog (GNOME, KDE) | — |
| Android | the system's file picker | Downloads, and Google Drive |
| iPhone | Save to Files | On My iPhone, and iCloud Drive |

For each:

- [ ] It offers the name `dsip-backup-YYYY-MM-DD.txt` with today's date.
- [ ] After saving, the app says "Saved.". The file opens in a text editor and shows:
  - "DSIP identity backup";
  - the identity and the name;
  - the `DSIP1-…` code;
  - the line about names and follows;
  - the `DSIPC1-…` line.
- [ ] Cancelling the dialog shows nothing and leaves the code on screen.
- [ ] **Linux, without a portal.** Run the AppImage in a session with no `xdg-desktop-portal` (a bare window manager).
  The app says "The file was not saved: …" and does not hang or crash. **Copy with names** still works.

## 3. Restoring from a backup file

On a **fresh** install, choose **Restore from a backup**, then **Open a backup file**, and pick a file saved in part 2.

- [ ] The code field fills with the file's text.
- [ ] With the right passphrase and a relay, **Start** restores the identity. It is the same identity as the one
  backed up, with a new device key.
- [ ] The contacts you named show those names, and the identities you followed are followed again.
- [ ] A wrong passphrase fails with a message, and the install stays fresh: you can try again.
- [ ] A photo, or any file that isn't text, says it could not be read as a backup.
- [ ] **Android:** a file in Google Drive that isn't downloaded yet opens: the picker fetches it.
- [ ] **iPhone:** a file in iCloud Drive opens.

Restore across platforms at least once in each direction:

- [ ] a file saved on a phone, restored on a desktop;
- [ ] a file saved on a desktop, restored on a phone.

Carry the file however a person would: AirDrop, a cloud drive, email to yourself.

## Results

Copy this table into the release's notes or its issue:

| Test | Windows | macOS | Linux | Android | iPhone |
|---|---|---|---|---|---|
| 1.1–1.4 pairing by QR | | | | | |
| 2 saving a backup file | | | | | |
| 3 restoring from a file | | | | | |
| 3 across platforms | | | | | |

In each cell, record the version and device (for example "0.4.0, Pixel 7, Android 15"), then ✓, ✗ with what happened,
or "not run".
