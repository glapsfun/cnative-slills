# Portability: POSIX sh and GNU-vs-BSD (macOS)

Portability bugs come from two directions: **shell features** that exist in bash but not in `/bin/sh`, and **external tools** whose flags differ between GNU (Linux) and BSD (macOS) userlands. Decide your target first, then write to it. Use the [POSIX.1-2024 Shell Command Language](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html) as the canonical Issue 8 reference.

## Contents

- [When to target POSIX `sh`](#when-to-target-posix-sh)
- [Bash features that are NOT in POSIX sh](#bash-features-that-are-not-in-posix-sh)
- [GNU vs BSD: same command, different flags](#gnu-vs-bsd-same-command-different-flags)
- [macOS bash is ancient](#macos-bash-is-ancient)
- [Quick portability checklist](#quick-portability-checklist)

## When to target POSIX `sh`

Reach for `#!/bin/sh` only when portability is a real requirement:

- Alpine / minimal container images where `sh` is BusyBox or dash and bash isn't installed.
- BSD base systems, embedded systems, init/boot scripts.
- Scripts that must run "anywhere" with no dependency on a bash install.

Otherwise prefer `#!/usr/bin/env bash` — the extra features (arrays, `[[ ]]`, `local`) prevent more bugs than POSIX-purity buys you. **Verify portability with `checkbashisms script.sh` or `shellcheck -s sh script.sh`**, which flag bash-only constructs in an `sh` script.

## Bash features that are NOT in POSIX sh

If the shebang is `#!/bin/sh`, avoid all of these:

| Bash-only | POSIX alternative |
|-----------|-------------------|
| `[[ ... ]]` | `[ ... ]` (quote operands, use `=` not `==`) |
| Arrays `arr=(...)`, `"${arr[@]}"` | Positional params `set -- a b c`; or newline-separated strings |
| `local var` | Not standardized; many `sh` support it, dash does. Avoid relying on it. |
| `${var^^}` / `${var,,}` (case) | `tr '[:lower:]' '[:upper:]'` |
| `function name { }` | `name() { }` |
| `source file` | `. file` (dot) |
| `<<<"$x"` here-strings | `printf '%s' "$x" \| cmd` |
| `<(...)` process substitution | Temp file via `mktemp`, or a pipe |
| `${var/old/new}` substitution | `sed` / `${var%...}`+`${var#...}` |
| `read -a` | Loop with `IFS` and `set --` |
| C-style `for ((i=0;...))` | `while [ "$i" -le "$n" ]` with `i=$((i+1))` |
| `&>` / `>&` redirect both | `>file 2>&1` |
| `echo -e` / `-n` (unreliable even in bash) | `printf` |
| `printf '%q'` | No portable shell-escaping formatter; print a fixed label and each argument as data |

POSIX.1-2024 Issue 8 standardizes `set -o pipefail`, but many deployed `/bin/sh` implementations predate or omit it, including dash versions. Probe in an `if` condition so an unsupported option does not trigger `set -e`:

```sh
if (set -o pipefail) 2>/dev/null; then
  set -o pipefail
fi
```

An unsupported shell continues without `pipefail`; restructure pipelines so each stage's status is checked, or exit explicitly when `pipefail` is required.

A safe POSIX header:

```sh
#!/bin/sh
set -eu
```

Do not change `IFS` globally: that affects every later split and any caller that sources the file. Quote expansions, and scope `IFS` to the individual command that needs it, such as `IFS= read -r line`.

## GNU vs BSD: same command, different flags

macOS ships BSD versions of core utilities; Linux ships GNU (coreutils). Scripts written against GNU flags break on macOS and vice versa. The biggest offenders:

| Task | GNU (Linux) | BSD (macOS) | Portable approach |
|------|-------------|-------------|-------------------|
| In-place sed | `sed -i 's/a/b/' f` | `sed -i '' 's/a/b/' f` | Write to temp + `mv`, or branch on OS |
| `sed -E` regex | `-E` (also `-r`) | `-E` | Use `-E` (works on both); avoid GNU-only `-r` |
| `date` math | `date -d '+1 day'` | `date -v+1d` | `date` differs entirely; consider `python3`/`perl` |
| Epoch to date | `date -d @1700000000` | `date -r 1700000000` | branch on OS |
| `readlink -f` | yes | available on modern macOS; older macOS and other BSDs may lack it | Capability-detect; fall back to `realpath`, a loop, Python, or optional `greadlink` |
| `stat` format | `stat -c '%s' f` | `stat -f '%z' f` | branch, or `wc -c < f` for size |
| `grep -P` (PCRE) | yes | no | use `-E` (ERE) instead |
| `mktemp` | accepts a template | needs a template on some BSDs | `mktemp -d "${TMPDIR:-/tmp}/script-name.XXXXXX"` |
| `xargs -r` | yes | no `-r` | `find … -exec command {} +` safely skips execution on empty input |
| `cp --preserve` | long flags | short `-p` only | use `cp -p` |
| `base64 -w0` | wrap control | no `-w` | pipe through `tr -d '\n'` |
| `getopt` (enhanced) | util-linux | BSD getopt differs | use the shell builtin `getopts` instead |

Detect the platform when you must branch:

```bash
case "$(uname -s)" in
  Linux)  sed_inplace() { sed -i "$@"; } ;;
  Darwin) sed_inplace() { sed -i '' "$@"; } ;;
  *)      die "unsupported OS: $(uname -s)" ;;
esac
```

A pragmatic alternative on developer machines: install GNU coreutils via Homebrew (`brew install coreutils gnu-sed`) and use the `g`-prefixed tools (`gsed`, `gdate`, `greadlink`) for consistent behavior — but don't assume they're present in scripts you ship to others. Prefer capability detection over branching only on the OS name because utility support changes across releases.

## macOS bash is ancient

`/bin/bash` on macOS is **3.2** (frozen for licensing reasons). Anything requiring bash 4+ — associative arrays, `${var^^}` case conversion, `mapfile`/`readarray`, `wait -n`, `;;&` in case — will fail there. A modern bash usually lives at `/opt/homebrew/bin/bash` or `/usr/local/bin/bash`. `#!/usr/bin/env bash` finds whichever is first on `PATH`, which is why it's preferred over `#!/bin/bash`.

Gate features that need a newer bash:

```bash
if (( BASH_VERSINFO[0] < 4 )); then
  die "this script requires bash 4+ (found ${BASH_VERSION}); on macOS: brew install bash"
fi
```

## Quick portability checklist

- Shebang matches the target (`bash` vs `sh`), and the syntax matches the shebang.
- Ran `shellcheck -s sh` or `checkbashisms` for any `#!/bin/sh` script.
- Verified whether the deployed shell supports Issue 8 `pipefail`, or restructured pipelines to check each stage.
- No GNU-only flags if the script must run on macOS/BSD (or it branches on `uname`).
- No bash-4+ features if it must run on stock macOS bash (or it version-gates).
- `printf` instead of `echo -e/-n`; `$(...)` instead of backticks.
