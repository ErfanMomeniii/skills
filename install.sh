#!/usr/bin/env bash
#
# Link every skill in this repo into a tool's rules directory.
#
#   ./install.sh claude            → ~/.claude/skills/<topic>-<skill>/
#   ./install.sh cursor            → .cursor/rules/<topic>-<skill>.mdc  (current dir)
#   ./install.sh cursor ~/work/api → that project's .cursor/rules/
#   ./install.sh copilot           → .github/instructions/<topic>-<skill>.instructions.md
#
# Links point back at this repo, so editing a skill here updates every install.
# Re-run any time; existing links are replaced, not duplicated.

set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)

# skills/golang/structure → golang-structure
skill_name() {
	local dir=$1 topic
	topic=${dir%/*}
	printf '%s-%s' "${topic##*/}" "${dir##*/}"
}

link_all() {
	local dest=$1 mode=$2 suffix=${3:-} count=0 file dir name
	mkdir -p "$dest"
	for file in "$root"/skills/*/*/SKILL.md; do
		dir=${file%/SKILL.md}
		name=$(skill_name "$dir")
		if [ "$mode" = dir ]; then
			ln -sfn "$dir" "$dest/$name"
		else
			ln -sfn "$file" "$dest/$name$suffix"
		fi
		count=$((count + 1))
	done
	echo "linked $count skills into $dest"
}

case ${1:-} in
claude)
	link_all "${2:-$HOME/.claude/skills}" dir
	echo "restart the session to pick them up"
	;;
cursor)
	link_all "${2:-.}/.cursor/rules" file .mdc
	;;
copilot)
	link_all "${2:-.}/.github/instructions" file .instructions.md
	;;
*)
	echo "usage: $0 {claude|cursor|copilot} [target-dir]" >&2
	exit 2
	;;
esac
