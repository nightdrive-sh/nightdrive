# Games

The games on this computer with their covers, in a window that floats in the middle of the screen. The controller's
Xbox button opens it, the d-pad or the left stick picks a game, and A plays it: the window closes, and the game has the
screen and the controller.

## Using it

| Keys | Controller | |
| --- | --- | --- |
| ← → ↑ ↓ | d-pad, left stick | Pick a game |
| `Enter` | A | Play it |
| `Esc` | B, or the Xbox button again | Close |

- **The games** are the apps whose category is Game (one of your own, a Flatpak game) and every game in Steam's library. A game Steam is still downloading shows how far; A opens it in Steam, which goes on downloading.
- **Steam games** start through Steam, which may take a while, more so on an ARM Mac, where Steam runs emulated. A notification says it is on its way.
- **The Xbox button** works with any controller that has one (Xbox, PlayStation), over Bluetooth or a cable, also after it reconnects. While a Steam game runs, the button is Steam's. While Games shows, the controller moves only in it: a game behind it doesn't see the presses.
- **A cover of your own** for a game that isn't Steam's: in its `.desktop` file (`~/.local/share/applications`), `X-Nightdrive-Cover=/path/cover.png`, a 2:3 picture such as 600×900, and if you like `X-Nightdrive-Hero=/path/backdrop.png`, a wide one shown behind the covers. Without them the card shows the game's icon.
- The Launcher has the same games without the covers: Launcher › Games, and searching finds Steam's games by name. Without this app, the Xbox button opens that page instead.
- `nightdrive games` lists the games (`--json`) and `nightdrive games launch ID` starts one. Claude can list them and, once you allow it, start one. `games` opens the window, `games quit` closes it.

Needs: nothing to set up; a controller for the Xbox button
