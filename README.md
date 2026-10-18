**English** | [Русский](README.ru.md)

# Safety AI

A macOS menu bar toggle that stops [Claude Code](https://claude.com/claude-code) from committing.

Turn isolation mode on and the agent keeps editing code, but it won't `commit`, `push`, `merge`, `rebase`, tag
or open MRs in any repository, and it stops asking "should I commit?". All changes stay in the working tree.
Turn it off and Claude behaves as usual.

## Install

Requires macOS 13+, Command Line Tools (`xcode-select --install`) and `jq` (bundled with macOS 15+).

```bash
git clone <repo> && cd safety-ai
./install.sh
```

The script:
1. copies the hook to `~/.claude/hooks/isolation.sh` and registers it in `~/.claude/settings.json`
   (the previous file is saved as `settings.json.bak-isolation`);
2. builds `~/Applications/Safety AI.app`;
3. adds a login item (`~/Library/LaunchAgents/local.safety-ai.plist`) and launches the app.

Re-running is safe: the hook is not registered twice, the app is rebuilt.

## Usage

A lock appears on the right side of the menu bar:
- 🔒 closed: isolation is on, commits are blocked;
- 🔓 open: isolation is off.

Click the lock → "Isolation mode". It takes effect immediately, including in Claude sessions that are already open.

Same from a terminal:
```bash
touch ~/.claude/isolation   # on
rm ~/.claude/isolation      # off
```

## How it works

The whole state is one flag file, `~/.claude/isolation`. The app creates and deletes it, the hook reads it.

- **`PreToolUse`**: before every Claude tool call the hook checks the flag. If it is set, it blocks
  `git commit/push/merge/rebase/cherry-pick/am/tag` via Bash and `add_commit`, `add_branch`,
  `save_merge_request`, `accept_merge_request` via GitLab MCP. Read-only commands (`git status`, `diff`, `log`) pass.
- **`UserPromptSubmit`**: every user message gets a reminder "don't commit and don't ask about committing".
  Without it the agent would keep offering to commit.
- While isolation is on, Claude cannot remove the flag: commands that mention it are blocked.

```
app/main.swift       menu bar app (AppKit, no dependencies)
app/*.lproj/         UI translations
hooks/isolation.sh   Claude Code hook
install.sh           install
uninstall.sh         uninstall
```

## Languages

The app follows the macOS language setting (System Settings → General → Language & Region,
or per app via Applications → Safety AI). Bundled: English, Russian.

To add a language, copy `app/en.lproj` to `app/<code>.lproj` (e.g. `de.lproj`), translate the right-hand
strings in `Localizable.strings` and run `./install.sh` again. Pull requests with translations are welcome.

## Limitations

- This guards against accidental commits, it is not a sandbox: an agent deliberately looking for a bypass will find one.
- The hook does not see git run through third-party MCP terminals (e.g. PhpStorm `execute_terminal_command`).
- The "Commit" button in Claude desktop is drawn by the app itself. Pressing it while isolation is on hits the hook.

## Uninstall

```bash
./uninstall.sh
```

Removes the app, the login item, the hook, the flag and the hook entries in `settings.json`
(backup: `settings.json.bak-uninstall`).

## License

[MIT](LICENSE)
