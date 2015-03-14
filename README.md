# Spotifree
Spotifree is a free OS X app that automatically detects and mutes Spotify audio ads.

## Installing
1. Download **Spotifree** from [the website](http://spotifree.gordinskiy.com);
2. Move **Spotifree.app** to the **Applications** folder, run
3. Let Spotifree patch Spotify
4. Enjoy your ad-free music listening experience :)

On the first run, **Spotifree** will ask you if you want it to run automatically at login. If you agree, the app will be added to the login items. From this moment, **Spotifree** will mute all **Spotify** ads it detects (usually, all of them). Don't worry though, it will not impact your Mac's performance and you'll never notice it running.

## How it works
**Spotifree** is listening to a notification which is sent everytime the next song is played. Now, if the prefix of the current track URL is **spotify:ad** (as in all ads), Spotify is muted for a duration of an ad. When an ad is over, the volume is set to the way it was before.

## Supported Spotify Versions
* *1.0.1.1060.gc75ebdfd*