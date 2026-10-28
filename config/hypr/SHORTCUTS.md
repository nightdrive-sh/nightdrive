# Keyboard shortcuts  (⌘ = Super)            close: q

## Apps
  Hyper              Caps Lock: Hyper + a letter opens an app (below); your own: launcher › Settings › Apps › App shortcuts
  ⌘ Enter            Terminal
  ⌘ ⌥ Enter          Claude Code (with text typed in the launcher: sends it as the prompt)
  ⌘ Space            App launcher (↑↓ select, Enter open, Esc close; on an app ⌃Enter adds/removes it in Apps, ⌥Enter starts it at login)
  Hyper B / ⌘ ⇧ Enter  Browser (the default apps: launcher › Settings › Apps › Default apps)
  Hyper F            Files
  Hyper E            Email
  F8 (play)          Play/pause {!deck}
  Hyper W            WhatsApp {whatsapp}
  Hyper S            Slack {slack}
  Hyper T            Teams {teams}
  Hyper Y            YouTube {youtube}
  ⌘ Esc / F3         Notifications (history, do not disturb)
  ⌘ Ctrl L           Lock screen
  ⌃ ⌥ F3             Lock screen, and brings back a lock that died (Hyprland's "lockscreen app died" screen)
  ⌘ ⇧ Space          Top bar by keyboard (←/→ menu, ↑/↓ row, Enter select, Esc close)
  ⌘ ⇧ K              This help

## Copy and paste (in every app)
  ⌘ C / ⌘ V / ⌘ X    Copy / paste / cut
  ⌘ V                In the terminal, a picture too (a screenshot into Claude Code)
  ⌘ Z / ⌘ ⇧ Z        Undo / redo (not in the terminal)
  ⌘ A                Select all (not in the terminal)
  ⌘ S                Save (not in the terminal)
  ⌘ R / ⌘ ⇧ R        Reload / reload without the cache (not in the terminal)
  ⌘ F / ⌘ T / ⌘ J    Find / new tab / downloads: the app's own keys (not in the terminal)
  ⌘ ⌫                Move file to trash (in Files) {!keyd}
  ⌘ ⇧ V              Clipboard history (Enter pastes into the active window, ⇧ Enter copies only; over a launcher text field it pastes there)
  ⌘ ⇧ E              Emoji picker (Enter pastes, ⇧ Enter copies only)
  ⌘ ⇧ C              Claude writes the selected text out (a preview first: Enter replaces, ⌘ ⇧ C writes a new one, Esc cancels; nothing selected: it asks what to write and inserts it; in terminals, if turned on: the command)

## Windows
  ⌘ W                Close window; background apps (Deck, WhatsApp, Slack, 1Password…) are only hidden and keep running, with a green dot in the launcher (their shortcut brings them back)
  ⌘ Q                Quit the app for real: closes all its windows, and an app left running in the tray is asked to quit too (also the background apps; in Deck `q` does the same)
  ⌘ ⇧ U              Reopen the window closed with ⌘W, where it was; again: the one before it (up to 10). A terminal opens in the same folder, Claude Code in the same conversation, editors start again (hypr/reopen-commands)
  ⌘ ⇧ F              Fullscreen
  ⌘ ⇧ T              Tile or float the window; a floating one goes to the centre (Deck: tiled → floating at start size in the centre; moved → back to centre; already there → tiles)
  ⌘ ⇧ J              Toggle split direction (vertical/horizontal)
  ⌘ arrows           Move focus between windows
  ⌥ Tab / ⌥ ⇧ Tab    Next / previous window of the same app (on any workspace)
  ⌘ ⇧ arrows         Move window
  ⌘ + mouse drag     Move window / right button: resize
  ⌘ + drag           A top bar icon: move it (the order is kept; also launcher › Settings › Top bar › Items)
  ⌃ ⌘ + click       A link: the window it opens floats in the centre (not a link that opens in a tab)
  ⌘ ⌥ ← / →         Previous / next tab (any app: sends Ctrl+PageUp/PageDown)
  ⌃ ⌘ ← / →         Back / forward (browsers, web apps, Nautilus)
  ⌥ ← / →           Move by word (⇧ selects)

## Workspaces (like macOS Spaces)
  ⌘ 1 … ⌘ 0          Go to workspace (⌘ 0: the laptop's own screen, with an external display)
  ⌘ ⇧ 1 … ⌘ ⇧ 0      Move window to workspace
  ⌘ ⌥ 1 … ⌘ ⌥ 0      Move all windows to workspace (and go there). These three and ⌘ ⇧ F also work over a VM's window, which otherwise takes every key
  ⌘ Tab / ⌘ ⇧ Tab    Next / previous workspace
  3-finger swipe     Switch workspace
  4-finger swipe     Move window in the swipe direction
  ⌘ D                Drawer: show / hide (slides up over the windows)
  3-finger swipe ↑ ↓ Drawer: show / hide
  ⌘ ⇧ D              Put the window in the drawer / take it back out

## Screenshots
  ⌘ ⇧ S              Region to the clipboard
  ⌘ ⌥ S              Window to the clipboard (click the window)
  ⌘ ⌥ ⇧ S            Whole screen to the clipboard (Save in the notification keeps a copy in Downloads)
  ⌘ Space → Tools › Screenshot   Region, window or whole screen (saved to a file and the clipboard)

## Other
  ⌘ ⌫ / Delete in Settings › Background   Delete the selected own background (press twice; moves it to the trash)
  Top-row keys       Volume, screen brightness (F1/F2); keyboard backlight = ⌘F1/⌘F2
  F3                 Notification center (hamburger menu)
  F4                 App launcher (like ⌘Space)
  F5 / Fn / Insert   Dictation, held: speak, let go to type it (F5 or Fn on a Mac, Insert on a PC)
  ⌘ F5              Mic on/off (toast)
  F6                 Do not disturb (hides notifications, toast shows state)
  ⌃ + click          In the terminal: a link, or a file or folder path in the output (Claude Code's too): a folder in Files, a file in the code editor at its line (file.py:42)
