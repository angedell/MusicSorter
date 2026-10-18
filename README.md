# MusicSorter

An iOS app that sorts your Apple Music favorites and Shazam discoveries into playlists automatically, in the background.

MusicSorter reads your **Favorite Songs** playlist and your **My Shazam Tracks** playlist. It then files each song into **Sorted Playlists** based on **Rules** you define, such as "Played 20+ times", "Released in the 1990s", or "Group by Genre", which creates one playlist per genre.

## How it works

- **Source Playlists**: "Favorite Songs" and "My Shazam Tracks". MusicSorter only reads them and never changes them.
- **Rules**: one or more Conditions, all of which a song must meet: genre, play count of at least N, artist, release decade or year, Source Playlist, and the date the song first appeared there.
- **Grouped Rules**: create one Sorted Playlist per genre, artist, decade, or year. A group's playlist is created once it reaches a minimum number of songs (5 by default).
- **Sorted Playlists**: regular Apple Music playlists that MusicSorter creates and adds to. A song can be in several of them. If you remove a song by hand, MusicSorter won't add it back.
- **Sorting Runs**: happen when you open the app and whenever iOS grants background time. Background timing is up to iOS and not guaranteed. You can turn on an optional notification that summarizes each run.

### Why there's no "Top 25" playlist

MusicKit lets apps add songs to playlists, but not remove them. Because of that, Rules only use Conditions a song can't stop meeting. "Played at least 20 times" is allowed; "Top 25 most played" isn't. See [ADR 0001](docs/adr/0001-rules-use-only-conditions-songs-cannot-stop-meeting.md).

## Requirements

- An iPhone with an **Apple Music** subscription.
- Permission for MusicSorter to access your Apple Music library.
- To sort Shazam songs: turn on **Sync to Apple Music** in the Shazam app so it keeps the "My Shazam Tracks" playlist up to date. See [ADR 0002](docs/adr/0002-shazam-songs-via-synced-apple-music-playlist.md). Without it, MusicSorter sorts Favorites only.

## Development

Open `MusicSorter.xcodeproj` in Xcode and run the `MusicSorter` scheme.

- Domain glossary: [`CONTEXT.md`](CONTEXT.md)
- Architecture decisions: [`docs/adr/`](docs/adr/)
- Agent workflow (issues, labels): [`docs/agents/`](docs/agents/)
