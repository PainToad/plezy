# Plex (Plezy fork)

A personal fork of [Plezy](https://github.com/edde746/plezy), focused on Plex Live TV, server-side timeshifting, and a simpler interface.

## Changes in this fork

- **Plex server-side timeshifting:** pause, resume, and seek through the Live TV history retained by Plex, using its server-side capture buffer.
- **Persistent Live TV startup retries:** keep trying until playback starts, or until you leave the player or change channels. If mpv fails while the Plex capture is still active, reopen the same session and stream URL instead of requesting another tuner. Re-tune when Plex confirms the capture has ended.
- **Simplified Live TV:** show the Guide directly, with recording controls, recording screens, and What's On removed from the UI. Timeshifting remains available.
- **Simplified libraries:** show Browse directly, without the Recommended or Collections tabs. Grouping is available only for music, including on phones and tablets.
- **Less UI clutter:** remove the server-activity button and hide paid features without unlocking them.
- **Plex branding:** use the Plex app name, updated app icons, and a gold Plex logo on the loading screen.
- **Apple downloads:** build unsigned iPhone/iPad and Apple TV IPAs, plus a macOS DMG.
- **CI adjustments:** remove the unrelated Server checks and Website checks jobs and improve playback regression coverage and test reliability.

Plex server-side timeshifting and its startup retry behavior are Plex-only. Persistent startup retries are disabled by default and can be turned on under Settings → Video Playback → Live TV. The other supported server backends retain their existing playback behavior.

## Releases

A release is automatically created for each pushed tag once its checks and builds succeed. The release includes direct downloads for the iPhone/iPad IPA, Apple TV IPA, and macOS DMG.

Download builds from this repository's [Releases](https://github.com/PainToad/plezy/releases) page. The IPAs are unsigned and need signing before installation.

## License

Based on Plezy and licensed under [GPL-3.0](LICENSE).
