# CarPlay

Minidisc uses native CarPlay audio templates with Home as the root screen. The leading Library button opens Albums and
Playlists; the trailing magnifying glass opens voice search.
Selecting an album or playlist opens its tracks; selecting a track starts a queue
in the existing player and opens the system Now Playing template. Transport
controls, metadata and artwork use the same Now Playing service as the phone.
CarPlay and the phone share `MinidiscRuntime`, including on a CarPlay cold launch.
Disconnecting CarPlay cancels browsing requests without stopping music.

Home shares the iPhone Home feed and section order: playlists, favorite songs and
albums, recently played, heavy rotation, rediscovery, relevant additions, recent
additions and genre shelves. Empty sections are omitted. Albums shows recent additions.
Playlists use native iOS 26 image row elements with the same preview limit as the
phone's carousel. Artwork resolves through PlaylistCoverManager and the shared
artwork cache, including custom and downloaded covers. Tapping artwork opens the
matching playlist; tapping the carousel title opens the playlist list.

Favorite songs show the five highest server play counts. Ties and missing counts
preserve source order. The clickable favorite title opens the complete available
favorite list (subject to CarPlay's native list limit), ordered by the same counts.
The online list comes from getStarred2 rather than the Home feed's bounded preview.

Local-only Home shows recent local albums and artists. Home includes Apple's
native Siri assistant cell directly above its sections, with the Play Media
action and the existing SiriKit handler for songs and playlists. There is no
search button or intermediate search screen. The system controls the voice affordance's
placement and appearance; no microphone recording or private Siri URL is used.
Lists respect `CPListTemplate.maximumItemCount`. Local files appear alongside the
server library. Offline browsing uses the app's existing playable download/cache
snapshot and saved playlist membership. No account setup or file import is
performed while driving: configure those on the phone first. Returning to a browsing screen
reloads it, including after switching servers or offline mode on the phone.

Song detail lists (albums, playlists, favorites and local collections) include a
native horizontal action row above the songs: shuffle, repeat, endless playback, and Musical Mix.
They invoke the same player/settings actions as the iPhone queue and observe its
shared state, including changes made from the phone. Active modes have a filled
red icon background; Repeat One changes the icon. Endless is disabled for local
tracks, matching the phone. Popping a list or disconnecting CarPlay releases its
control observer.

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
- Home sections, recent albums, playlist details, selection and Now Playing controls.
- Native Siri assistant: request a song and a playlist by name.
- Local files with no configured server, and downloaded music in offline mode.
- Empty libraries, failed requests and retry, disconnect/reconnect.
- Change servers on the phone while a list is loading or displayed: previous
  server lists must never start playback against the new connection.
- Spanish and another app language, including empty/error states.

Apple references: [CarPlay](https://developer.apple.com/documentation/carplay),
[Displaying content](https://developer.apple.com/documentation/carplay/displaying-content-in-carplay),
[CarPlay Audio entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.carplay-audio).

## Verification in this workspace

On 2026-11-15 the device build and 16 targeted simulator tests passed
(`CarPlayTests`, `HomePersonalizationTests`, `SiriMediaIntentTests`). The signed
app was installed on the connected iPhone and opened in Device Hub CarPlay
Simulator over USB. Home, its trailing search button and the native Siri assistant screen were visually verified.
All app-authored CarPlay strings have translations in every supported language.
Apple localizes the Siri assistant cell itself.

The magnifying glass opens a native list containing the Siri assistant cell;
tap that cell to speak. Apple does not expose a public API to invoke Siri directly
from an arbitrary bar button. A spoken song/playlist request still requires a
manual end-to-end check with Siri enabled on the phone.

On 2026-11-15 the playlist artwork selection, five-song favorite preview, and
navigation to the complete favorite list were checked in CarPlay Simulator with
the USB-connected iPhone. Five targeted CarPlay tests passed, including ranking,
ties, missing counts and preservation of the complete list.

On 2026-11-15 the four playback controls were verified in Device Hub CarPlay
with the USB-connected iPhone, in album, playlist and favorite song lists.
Shuffle, all/one/off repeat, endless and Musical Mix updated their visible state.
The device build and all seven targeted CarPlay simulator tests passed.
Screenshot: `artifacts/carplay/track-controls.png`.

Direct Home Siri access was verified on 2026-11-15 in Device Hub: tapping the
assistant cell activates Siri without navigation. The device build and seven
CarPlay simulator tests passed. Screenshot: `artifacts/carplay/home-siri.png`.
