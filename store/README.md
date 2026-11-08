# Store listings (app plan A7)

Drafts for when the developer accounts exist (A4c: Apple Developer Program, Google Play Console). Nothing here is
submitted anywhere yet.

- `listing.md`: the name, subtitle and descriptions for the App Store, Google Play and the desktop downloads, within each
  store's limits.
- `privacy.md`: the privacy policy, to be published at a stable URL and linked from both stores.
- `data-safety.md`: the answers for Apple's App Privacy section and Google Play's Data safety form, taken from
  `privacy.md`.
- `screenshots/`: the store screenshots, drawn from the same fixtures as the app's goldens at the sizes the stores ask
  for. Made with `flutter test ../store/screenshots_test.dart --update-goldens` from `app/` (not part of the test run).

The screenshots are drawn from `app/test_store/fixture.json`: people on domains of their own, a short conversation.
Edit it for other content. A presence state the app does not know is shown with its token as it came (the Presence
Profile asks for it, P§5), so the fixture keeps to the registered states.

Before submitting, fill in what is marked `<…>`: the support and privacy URLs and a contact address.

When the app changes what it sends or keeps, change `privacy.md` and `data-safety.md` in the same change.
