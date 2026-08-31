# Auto-commit bot for Eka.jl

Commits to `JoshCCorby/Eka.jl` **6–15 times per day** at random hours (07:00–22:00), attributed to:

- **Name:** Joshua Corbett
- **Email:** joshua.c.corbett@icloud.com

## How it works

| Time | Script | Action |
|------|--------|--------|
| 00:05 daily | `reset-daily-quota.sh` | Picks today's target (6–15) |
| Hourly 07–22 | `maybe-commit.sh` | Probabilistically commits until target is met |

Each commit rotates through harmless files:

- `logs/heartbeat.txt` — UTC timestamp
- `logs/activity.log` — appended log line
- `docs/dev-notes.md` — appended working note

## Safety features

- **Lock file** — prevents overlapping commits
- **Dirty-tree guard** — skips if you have uncommitted changes outside bot-managed files
- **Hourly scheduling** — survives Mac sleep better than midnight sleep-jobs

## Install

```bash
~/Coding/Eka/bot/install.sh
```

Or manually:

```bash
chmod +x ~/bin/auto-commit.sh ~/bin/maybe-commit.sh ~/bin/reset-daily-quota.sh
crontab ~/Coding/Eka/bot/crontab.txt
~/bin/reset-daily-quota.sh
```

Ensure SSH push works:

```bash
cat ~/.ssh/id_ed25519_github.pub   # add to GitHub if needed
git -C ~/Coding/Eka remote set-url origin git@github.com:JoshCCorby/Eka.jl.git
```

## Test

```bash
~/bin/auto-commit.sh              # one commit now
~/bin/maybe-commit.sh             # simulate hourly attempt
tail -f ~/logs/auto-commit.log    # watch activity
cat ~/logs/auto-commit-target     # today's target count
cat ~/logs/auto-commit-done       # commits made so far today
```

## Scripts (in `~/bin/`)

| Script | Purpose |
|--------|---------|
| `auto-commit.sh` | Makes one varied commit and pushes |
| `maybe-commit.sh` | Hourly gate — decides whether to commit |
| `reset-daily-quota.sh` | Sets random daily target at midnight |
