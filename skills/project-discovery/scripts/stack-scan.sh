#!/usr/bin/env bash
# stack-scan.sh: deterministic helpers for mode detection and project discovery.
#
#   stack-scan.sh mode [DIR]                 Suggest the run mode for DIR.
#   stack-scan.sh fingerprint [DIR]          Print the fingerprint of DIR's stack-defining files.
#   stack-scan.sh write PROFILE [DIR]        Replace the fingerprint block in PROFILE.
#   stack-scan.sh check PROFILE [DIR]        Compare DIR with the fingerprint stored in PROFILE.
#
# DIR defaults to the current directory. Output is plain text, one fact per line.
# Exit codes: 0 ok, 2 usage or input error. Works with macOS bash 3.2.

set -euo pipefail
export LC_ALL=C

BEGIN_MARK='<!-- fingerprint:begin -->'
END_MARK='<!-- fingerprint:end -->'
TAB=$'\t'

die() { echo "error: $*" >&2; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/stack-scan.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -c1-12
  else shasum -a 256 | cut -c1-12; fi
}

# Paths never considered: dependencies, virtualenvs, team state, test fixtures.
excluded() {
  case "/$1" in
    */node_modules/*|*/vendor/*|*/.venv/*|*/venv/*|*/.team/*|*/.git/*|*/third_party/*|*/testdata/*|*/fixtures/*|*/__fixtures__/*) return 0 ;;
  esac
  return 1
}

# Print the category of a stack-defining file, or fail if the file is not one.
category() {
  local p="$1" b="${1##*/}"
  case "$p" in
    .github/workflows/*|.gitlab-ci.yml|.circleci/*|azure-pipelines.yml|Jenkinsfile|bitbucket-pipelines.yml|.buildkite/*|.woodpecker.yml|.woodpecker/*)
      echo ci; return 0 ;;
  esac
  case "$b" in
    package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lock|bun.lockb|deno.lock|poetry.lock|uv.lock|Pipfile.lock|pdm.lock|go.sum|Cargo.lock|Gemfile.lock|composer.lock|mix.lock|Package.resolved|Podfile.lock|pubspec.lock|packages.lock.json|gradle.lockfile|flake.lock)
      echo lock ;;
    package.json|pnpm-workspace.yaml|pyproject.toml|setup.py|setup.cfg|requirements*.txt|Pipfile|go.mod|go.work|Cargo.toml|pom.xml|build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts|libs.versions.toml|*.csproj|*.fsproj|*.vbproj|*.sln|Directory.Build.props|Directory.Packages.props|Gemfile|*.gemspec|composer.json|mix.exs|Package.swift|Podfile|project.pbxproj|pubspec.yaml|deno.json|deno.jsonc|vcpkg.json|conanfile.txt|conanfile.py|build.sbt)
      echo manifest ;;
    .nvmrc|.node-version|.python-version|.ruby-version|.tool-versions|mise.toml|.mise.toml|rust-toolchain|rust-toolchain.toml|global.json|gradle-wrapper.properties|flake.nix|.sdkmanrc|.java-version)
      echo toolchain ;;
    Makefile|GNUmakefile|justfile|Justfile|Taskfile.yml|Taskfile.yaml|CMakeLists.txt|meson.build|turbo.json|nx.json|lerna.json|tsconfig.json|tsconfig.*.json|Dockerfile|Dockerfile.*|*.dockerfile|docker-compose*.yml|docker-compose*.yaml|compose.yml|compose.yaml|Procfile|tox.ini|noxfile.py|pytest.ini|conftest.py|vite.config.*|webpack.config.*|jest.config.*|vitest.config.*|playwright.config.*|cypress.config.*|karma.conf.*|phpunit.xml|phpunit.xml.dist|.env.example)
      echo build ;;
    .eslintrc|.eslintrc.*|eslint.config.*|.prettierrc|.prettierrc.*|prettier.config.*|biome.json|biome.jsonc|ruff.toml|.ruff.toml|.flake8|mypy.ini|.golangci.yml|.golangci.yaml|.rubocop.yml|.pre-commit-config.yaml|.stylelintrc|.stylelintrc.*|rustfmt.toml|.rustfmt.toml|clippy.toml|.swiftlint.yml|.swiftformat|analysis_options.yaml|detekt.yml|.scalafmt.conf|.php-cs-fixer.php|.php-cs-fixer.dist.php)
      echo lint ;;
    *) return 1 ;;
  esac
}

# Files that still count as an empty (greenfield) directory: docs, notes, licenses, editor config.
greenfield_ok() {
  local b="${1##*/}"
  case "$1" in .claude/*|.vscode/*|.idea/*|.github/ISSUE_TEMPLATE/*) return 0 ;; esac
  case "$b" in
    README*|LICENSE*|LICENCE*|COPYING*|NOTICE*|CHANGELOG*|CONTRIBUTING*|CODE_OF_CONDUCT*|SECURITY*|.gitignore|.gitattributes|.editorconfig|.DS_Store|*.md|*.txt|*.pdf|*.docx|*.rtf|*.png|*.jpg|*.jpeg|*.svg) return 0 ;;
  esac
  return 1
}

is_git() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# NUL-separated list of candidate files, relative to DIR.
list_files() {
  local dir="$1"
  if is_git "$dir"; then
    git -C "$dir" ls-files -z -co --exclude-standard
  else
    (cd "$dir" && find . -maxdepth 8 \( -name .git -o -name node_modules -o -name .venv -o -name venv -o -name .team \) -prune -o -type f -print0)
  fi
}

# Sorted lines: <category> TAB <hash> TAB <path>
fingerprint_lines() {
  local dir="$1" p c h
  while IFS= read -r -d '' p; do
    p="${p#./}"
    [ -f "$dir/$p" ] || continue
    excluded "$p" && continue
    c=$(category "$p") || continue
    h=$(hash_stdin < "$dir/$p")
    printf '%s\t%s\t%s\n' "$c" "$h" "$p"
  done < <(list_files "$dir") | sort -t "$TAB" -k3,3
}

cmd_fingerprint() {
  local dir="$1" lines
  lines=$(fingerprint_lines "$dir")
  echo "fingerprint v1"
  [ -n "$lines" ] && printf '%s\n' "$lines"
  echo "total${TAB}$(printf '%s\n' "$lines" | hash_stdin)"
}

stored_lines() {
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" 'index($0,b){f=1;next} index($0,e){f=0} f' "$1" \
    | grep -v -e '^```' -e '^fingerprint v' -e '^total' -e '^[[:space:]]*$' || true
}

cmd_write() {
  local profile="$1" dir="$2" n
  [ -f "$profile" ] || die "no profile at $profile"
  grep -qF "$BEGIN_MARK" "$profile" && grep -qF "$END_MARK" "$profile" || die "fingerprint markers missing in $profile"
  cmd_fingerprint "$dir" > "$TMP/block"
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v blk="$TMP/block" '
    index($0,b) { print; print "```text"; while ((getline l < blk) > 0) print l; print "```"; skip=1; next }
    index($0,e) { skip=0 }
    !skip { print }' "$profile" > "$TMP/profile"
  cat "$TMP/profile" > "$profile"
  n=$(grep -c "$TAB" "$TMP/block" || true)
  echo "wrote fingerprint: $((n - 1)) files, $(tail -n 1 "$TMP/block" | tr '\t' ' ')"
}

# Prints: status, areas, then one line per difference: <added|removed|changed> TAB <category> TAB <path>
cmd_check() {
  local profile="$1" dir="$2" diffs
  if [ ! -f "$profile" ]; then echo "status: missing"; echo "reason: no profile at $profile"; return 0; fi
  stored_lines "$profile" > "$TMP/old"
  if [ ! -s "$TMP/old" ]; then echo "status: missing"; echo "reason: profile has no fingerprint"; return 0; fi
  fingerprint_lines "$dir" > "$TMP/new"
  diffs=$(awk -F '\t' '
    NR==FNR { oc[$3]=$1; oh[$3]=$2; next }
    { nc[$3]=$1; nh[$3]=$2 }
    END {
      for (p in nc) {
        if (!(p in oc)) print "added\t" nc[p] "\t" p
        else if (nh[p] != oh[p]) print "changed\t" nc[p] "\t" p
      }
      for (p in oc) if (!(p in nc)) print "removed\t" oc[p] "\t" p
    }' "$TMP/old" "$TMP/new" | sort -t "$TAB" -k3,3)
  if [ -z "$diffs" ]; then echo "status: fresh"; return 0; fi
  if printf '%s\n' "$diffs" | grep -qE "^(added|removed)${TAB}manifest${TAB}[^/]+\$"; then
    echo "status: layout"
  elif ! printf '%s\n' "$diffs" | grep -qvE "^changed${TAB}lock${TAB}"; then
    echo "status: lock-only"
  else
    echo "status: stale"
  fi
  echo "areas: $(printf '%s\n' "$diffs" | cut -f2 | sort -u | tr '\n' ' ' | sed 's/ $//')"
  printf '%s\n' "$diffs"
}

git_state() {
  local dir="$1" top
  if ! is_git "$dir"; then echo "none"; return; fi
  top=$(git -C "$dir" rev-parse --show-toplevel)
  if [ "$(cd "$top" && pwd -P)" != "$(cd "$dir" && pwd -P)" ]; then echo "parent-repo $top"; return; fi
  if ! git -C "$dir" rev-parse --verify -q HEAD >/dev/null; then echo "no-commits"; return; fi
  echo "ok"
}

profile_status() {
  awk -F '|' '{ k=$2; gsub(/[ `*]/,"",k) } k=="Status" { v=$3; gsub(/[ `*]/,"",v); print v; exit }' "$1"
}

cmd_mode() {
  local dir="$1" profile="$1/.team/project-profile.md" st p c manifests=0 others=0
  echo "git: $(git_state "$dir")"
  if [ -f "$profile" ]; then
    st=$(profile_status "$profile")
    echo "profile: $st"
    case "$st" in
      verified) echo "mode: established"; cmd_check "$profile" "$dir" ;;
      planned)  echo "mode: greenfield"; echo "reason: stack approved, walking skeleton (M0) not yet verified" ;;
      draft)    echo "mode: resume"; echo "reason: profile drafted but not approved at Gate 0; resume the open run or re-run discovery" ;;
      *)        echo "mode: ambiguous"; echo "reason: unknown profile status '$st'" ;;
    esac
    return 0
  fi
  echo "profile: none"
  : > "$TMP/manifests"; : > "$TMP/others"
  while IFS= read -r -d '' p; do
    p="${p#./}"
    excluded "$p" && continue
    c=$(category "$p" || true)
    if [ "$c" = manifest ]; then echo "$p" >> "$TMP/manifests"
    elif ! greenfield_ok "$p"; then echo "$p" >> "$TMP/others"; fi
  done < <(list_files "$dir")
  manifests=$(wc -l < "$TMP/manifests" | tr -d ' ')
  others=$(wc -l < "$TMP/others" | tr -d ' ')
  if [ "$manifests" -gt 0 ]; then
    echo "mode: brownfield"
    echo "reason: $manifests build manifest(s): $(head -n 5 "$TMP/manifests" | tr '\n' ' ' | sed 's/ $//')"
  elif [ "$others" -eq 0 ]; then
    echo "mode: greenfield"
    echo "reason: no source code or build manifest"
  else
    echo "mode: ambiguous"
    echo "reason: $others file(s) that are not docs, but no build manifest"
    head -n 10 "$TMP/others" | sed 's/^/file: /'
  fi
}

sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  mode)        cmd_mode "${1:-.}" ;;
  fingerprint) cmd_fingerprint "${1:-.}" ;;
  write)       [ $# -ge 1 ] || die "usage: stack-scan.sh write PROFILE [DIR]"; cmd_write "$1" "${2:-.}" ;;
  check)       [ $# -ge 1 ] || die "usage: stack-scan.sh check PROFILE [DIR]"; cmd_check "$1" "${2:-.}" ;;
  *)           sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; [ -z "$sub" ] || exit 2 ;;
esac
