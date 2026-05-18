<p align="center">
  <img src="antpodlogo.svg" width="96" alt="AntPod logo" />
</p>

# AntPod
**Six legs. Zero ads.**

Open-source podcast app for Android and iOS — built with Flutter, powered by [PodcastIndex](https://podcastindex.org).

[![Release](https://img.shields.io/github/v/release/ueen/antpod)](https://github.com/ueen/antpod/releases/latest) [![License](https://img.shields.io/github/license/ueen/antpod)](LICENSE) [![F-Droid](https://img.shields.io/f-droid/v/de.ueen.antpod)](https://f-droid.org/packages/de.ueen.antpod)

---

<p align="center">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" width="200" />
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/2.png" width="200" />
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" width="200" />
</p>

---

## Get it

[<img src="https://fdroid.gitlab.io/artwork/badge/get-it-on.png" alt="Get it on F-Droid" height="60">](https://f-droid.org/packages/de.ueen.antpod)

Or build from source — standard `flutter run`.

---

## Subscribe

First launch opens Discover. Search by name or paste an RSS URL directly into the search bar. **Trending** and **Suggestions** tabs surface new podcasts based on what's popular or what matches your existing subscriptions.

Tap any result to preview the podcast and its episodes before committing. Hit **Subscribe** to add it to your feed.

To unsubscribe: open the podcast, tap the share icon → **Unsubscribe**.

---

## Feed

All subscriptions in one chronological list. Filter chips at the top narrow it down:

| Chip | Shows |
|---|---|
| **New** | Unplayed episodes (default) |
| **Playing** | Started but not finished — floated to top |
| **Downloaded** | Saved to device only |
| **Listened** | Completed episodes |
| **Podcasts** | Switch to cover grid; tap any cover to open that podcast |
| **A–Z / Oldest first / Random** | Sort order, combinable with the above |

Tap the **tune icon** (top-right) to collapse or expand the chip bar. The dot on the icon signals active filters.

Tap the **search icon** to filter by episode title or podcast name. No results? A button lets you search PodcastIndex without leaving the screen.

Tap any **podcast cover** in the feed to jump to that podcast's episode list — the **New** filter clears automatically so all episodes are visible. Tap the cover again to return — **New** reselects automatically.

Pull down to refresh all subscriptions.

---

## Playback

Tap the play button on any episode to open the player sheet.

| Control | Action |
|---|---|
| Progress bar | Drag to scrub |
| Skip back / forward | 10 s and 30 s by default; **long-press** to choose any value |
| Speed | Cycles 1× → 1.5× → 2× → 0.8× |
| Chapters | Listed below the progress bar when available; cover art updates per chapter |
| Share | Generates an `antpod.eu/open?…` link anyone can tap to open the same episode |

Audio continues in the background with lock-screen and notification controls. A **mini player** stays visible at the bottom of every screen while something is loaded.

The last-played episode restores on next launch at the same position — as long as it isn't finished.

---

## Downloads

Tap the **download icon** on any episode tile to save it locally. The icon shows a progress ring while downloading; tap again to cancel.

Once downloaded, playback uses the local file — no streaming. The file is **deleted automatically** when the episode finishes (or when you pause within the last minute).

To delete manually: tap the download icon again → **Delete download**, or long-press the episode tile → context menu.

---

## Episode actions

Long-press any episode tile to reveal:

| Action | |
|---|---|
| **Mark as played / unplayed** | Also available via the check button on the tile |
| **Download / Delete download** | |
| **Share episode** | Creates an `antpod.eu/open?…` deep link |
| **Export file** | Share the downloaded audio file directly |
| **Remove episode** | Removes from feed (preview/temporary episodes only) |

---

## Sharing & deep links

Every share action produces an `antpod.eu/open?…` URL. Opening that link on a device with AntPod installed jumps directly to the podcast or loads the episode into the player. On other devices it opens the website.

---

## Languages

English · Deutsch · Español · Français

---

**[antpod.eu](https://antpod.eu)**
