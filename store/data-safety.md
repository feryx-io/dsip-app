# Store privacy forms

From `privacy.md`. Both stores count as "collected" what leaves the device for the developer's servers, or for third
parties the developer works with. Data that goes only to services the user chooses and runs (their relay, mailbox,
hints nodes, STUN servers), or straight to the person they call, is not collected by the developer. The one server the
publisher runs for the app is the push gateway, and only when the build has one (the phones' official builds).

Check each answer against the store's definitions at submission: they change.

## Apple: App Privacy (App Store Connect)

**Data used to track you:** none.

**Data linked to you:** none.

**Data not linked to you:**

| Type | Collected | Purpose | Notes |
|---|---|---|---|
| Identifiers, Device ID | yes | App Functionality | The push token, sent to the push gateway with a key made only for it, never with the user's identity. Without a push gateway in the build: not collected. |

Everything else is "not collected":
- **Contact info, contacts, user content (messages, audio), location, browsing, usage data, diagnostics:** none
  reaches the developer.
- **Audio** goes from the microphone to the person called.
- **Messages** go end-to-end encrypted to the user's own mailbox.

**Privacy policy URL:** `<privacy policy URL>`.

## Google Play: Data safety

**Does the app collect or share user data?** Yes: one type, collected and not shared.

| Data type | Collected | Shared | Optional | Purpose | Notes |
|---|---|---|---|---|---|
| Device or other IDs | yes | no | no (only when the build has a push gateway) | App functionality | The FCM token, to wake the phone for a call or a message. |

**Security practices:**
- **Encrypted in transit:** yes. TLS to the push gateway, the relay, the mailbox and the hints nodes, and messages
  encrypted end to end.
- **Deletion:** the user can ask for data to be deleted. Uninstalling, or clearing the app's data, removes everything
  on the device. The push gateway keeps no record per user: its handle is sealed data it gives back, and the
  registration lapses within 30 days without the app.
- **Independent security review:** no.

**Not collected:** personal info, financial info, health, messages, photos and videos, audio, files, calendar,
contacts, app activity, web browsing, location, app info and performance. Some of these go to services the user
chooses, or to the person they call, never to the developer.

**Permissions to explain in the listing:**
- **Microphone:** calls.
- **Camera:** scanning a pairing code from another of the user's devices; images are read on the device, never kept or
  sent (not "collected").
- **Notifications:** calls and messages.
- **Phone calls (`MANAGE_OWN_CALLS`):** the system's call screen.
- **Foreground service (phone call):** a call that continues with the screen off.
