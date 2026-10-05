# Contributing to Island

Thanks for helping improve Island. Bug reports, small fixes, and focused feature
proposals are welcome.

## Before you start

Island targets Omarchy 4 and runs inside its Quickshell shell. Use a current
Omarchy installation for visual and runtime checks. The root `manifest.json`
defines the bar plugin; `companion/lanta.notifications/` contains the
separate notification service. Keep their IDs and entry points consistent with
the QML and shell commands that refer to them.

For a bug report, include the Omarchy version, the steps to reproduce, what you
expected, and what happened. Screenshots or short recordings help with visual
issues. Remove personal information from logs and screenshots before posting.

## Making a change

1. For broad changes to installation, removal, or user configuration, discuss
   the approach in an issue first.
2. Keep each pull request focused. Explain the behavior change and any new
   commands or dependencies.
3. Preserve user settings and local changes. When editing `shell.json` or menu
   overrides, keep unrelated entries intact and provide a clear removal path.
4. Do not edit Omarchy's packaged files under `/usr/share/omarchy/`. Use them as
   a reference only.

Anything that shells out to an `omarchy-*` helper should ask
`host.hasHelper("omarchy-thing")` first and hide, disable or explain itself when
the helper is missing, so Island on an older Omarchy degrades instead of
offering controls that do nothing. The probe and the list of names live in
`Island.qml`.

The main UI is in `Island.qml`, `components/`, and `views/`. Every animation
takes its duration and easing from the motion tokens on the island root (the
Motion block in `Island.qml`) instead of hard-coded values, so the whole plugin
keeps one tempo and one easing family; add a token there if none of the existing
roles fit. Companion setup and removal live in `companion/`. Update the README
when a user-facing action, dependency, or configuration path changes.

## Checking your work

From the repository root, run:

Turn the checks on as a commit hook, once per clone:

```sh
git config core.hooksPath githooks
```

After that `tests/checks.sh` runs before every commit and a red one blocks
it. `git commit --no-verify` bypasses it; say why if you use it.

```sh
bash tests/checks.sh
omarchy plugin validate .
omarchy plugin validate companion/lanta.notifications
```

Recording the demo video is `tests/demo.sh`: it backs up and clears the
notification and clipboard history, generates a neutral file to drag, and fires
the few events that have to land on a timeline while a person records. It never
starts a recorder, it only writes under `ISLAND_DEMO_DIR` (default
`/tmp/island-demo`), and it puts everything back on `cleanup` or when a run is
interrupted. See `tests/demo.sh` with no arguments for the subcommands.

On a machine with Omarchy running, `bash tests/smoke.sh` restarts the shell
and checks that the island came back: its layer is on screen, the IPC target
answers, and the journal has no warnings from this shell instance. That is the
rule above turned into one command.

`tests/checks.sh` runs everything that does not need an Omarchy session: bash
syntax, shellcheck, the manifests as JSON, whitespace, `qmllint` over every QML
file, and `tests/run.sh`. A tool that is not installed is reported and skipped
rather than failing the run, so it is useful on a fresh checkout. The two
`omarchy plugin validate` calls do need Omarchy, which is why they are separate.

`tests/run.sh` needs nothing but bash, jq and perl. It covers the JSONC menu
edit and the backup rotation, and it runs `companion/install.sh` twice against a
throwaway `HOME` with the Omarchy commands stubbed out, so a second run is
proven not to touch anything.

For a QML change, confirm the plugin actually loaded after restarting the shell
(`hyprctl layers` should list a layer named `omarchy-island`). Omarchy falls back
to its own bar, and disables the plugin, when one of its files fails to load --
and the only clue is a `bar option lanta.island failed to load` warning in the
journal. A missing import is enough: a view that uses `Process` needs
`import Quickshell.Io`.

For visual changes, check the affected views in a running Omarchy session and
include a screenshot in the pull request. For setup or removal changes, test a
fresh install, a repeat run, and `companion/uninstall.sh --dry-run`. Confirm that
unrelated user configuration survives. Do not run destructive setup or removal
checks against a session with changes you cannot restore.

In the pull request, summarize what changed, how you checked it, and any known
limitations. Do not include credentials, notification history, or other personal
state in fixtures or screenshots.
