# MusicSorter

An iOS app that reads songs from the user's Apple Music Source Playlists and files them, in the background, into Sorted Playlists according to Rules the user defines.

## Sources and outputs

**Source Playlist**:
An Apple Music playlist the app reads songs from but never modifies: the system "Favorite Songs" playlist and the "My Shazam Tracks" playlist synced by the Shazam app.
_Avoid_: Input playlist, origin

**Sorted Playlist**:
An Apple Music playlist the app creates and owns, holding Songs placed by one Rule. A Song may be in several Sorted Playlists at once.
_Avoid_: Sub playlist, smart playlist, bucket

**Song**:
A single Apple Music catalog track, identified by its catalog ID. A track that appears in more than one Source Playlist is still one Song.
_Avoid_: Track, item, media item

**Primary Genre**:
The first genre listed for a Song, ignoring the catch-all "Music". Grouped Rules group by it; a genre Condition instead matches any of the Song's genres.
_Avoid_: Main genre, top genre

**First Seen**:
The moment the app first found a Song in a given Source Playlist; used in place of a true "date added".
_Avoid_: Date added, Shazam date

## Rules

**Rule**:
A user-defined set of Conditions, all of which a Song must meet to be placed into that Rule's Sorted Playlist(s).
_Avoid_: Criterion, filter, sort

**Condition**:
One test within a Rule (genre, play count at least N, artist, release decade or year, Source Playlist, First Seen). Conditions are chosen so that a Song that meets one keeps meeting it. A Condition that can't be checked because the Song lacks the data counts as not met.
_Avoid_: Clause, predicate

**Grouped Rule**:
A Rule that creates one Sorted Playlist per Group instead of a single Sorted Playlist. It groups by Primary Genre, Artist (the Song's first linked artist), Release Decade, or First Seen year. Songs missing the grouping value are left out.
_Avoid_: Split rule, dynamic rule

**Group**:
The Songs that meet a Grouped Rule and share one grouping value (e.g., all Songs whose Primary Genre is Jazz).
_Avoid_: Category, bucket

**Group Threshold**:
The number of Songs a Group needs before its Sorted Playlist is created; the user sets it per Grouped Rule. Once created, a Group's Sorted Playlist is never removed; only Starting Over detaches it, after which the Group must reach the threshold again.
_Avoid_: Minimum, cutoff

**Placement**:
The permanent record that the app added a given Song to a given Sorted Playlist. A Song is never placed into the same Sorted Playlist twice, even if the user removed it by hand.
_Avoid_: Assignment, membership

**Sorting Run**:
One pass in which the app reads the Source Playlists, applies every active Rule, and records new Placements. It runs when the app opens and whenever iOS grants background time.
_Avoid_: Sync, refresh, scan

**Starting Over**:
Detaching every Sorted Playlist of a Rule, so the next Sorting Run creates new ones holding every Song that meets the Rule then. The detached playlists stay in Music, and the app never adds to them again. The way to undo a tightened Rule's old Placements (ADR 0001).
_Avoid_: Reset, rebuild

**Paused Rule**:
A Rule the app has stopped applying because the user deleted one of its Sorted Playlists outside the app.
_Avoid_: Disabled rule, broken rule
