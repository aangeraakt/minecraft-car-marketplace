#!/bin/bash
# The car review bot. Decides: approve+merge / ask a human / request changes.
set -uo pipefail
MARK="<!-- car-review-bot -->"
work=$(mktemp -d)

pr_json=$(gh pr view "$PR" -R "$REPO" --json number,author,headRefOid,headRepository,headRepositoryOwner,state,files)
state=$(jq -r .state <<<"$pr_json")
author=$(jq -r .author.login <<<"$pr_json")
head_sha=$(jq -r .headRefOid <<<"$pr_json")
head_repo="$(jq -r .headRepositoryOwner.login <<<"$pr_json")/$(jq -r .headRepository.name <<<"$pr_json")"
[ "$state" = "OPEN" ] || { echo "PR is $state, nothing to do"; exit 0; }

gh label create "auto-approved" -R "$REPO" --color 2ea44f --description "Passed every car check" --force >/dev/null 2>&1 || true
gh label create "needs-human-review" -R "$REPO" --color fbca04 --description "The bot is not sure" --force >/dev/null 2>&1 || true
gh label create "changes-requested" -R "$REPO" --color d73a4a --description "A car check failed" --force >/dev/null 2>&1 || true

comment() {  # one bot comment per PR, updated on every run
  local body="$MARK"$'\n'"$1"
  local id
  id=$(gh api "repos/$REPO/issues/$PR/comments" --paginate --jq ".[] | select(.body | startswith(\"$MARK\")) | .id" | tail -1)
  if [ -n "$id" ]; then gh api -X PATCH "repos/$REPO/issues/comments/$id" -f body="$body" >/dev/null
  else gh pr comment "$PR" -R "$REPO" --body "$body" >/dev/null; fi
}
label() {
  for l in auto-approved needs-human-review changes-requested; do gh pr edit "$PR" -R "$REPO" --remove-label "$l" >/dev/null 2>&1 || true; done
  gh pr edit "$PR" -R "$REPO" --add-label "$1" >/dev/null
}
human() { comment "## Car check"$'\n\n'"**A human will review this:** $1"; label needs-human-review; exit 0; }

# 1. only one car folder, only the three car files, nothing deleted
files=$(jq -r '.files[] | "\(.path)\t\(.additions)\t\(.deletions)"' <<<"$pr_json")
ids=$(jq -r '.files[].path' <<<"$pr_json" | awk -F/ '$1=="cars"{print $2}' | sort -u)
while IFS=$'\t' read -r path add del; do
  [[ "$path" =~ ^cars/[a-z0-9_]{1,64}/(car\.bmwcar|thumbnail\.png|meta\.json)$ ]] || human "the pull request changes \`$path\`, which is not a car file. Only car folders can be approved automatically."
done <<<"$files"
[ "$(wc -l <<<"$ids")" -eq 1 ] && [ -n "$ids" ] || human "the pull request touches more than one car folder."
id="$ids"

# 2. download the car files from the pull request (as data)
mkdir -p "$work/car"
for f in car.bmwcar thumbnail.png meta.json; do
  if ! gh api -H "Accept: application/vnd.github.raw" "repos/$head_repo/contents/cars/$id/$f?ref=$head_sha" > "$work/car/$f"; then
    human "could not download \`cars/$id/$f\` from the pull request."
  fi
done

# 3. run the checks (the mod's own importer)
java -Xmx3g -jar tools/car-validator.jar "$work/car" "$id" "$author" index.json "$work/report.json" "$work/report.md" || true
[ -s "$work/report.json" ] || human "the checker could not run."
verdict=$(jq -r .verdict "$work/report.json")
report=$(cat "$work/report.md")
echo "verdict: $verdict"

if [ "$DRY_RUN" = "true" ]; then
  comment "$report"$'\n\n'"*(dry run: no approval or merge, verdict would be **$verdict**)*"
  exit 0
fi

case "$verdict" in
  approve)
    comment "$report"
    label auto-approved
    gh pr review "$PR" -R "$REPO" --approve --body "All car checks passed." || human "every check passed, but the bot is not allowed to approve. Enable *Settings > Actions > General > Allow GitHub Actions to create and approve pull requests*."
    if ! gh pr merge "$PR" -R "$REPO" --squash --subject "Add car: $id (auto-approved)"; then
      human "every check passed but merging failed (conflict?)."
    fi
    # merges made by the bot do not start other workflows: rebuild the car list here
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    for try in 1 2 3 4 5; do   # another merge may land at the same moment: rebuild on the newest main and retry
      git fetch -q origin main && git checkout -q -B main origin/main
      python .github/scripts/build_index.py --write || break
      git diff --quiet index.json && break
      git add index.json && git commit -q -m "Update index.json ($id)"
      git push -q origin main && break
      sleep $((try * 5))
    done
    ;;
  human)
    comment "$report"
    label needs-human-review
    ;;
  *)
    comment "$report"
    label changes-requested
    gh pr review "$PR" -R "$REPO" --request-changes --body "Some car checks failed, see the bot comment." >/dev/null 2>&1 || true
    ;;
esac
