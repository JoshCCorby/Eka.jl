#!/usr/bin/env bash
set -euo pipefail

BIN="$HOME/bin"
LOG="$HOME/logs"
REPO="$HOME/Coding/Eka"

echo "==> Eka.jl auto-commit bot install"

mkdir -p "$BIN" "$LOG"

chmod +x \
  "$BIN/auto-commit.sh" \
  "$BIN/maybe-commit.sh" \
  "$BIN/reset-daily-quota.sh"

# Initialise today's quota immediately
"$BIN/reset-daily-quota.sh"

# Install cron schedule
crontab "$REPO/bot/crontab.txt"
echo "Installed crontab:"
crontab -l

echo
echo "==> Next steps"
echo "1. Ensure SSH key is on GitHub:"
echo "   cat ~/.ssh/id_ed25519_github.pub"
echo
echo "2. Test one commit:"
echo "   $BIN/auto-commit.sh"
echo
echo "3. Watch the log:"
echo "   tail -f $LOG/auto-commit.log"
echo
echo "Target for today: $(cat "$LOG/auto-commit-target") commits"
