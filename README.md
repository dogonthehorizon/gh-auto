# gh-auto

> [!WARNING]
> This project is vibecoded. It was written with an AI coding agent and has not been closely reviewed by a human operator. Read the code before you run it, and use it at your own risk.

A menu bar app that shows your open GitHub pull requests. It replaces Arc's "Pull Requests" live folder, which broke when GitHub moved `github.com/pulls` to a client-rendered React app.

- Auth comes from the `gh` CLI (`gh auth token`). There is nothing to configure.
- One GraphQL search (`is:pr is:open author:@me archived:false`) per poll.
- Polls every ~2 min via `NSBackgroundActivityScheduler` at utility QoS. Skips polls while the screen is locked or you've been idle for 10+ min. Refreshes on wake, unlock, and menu open.

## Workflow

| Command | What it does |
|---|---|
| `make once` | Build and print your PRs to the terminal (quick check of auth + query) |
| `make run` | Build a dev `gh-auto.app` in the repo and launch it |
| `make publish` | Build → smoke test → swap into `~/Applications` → relaunch → verify |
| `make uninstall` | Quit and remove the installed app |

To change something: edit, run `make once` / `make run`, commit, then `make publish`. Bump `VERSION` for notable changes. The build number and commit are stamped from git, and `-dirty` marks uncommitted builds.

`publish.sh` options: `DEST=/Applications` to install elsewhere, `SKIP_SMOKE=1` to skip the live GitHub check.

Turn on **Launch at Login** from the menu *after* publishing, so macOS registers the `~/Applications` copy. Republishing to the same path keeps that setting.

## Logs

Use the full path; in zsh, `log` is a shell builtin.

```sh
/usr/bin/log show --last 1h --predicate 'subsystem == "com.dogonthehorizon.gh-auto"' --style compact
```

## License

MIT. See [LICENSE](LICENSE).

The menu bar icon is `git-pull-request-16` from [Primer Octicons](https://github.com/primer/octicons), © GitHub Inc., MIT licensed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
