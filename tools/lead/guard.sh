#!/bin/bash
# Lead's guard: (1) logs memory every 20 s so a restart's cause can be read afterwards;
# (2) every 3 min snapshots every helper worktree (committed + uncommitted + new files) to origin
#     wip/auto/<worktree>, through a private index, so no helper's git state is touched.
S="${SPICY_GUARD_DIR:-/tmp/spicy-guard}"; mkdir -p "$S"; R=/home/user/spicy-rodents-roblox; n=0
while true; do
  a=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
  top=$(ps -eo rss,comm --sort=-rss | awk 'NR>1 && NR<5{printf "%s:%dMB ", $2, $1/1024}')
  echo "$(date -u +%FT%TZ) avail=${a}MB load=$(cut -d' ' -f1 /proc/loadavg) $top" >> "$S/mem.log"
  if [ $((n % 9)) -eq 0 ]; then
    for d in "$R"/.claude/worktrees/agent-*; do
      [ -d "$d" ] || continue
      name=$(basename "$d"); (
        cd "$d" || exit
        gd=$(git rev-parse --absolute-git-dir) || exit
        idx=$(mktemp); cp "$gd/index" "$idx" 2>/dev/null
        GIT_INDEX_FILE="$idx" git add -A . >/dev/null 2>&1
        tree=$(GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null); rm -f "$idx"
        [ -n "$tree" ] || exit
        prev=$(cat "$S/guard_$name.prev" 2>/dev/null)
        [ -n "$prev" ] && [ "$(git rev-parse "$prev^{tree}" 2>/dev/null)" = "$tree" ] && [ "$(git rev-parse HEAD)" = "$(cat "$S/guard_$name.head" 2>/dev/null)" ] && exit
        c=$(git commit-tree "$tree" -p HEAD ${prev:+-p "$prev"} -m "auto snapshot of $name ($(git branch --show-current)) $(date -u +%FT%TZ)")
        if git push -q origin "$c:refs/heads/wip/auto/$name" 2>>"$S/guard.err"; then
          echo "$c" > "$S/guard_$name.prev"; git rev-parse HEAD > "$S/guard_$name.head"
          echo "$(date -u +%FT%TZ) snapshot $name $c" >> "$S/guard.log"
        fi
      )
    done
  fi
  n=$((n+1)); sleep 20
done
