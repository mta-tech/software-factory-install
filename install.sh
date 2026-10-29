#!/bin/sh
# User-local Software Factory bootstrap. Safe to invoke through a pipe.
set -eu
umask 077

repo=${FACTORY_REPOSITORY:-mta-tech/software-factory}
ref=${FACTORY_REF:-v0.4.1}
prefix=${FACTORY_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/herdr-factory}
bin_dir=${FACTORY_BIN_DIR:-$HOME/.local/bin}
source_dir=
install_claude=0
modify_path=1

usage() {
    cat <<'EOF'
Install the Factory CLI with uv-managed Python 3.11.

Usage: sh install.sh [--claude] [--no-modify-path] [--source DIRECTORY]
                    [--prefix DIRECTORY] [--bin-dir DIRECTORY] [--ref REF]

  --claude          Also register and install the bundled Claude Code plugin.
  --no-modify-path  Do not append a PATH entry to shell startup files.
  --source DIR      Install from an existing checkout instead of GitHub.

Remote installs require GitHub CLI authentication with repository access.
Git and SSH must already be installed. uv is installed if unavailable.
VPN, SSH aliases, credentials, and Factory run state are left unchanged.
EOF
}

fail() { printf 'factory installer: %s\n' "$*" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --claude) install_claude=1; shift ;;
        --no-modify-path) modify_path=0; shift ;;
        --source|--prefix|--bin-dir|--ref)
            [ "$#" -ge 2 ] || fail "$1 needs a value"
            case "$1" in
                --source) source_dir=$2 ;;
                --prefix) prefix=$2 ;;
                --bin-dir) bin_dir=$2 ;;
                --ref) ref=$2 ;;
            esac
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown option: $1" ;;
    esac
done

case "$(uname -s)" in Darwin|Linux) ;; *) fail 'macOS or Linux is required' ;; esac
for command in git ssh curl; do
    command -v "$command" >/dev/null 2>&1 || fail "install $command first"
done
if [ "$install_claude" -eq 1 ]; then
    command -v claude >/dev/null 2>&1 || fail 'install Claude Code before using --claude'
fi
case "$prefix" in /*) ;; *) fail 'installation directory must be absolute' ;; esac
case "$bin_dir" in /*) ;; *) fail 'binary directory must be absolute' ;; esac
[ ! -L "$prefix" ] || fail 'installation directory must not be a symlink'
[ ! -L "$bin_dir" ] || fail 'binary directory must not be a symlink'
case "$repo" in *[!a-zA-Z0-9_./-]*|'') fail 'invalid repository' ;; esac
case "$ref" in *[!a-zA-Z0-9_./-]*|*..*|'') fail 'invalid ref' ;; esac
if [ -z "$source_dir" ]; then
    command -v gh >/dev/null 2>&1 || fail 'install GitHub CLI and run gh auth login first'
    gh auth status >/dev/null 2>&1 || fail 'run gh auth login with repository access first'
else
    [ -d "$source_dir" ] || fail 'source checkout does not exist'
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/factory-install.XXXXXXXX")
trap 'rm -rf "$temporary"' EXIT
trap 'exit 130' HUP INT TERM
if command -v uv >/dev/null 2>&1; then
    uv_command=$(command -v uv)
elif [ -x "$bin_dir/uv" ]; then
    uv_command=$bin_dir/uv
else
    mkdir -p "$bin_dir"
    curl -fsSL https://astral.sh/uv/install.sh -o "$temporary/uv-install.sh"
    UV_INSTALL_DIR="$bin_dir" UV_NO_MODIFY_PATH=1 sh "$temporary/uv-install.sh" </dev/null
    uv_command=$bin_dir/uv
fi
"$uv_command" python install --no-bin 3.11 </dev/null
python_command=$("$uv_command" python find --no-project --managed-python 3.11)
[ -x "$python_command" ] || fail 'uv did not return an executable Python interpreter'

if [ -z "$source_dir" ]; then
    commit=$(gh api "repos/$repo/commits/$ref" --jq .sha </dev/null)
    [ "${#commit}" -eq 40 ] || fail 'GitHub did not return a commit identity'
    case "$commit" in *[!a-f0-9]*) fail 'invalid commit identity' ;; esac
    gh api "repos/$repo/tarball/$commit" > "$temporary/source.tar.gz" </dev/null
    "$python_command" - "$temporary" <<'PY'
from pathlib import Path, PurePosixPath
import tarfile
import sys

root = Path(sys.argv[1])
with tarfile.open(root / 'source.tar.gz') as archive:
    members = archive.getmembers()
    if not members or len(members) > 20000 or sum(m.size for m in members) > 128 * 1024 * 1024:
        raise SystemExit('Factory source archive exceeds installation limits')
    tops = set()
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not path.parts or not (member.isfile() or member.isdir()):
            raise SystemExit('Unsupported source archive entry')
        tops.add(path.parts[0])
    if len(tops) != 1:
        raise SystemExit('Source archive must contain one directory')
    archive.extractall(root / 'unpacked', filter='data')
    (root / 'source-path').write_text(str(root / 'unpacked' / tops.pop()))
PY
    source_dir=$(cat "$temporary/source-path")
fi
[ -f "$source_dir/scripts/install_factory.py" ] || fail 'selected source does not contain the Factory installer'
"$python_command" "$source_dir/scripts/install_factory.py" \
    --source "$source_dir" --prefix "$prefix" --bin-dir "$bin_dir" \
    --claude "$install_claude" --modify-path "$modify_path" </dev/null
