# LocalWillow for iPhone

Fully local dictation on iOS: hold the button, speak (English or Korean), release —
the cleaned-up text is copied to the clipboard and saved to history. A custom keyboard
extension inserts any recent dictation into any app. All recognition runs **on-device**
(`SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`); nothing leaves the phone.

Like Willow's own iOS app, the keyboard can't record audio — iOS forbids microphone
access in keyboard extensions — so the keyboard's mic button jumps to the app, and the
result appears both in the clipboard and in the keyboard's recent list.

## Build & install (requires Xcode on this Mac)

1. Install Xcode from the App Store (the project was scaffolded without it).
2. `cd ios && xcodegen generate` (already generated; rerun after editing `project.yml`).
3. `open LocalWillow.xcodeproj`
4. In **Signing & Capabilities** (both targets): select your team (a free Apple ID works).
   If the App Group capability fails on a free account, remove
   `group.dev.yun.localwillow` from both targets — everything works except the
   keyboard's recent-dictations list.
5. Plug in your iPhone, select it as the destination, press Run.
6. On the phone: Settings → General → VPN & Device Management → trust your developer
   certificate. With a free Apple ID the install expires after 7 days — just Run again.

## Enable the keyboard

Settings → General → Keyboard → Keyboards → Add New Keyboard → **LocalWillow Keys**,
then enable **Allow Full Access** (needed to read the shared history; the keyboard has
no network code — verify in `Keyboard/Sources`, it's ~150 lines).

## On-device language models

iOS downloads on-device speech models per language. If Korean (or English) dictation
reports it isn't available, enable that language under Settings → General → Keyboard →
Enable Dictation, and add the keyboard language; iOS fetches the on-device model.

## Upgrade path

`SFSpeechRecognizer` is the pragmatic on-device engine. For Whisper-quality parity with
the Mac app, swap `SpeechEngine` for whisper.cpp compiled for iOS with a `base`/`small`
quantized model (~60–190 MB in the bundle) — the rest of the app is engine-agnostic.
