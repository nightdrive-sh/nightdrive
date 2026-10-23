# Deck

A fast Spotify player, made for Nightdrive: your albums in the launcher, the player in the top bar, and a window only when you want one.

- Launcher › Music: your albums, the Curated list and Spotify search (artists, albums and songs). Typing there finds your shelf's and Curated's artists and albums, with a row that searches Spotify for the same words. Enter plays: a song plays its album from that song.
- The launcher's own search leaves Deck out unless you turn on Settings › Launcher › Include Deck artists, albums and songs: then your shelf's and Curated's albums and artists come up among the hits, with a row that searches Spotify for what you typed (Spotify is asked only when you pick it).
- While music plays, a player row sits on top of the launcher, and Ctrl+Space plays or pauses.
- The music icon in the top bar opens the player: the cover, the controls, the like and the speaker to play on.
- Hyper+M (Caps Lock + M) opens Deck's window: your shelf, Curated, genre radio, Spotify search and the queue, with the player along the bottom. ⌘W closes it, and the music keeps playing; ⌘Q quits Deck, the music too.

## The window

The sidebar's sections are Shelf, Curated, Radio, Search, Queue and History (⌘1–6 or Ctrl+↑ ↓, / searches). History lists the albums you have played in the last 30 days, newest first. Enter opens an artist or an album and plays a song; Esc or ⌫ goes back. On a row, p plays the album (or the song), e queues the album or the song, a puts the album on your shelf or takes it off, and d removes a track from the queue, or an album from Curated (Deck remembers it, so it isn't suggested again). Space plays and pauses, ← → skip a track, , and . jump 10 seconds back and ahead, l likes the playing one and n opens what plays (its album, or the radio; a click on the player's cover does the same). `?` or Ctrl+? shows all the keys.

Queue shows what plays now at the top, with the playing note on the right (it says when it came from the queue: Next takes the queue's first track), and buttons that play the queue and empty it.

Pick for me (r, or the button on Shelf and Curated) puts an album from your shelf or Curated that you haven't played in a while at the front of the queue, all of it, and starts it: Deck draws them like from a hat, so an album comes again only once the others have played, and every album you play counts (`deck ctl pick`).

Radio lists Deck's genres, your favourites first (the star): a click or Enter opens a genre, and its Play button (or p) starts the radio, which then shows what it plays next; f makes a genre a favourite or not. Deck's own genres (`deck genre add`) are there too.

A click opens an artist or an album, a double click plays a song, and an album's artist in its title opens the artist's albums. The shelf's icon marks the albums on your shelf. An album's own buttons play, queue and shelve it, and the player's shelf icon, by the album's name, does the same for the album that plays. A click or a drag on the player's bar jumps in the track, and the speaker button (or o) picks where the sound plays, as in the Sound menu. When Deck runs into an error (a search that failed, a radio that didn't start), the line beside the speaker says so. Curated says which albums you have listened to (Listened, or how far: 3 of 12), and an album opened from it has a Not for me button (or d): it leaves the list, and the next list learns from it. Albums show their cover and artists their picture, and Curated's New list button has Claude Code make a new list (`deck curate`, a few minutes on your Claude plan): the first press says so, the second starts it, and the list changes when it is ready, even if you close the window meanwhile. Until Curated is set up, the button is Set up with Claude instead (see below). The pictures' addresses are kept in `~/.cache/deck/covers.json`; the images come from Spotify each time.

The music plays in `deck serve`, Deck without its screen, which the window starts when no Deck runs; the window only talks to it. `deck` opens the window, from a terminal too, and `deck tui` gives you Deck's own screen in the terminal when no other Deck is running. `deck-window quit` closes the window and stops the music, `deck-window restart` and `deck-window log` are for trying out changes to the window (`app/`).

## Setting up

The installer builds Deck from source (a few minutes), and `nightdrive update` builds it again when it changes. Deck needs the Client ID of your own free Spotify developer app: Deck's README shows how.

Curated needs your own Spotify app too (it finds its albums through it) and something to go on: best your Last.fm listening history (a Last.fm account that records your Spotify listening, and its API key in Deck's config), or without Last.fm, a few lines about your taste in `~/.config/deck/taste.md` (Deck's README › Setting up Curated). Deck's first start offers Set up with Claude, which opens Claude Code in a terminal to go through what is still missing with you a step at a time, the Spotify app first: it asks whether you have Last.fm, and if not, talks with you about the music you like and writes it down (`deck-window setup` does the same, and so does Curated's button until it is done); Esc puts the offer aside. Sign-ins happen only in your browser. Then Curated's New list makes the first list, and it learns from what you play in Deck. Nightdrive doesn't make a new list every week by itself: New list makes one when you want it.

Homepage: https://github.com/nightdrive-sh/deck
Needs: Spotify Premium
Keys: Hyper+M
