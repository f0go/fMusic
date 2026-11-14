# CarPlay

Minidisc uses native CarPlay audio templates with Songs, Albums and Playlists tabs.
Selecting an album or playlist opens its tracks; selecting a track starts a queue
in the existing player and opens the system Now Playing template. Transport
controls, metadata and artwork use the same Now Playing service as the phone.
CarPlay and the phone share `MinidiscRuntime`, including on a CarPlay cold launch.
Disconnecting CarPlay cancels browsing requests without stopping music.

Songs shows a bounded first page of server tracks; Albums shows recent additions.
Lists respect `CPListTemplate.maximumItemCount`. Local files appear alongside the
server library. Offline browsing uses the app's existing playable download/cache
snapshot and saved playlist membership. No account setup or file import is
performed while driving: configure those on the phone first. Returning to a tab
reloads it, including after switching servers or offline mode on the phone.

All interface strings reuse Localizable.xcstrings translations (English, German,
Greek, Spanish, French, Italian, Japanese, Simplified and Traditional Chinese).
Server titles and artist names remain library metadata.

## Signing and verification

The app declares `com.apple.developer.carplay-audio` and a
`CPTemplateApplicationSceneSessionRoleApplication` scene. Distribution and device
builds require Apple to approve the CarPlay Audio capability for the app's App ID;
regenerate the provisioning profile after enabling it. Adding the entitlement to
the repository alone does not enable it on a distribution profile.

Build with the Minidisc scheme. For simulator tests keep ad hoc signing enabled
(`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`) so fixture Keychain access works.
Open Simulator > I/O > External Displays > CarPlay, then open Minidisc on the
CarPlay home screen. Verify:

- Cold launch from CarPlay and launch with the phone app already running.
- Songs, recent albums, playlist details, selection and Now Playing controls.
- Local files with no configured server, and downloaded music in offline mode.
- Empty libraries, failed requests and retry, disconnect/reconnect.
- Change servers on the phone while a list is loading or displayed: previous
  server lists must never start playback against the new connection.
- Spanish and another app language, including empty/error states.

Apple references: [CarPlay](https://developer.apple.com/documentation/carplay),
[Displaying content](https://developer.apple.com/documentation/carplay/displaying-content-in-carplay),
[CarPlay Audio entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.carplay-audio).

## Verification in this workspace

On 2026-11-14 the iOS 26.5 simulator build and 10 targeted tests passed
(`CarPlayTests` and `MusicIntentTests`). The built manifest contains the CarPlay
scene and the iPhone app launches normally. All nine CarPlay UI strings have
translations in every supported language.

Visual CarPlay verification remains pending: this Xcode installation has no
Simulator.app, and the headless external CarPlay display produces a black image.
No successful visual or end-to-end CarPlay playback test is claimed. Run the
manual checks above with the graphical simulator or a provisioned device before
release.
