# Rules use only Conditions a Song cannot stop meeting

MusicKit lets an app create playlists and append to them, but not remove entries, reorder, or delete playlists. So a Rule may only use Conditions that a Song keeps meeting once it meets them: e.g. "played at least N times" (play counts only grow), never "top 25 most played". A ranked Condition would leave stale Songs in the Sorted Playlist forever.

## Considered Options

- **Make a new Sorted Playlist each run** (e.g. "Most Played – Oct 2026"): rejected. The user would have to delete old playlists by hand.
- **Allow ranked Conditions and accept that they go stale**: rejected. The playlist would stop meaning what its name says.

## Consequences

Tightening a Rule can't remove Songs that were already placed. The UI warns about this and offers to start over in a new Sorted Playlist.
