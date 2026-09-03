#!/usr/bin/env bash
#
# Golden-file tests for the slide-duration filter.
#
# A case is a directory under tests/cases/ holding `input.qmd`. Rendering it
# produces one capture — exit code, stdout, stderr — which is compared against
# `expected.txt`.
#
# stdout is the pandoc native AST: it shows where the generated `.notes` divs
# landed and that `duration` was stripped from the headers again. stderr carries
# the planned-schedule summary and the abort message for an unparsable
# `duration`.
#
# A case may also hold a `format` file naming the target format the filter should
# believe it is running for; without one it is revealjs. The filter asks
# `quarto.doc.is_format` for it, which plain pandoc does not provide, so cases run
# through quarto-stub.lua, which supplies that one function and then loads the
# filter — no quarto install needed.
#
#   tests/run.sh                  all cases
#   tests/run.sh units invalid-   only cases whose name contains a pattern
#   tests/run.sh --update         rewrite expected.txt from the actual capture
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FILTER="$HERE/../_extensions/slide-duration/slide-duration.lua"

update=0 patterns=()
for arg in "$@"; do
	case "$arg" in
	--update) update=1 ;;
	-*)
		sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
		exit 2
		;;
	*) patterns+=("$arg") ;;
	esac
done

pass=0 fail=0 failed=()

for dir in "$HERE"/cases/*/; do
	dir=${dir%/}
	name=${dir##*/}

	if [[ ${#patterns[@]} -gt 0 ]]; then
		hit=0
		for p in "${patterns[@]}"; do [[ "$name" == *"$p"* ]] && hit=1; done
		[[ $hit == 1 ]] || continue
	fi
	work=$(mktemp -d)
	format=revealjs
	[[ -f "$dir/format" ]] && format=$(cat "$dir/format")

	TEST_FILTER="$FILTER" TEST_FORMAT="$format" pandoc \
		--from=markdown --to=native \
		--lua-filter="$HERE/quarto-stub.lua" "$dir/input.qmd" >"$work/out" 2>"$work/err"
	rc=$?

	{
		printf -- '--- exit %d\n' "$rc"
		printf -- '--- stdout\n'
		cat "$work/out"
		printf -- '--- stderr\n'
		cat "$work/err"
	} | sed -E \
		-e "s#$work#TMP#g" \
		-e "s#$HERE#TESTS#g" >"$work/actual"

	[[ $update == 1 ]] && cp "$work/actual" "$dir/expected.txt"

	if diff -u "$dir/expected.txt" "$work/actual" >"$work/diff" 2>&1; then
		printf 'PASS %s\n' "$name"
		pass=$((pass + 1))
	else
		printf 'FAIL %s\n' "$name"
		sed 's/^/     /' "$work/diff"
		fail=$((fail + 1))
		failed+=("$name")
	fi
	rm -rf "$work"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail == 0 ]] || {
	printf 'failed: %s\n' "${failed[*]}"
	exit 1
}
