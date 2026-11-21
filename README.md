# Jaude

A minimal macOS menu bar gauge for your Claude subscription usage.

The menu bar shows a single icon, no numbers: it shows what is left of your session and your week. It starts full and drains as you use Claude. Four icon styles (bars, level, battery, ring) can be picked from the panel. Click it to see every limit Claude reports (session, week, per-model weekly limits such as Fable), when each one resets, and usage credits when they are enabled.

## How it works

Jaude reads the OAuth token Claude Code stores in your login keychain (`Claude Code-credentials`) and calls the same usage endpoint as `/usage` in Claude Code, every 5 minutes and when you open the panel. Nothing else leaves your Mac. It never refreshes the token itself: if it has expired, opening Claude Code refreshes it.

Requires macOS 26+ and Claude Code logged in with a Pro, Max, Team or Enterprise plan.

## Build

Needs the Xcode Command Line Tools only.

```sh
make install   # builds, signs ad hoc, copies to ~/Applications and launches
make check     # decodes a recorded response and checks the parsing
```

To start it at login, add `~/Applications/Jaude.app` in System Settings > General > Login Items.

## Note

The usage endpoint is undocumented and may change without notice.
