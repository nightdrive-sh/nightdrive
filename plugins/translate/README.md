# Translate

Type a word or a sentence in the Launcher and get it in your other language: Finnish to English, English to Finnish, without picking a direction. It translates on your own computer by default, and you choose what does the translating.

- In the Launcher: Tools › Translate (or type translate), then type. The translation shows a moment after you stop typing; Enter copies it. A single word also gets its other translations, when the engine knows any.
- ⌘Enter translates what you typed with Claude instead, whatever the engine: slower, and better with single words and tone.
- The language is detected from the text. Tab goes round the modes, shown in the footer: Detect language, Finnish → English, English → Finnish. A direction stays until you change it.
- ⌘⇧V in Translate picks the text from the clipboard history.
- Shift+Tab opens the engines, to pick what translates. Enter on an installed one uses it; one not installed installs in a terminal.

## Engines

| Engine | Where it runs | Good to know |
| --- | --- | --- |
| Opus-MT | offline, 160 MB | The default. Good with sentences, weak with single words. The University of Helsinki's models |
| NLLB-200 | offline, 630 MB | One model for 200 languages. Meta's licence allows non-commercial use only |
| Google Translate | online | Best with single words: it has a dictionary. Needs translate-shell; what you type goes to Google |
| Claude | online | Translates on Enter, in a few seconds, with Claude Code and your Claude plan |

The offline engines download their model once, checked against a known checksum, into `~/.local/share/nightdrive/translate`. After that nothing you type leaves the computer.

## In a terminal

| Command | What it does |
| --- | --- |
| `translate kolinaa` | Translate, guessing the language |
| `translate --to fi "see you tomorrow"` | Translate into Finnish |
| `translate --engine google --json sisu` | With another engine, as JSON |
| `translate engines` | The engines: installed, in use |
| `translate engine install nllb-200` | Install one |
| `translate engine use google` | Translate with it from now on |
| `translate engine remove nllb-200` | Delete its model |
| `translate langs sv en` | Change the pair (the guess works for Finnish and English; other pairs start from the first) |

Text can also come on stdin: `wl-paste | translate`.

The pair and the engine are kept in `~/.config/nightdrive/translate/settings.json` (`"langs": ["fi", "en"]`, `"engine"`): the commands above write it, and it can be edited by hand.

## Your own engine

Any program that prints a translation can be an engine: a JSON file in `~/.config/nightdrive/translate/engines.d/`, named for the engine. `{from}`, `{to}` and `{text}` are filled in; without `{text}` the text comes on stdin. It prints the translation, or JSON with `translation` and `alternatives`.

    {"name": "DeepL", "type": "command", "command": ["my-deepl", "{from}", "{to}"], "online": true}

`"live": false` makes it wait for Enter instead of translating as you type. Another Opus-MT pair is an entry of type `ct2` with its `pairs` (the model's address and sha256), as in the plugin's `lib/engines.json`.

Claude can translate with your engine and list the engines (Settings › Claude › Access › Translate).

Homepage: https://github.com/Helsinki-NLP/Opus-MT
Needs: about 300 MB of disk for the default engine (Opus-MT and its library); an online engine needs the network
