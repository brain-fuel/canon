# Sourced first by every corpus script: runs the script in a process group of its own, so that the
# run, its parses, and their timeouts can be stopped together with `kill -- -PGID` without touching
# another run's processes on the same machine, which a broad `pkill -f 'canon parse'` once did.
# The script re-executes itself through perl's setpgrp, since macOS has no setsid command, and
# prints the group to stop. Stopping the script with Ctrl-C or SIGTERM stops its whole group.
if [ "${CORPUS_PROCESS_GROUP:-}" != "$$" ]; then
  export CORPUS_PROCESS_GROUP=$$
  exec perl -e 'setpgrp(0, 0); exec @ARGV or die "exec: $!"' -- "$0" "$@"
fi
printf 'corpus run in process group %s; stop it with: kill -- -%s\n' "$$" "$$" >&2
trap 'trap - INT TERM; kill -TERM -- -$$ 2>/dev/null; exit 143' INT TERM
