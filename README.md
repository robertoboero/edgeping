# edgeping

A Claude Code plugin for macOS. When a conversation in one VS Code window finishes or asks you something, edgeping always plays a sound. If that window is not on the Space you are looking at, it also shows a colored strip on the edge of the screen, with the name of the project, on the side where that window is.

edgeping is not affiliated with Anthropic.

## What it does

edgeping reacts to three Claude Code events:

- a conversation finishes a turn (`Stop`);
- a conversation asks you to approve a permission (`Notification`, `permission_prompt`);
- a conversation asks you a question (`PreToolUse`, `AskUserQuestion`).

On each event it plays a sound and shows a strip on the edge of the screen. The strip carries a label with the project name. It appears on the left or right edge, according to where the window of that conversation sits among your Spaces. If the window is on the Space you are looking at, no strip is shown.

When a conversation still has subagents running, edgeping stays silent until the last one is done.

## Install

In the terminal:

```
/plugin marketplace add robertoboero/edgeping
/plugin install edgeping@edgeping
```

In the VS Code extension the command is `/plugins` (with an s). It opens the "Manage plugins" window, with the Plugins and Marketplaces tabs. Add the marketplace `robertoboero/edgeping` there, then install `edgeping`.

Set the options from the form that appears after the installation, or from the gear icon on the plugin's row. Open a new conversation afterwards: the plugin does not fire in conversations that were already open when you installed it.

Steps counted in the install test: `TBD-at-test`.

Requirements: macOS, Claude Code 2.1.275 or later. No compiler and no Xcode command line tools are needed: the program is already built (see [The compiled program](#the-compiled-program)).

## Options

| Option | Type | Default | What it does |
|---|---|---|---|
| `sound_enabled` | on/off | on | Play a sound when a conversation finishes or asks you something. |
| `strip_enabled` | on/off | on | Show the strip on the edge of the screen. |
| `sound_done` | choice | `Glass` | Sound when a conversation finishes. One of the macOS system sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink. |
| `sound_question` | choice | `Ping` | Sound when a conversation asks you something. Same list. |
| `color_done` | text | `#D97757` | Strip color for a finished conversation, as `#RRGGBB`. |
| `color_question` | text | `#007AFF` | Strip color when a conversation asks you something, as `#RRGGBB`. |
| `duration_seconds` | number | `10` | How long the strip stays, from 3 to 60 seconds. Ignored when `stay_until_visited` is on. |
| `stay_until_visited` | on/off | off | The strip stays until you visit the window's screen. Details below. |
| `label_enabled` | on/off | on | Show the text label on the strip. |

A value that is not valid is ignored: the default applies and the log records `option-invalid` with the name of the option.

The label text is black or white, whichever has the higher contrast with the color you chose.

### Stay until visited

With `stay_until_visited` on:

- A visit is stopping on the window's screen for about a second. The strip then goes away and does not come back for that conversation.
- While the strip waits, edgeping checks every 5 seconds that the window still exists. If you close the window, the strip goes away and the log records `window-gone`.
- The strips stack along each edge, from the middle of the screen downwards. The number of places on an edge depends on the height of the screen. When the places are over, a new strip is not shown, the sound still plays, and the log records `slots-full`. A strip that has to move to the other edge and finds no place waits hidden.

### When a change applies

Changes apply from the next turn, without reloading.

## Permission

Without the "Screen & System Audio Recording" permission, macOS gives edgeping empty window titles. edgeping then records `empty-titles` in the log and shows no strip. The sound still plays.

Give the permission to the application Claude Code runs from: Visual Studio Code, if you use the extension. Open System Settings → Privacy & Security → Screen & System Audio Recording and switch it on for that application.

After an update of the plugin, whether the permission has to be given again: `TBD-at-test`.

## What it reads, writes and never does

- It reads the event that Claude Code hands to the hook: the working directory (`cwd`), the session identifier and the list of running subagents.
- It reads the titles and the Spaces of the VS Code windows, to find the window of the project.
- It writes a log of one line per outcome in `~/Library/Logs/edgeping/outcomes.log`, readable only by you, with the project name and `cwd`. It does not record the values of your options.
- It keeps a small state in a folder named `edgeping` inside your temporary folder (`$TMPDIR`): one file per strip on screen and the subagent count of each session.
- It makes no network connection.
- It never takes the keyboard focus.

## Limits

- One monitor. With more than one display no strip is shown (`multiple-displays`); the sound still plays.
- Only windows of "Visual Studio Code" are recognised.
- Tested on one Mac: macOS `TBD-at-test`, architecture `TBD-at-test`, Claude Code `TBD-at-test`. Nothing else is claimed to work.
- Linux: planned, not guaranteed.

## Troubleshooting

The log is `~/Library/Logs/edgeping/outcomes.log`. Each line has a time, `outcome=<code>`, and, where known, `event=`, `name=` (the project), `cwd=` and extra fields such as `ms=`.

| Code | Meaning |
|---|---|
| `ok` | The strip was shown. |
| `sound-ok` | The sound started. |
| `sound-failed` | The sound could not be played. |
| `current-space` | The window is on the Space you are looking at: no strip. |
| `empty-titles` | The window titles are empty: give the permission above. No strip. |
| `window-not-found` | No VS Code window matches the project. No strip. |
| `ambiguous-window` | More than one window matches the project. No strip. |
| `multiple-displays` | More than one display. No strip. |
| `probe-failed` | The windows or the Spaces could not be read. |
| `slots-full` | No free place on the edge (`when=new` or `when=move`). |
| `slots-contended` | Another strip was taking places at the same moment. No strip. |
| `slots-unavailable` | The places could not be reserved or read. |
| `window-gone` | The window was closed while the strip waited (`via=` tells how it was noticed). |
| `focus-taken` | The strip became the active application after appearing. It should never happen: report it. |
| `option-invalid` | An option has an invalid value and the default was used (`option=` names it). |
| `invalid-input` | The hook did not receive a valid event on its input. |
| `invalid-arguments` | The program was started with arguments it does not know. |
| `launch-failed` | The sound or the strip process could not be started. |

### Redacting the log before you share it

A log line contains your project names and paths. Before you paste lines into an issue, replace them. A line as it is written:

```
2026-01-15T10:20:30+01:00 outcome=window-not-found event=123456789-4242 cwd=/Users/jane/work/acme-shop
```

The same line, redacted:

```
2026-01-15T10:20:30+01:00 outcome=window-not-found event=123456789-4242 cwd=/Users/you/work/project-a
```

With `name=` present, replace it in the same way (`name=project-a`).

## The compiled program

`dist/edgeping` is a universal binary (Apple Silicon and Intel), signed ad hoc and built from `Sources/` with `bash scripts/build.sh`, which needs the Xcode command line tools. `dist/SOURCES.sha256` lists the hash of every source file the binary was built from.

`bash scripts/check-dist.sh` tells you whether `dist/` is out of date: it detects an old binary, not a different one built from the same sources.

To rebuild, run `bash scripts/build.sh`; to run the tests, `bash scripts/test.sh`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Uninstall

In the VS Code extension, run `/plugins` and remove `edgeping` from the Plugins tab, then the marketplace from the Marketplaces tab. In the terminal: `TBD-at-test`.

Then delete the log folder `~/Library/Logs/edgeping`, and switch off or remove the permission in System Settings → Privacy & Security → Screen & System Audio Recording if you gave it only for this.

## License and author

MIT, see [LICENSE](LICENSE). Security reports: see [SECURITY.md](SECURITY.md).

By [codebeans.it](https://codebeans.it).
