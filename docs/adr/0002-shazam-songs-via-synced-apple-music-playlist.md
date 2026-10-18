# Shazam songs are read from the synced "My Shazam Tracks" playlist

Third-party apps can't read the user's Shazam history (`SHLibrary` exposes only items the app itself added), and ShazamKit recognition doesn't run in the background. So the app treats the "My Shazam Tracks" Apple Music playlist, which the Shazam app keeps up to date when "Sync to Apple Music" is on, as a Source Playlist. The user has to turn that setting on; the app detects when it's off and walks them through it.
