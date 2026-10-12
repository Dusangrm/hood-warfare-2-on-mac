#!/bin/zsh
set -eu
cd "${0:A:h:h}"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || { print -u2 'Commit the validated source before building a release.'; exit 1; }
mkdir -p dist
git archive --format=zip --prefix=Hood-Warfare-2-on-Mac/ HEAD > dist/Hood-Warfare-2-on-Mac.zip
cd dist
/usr/bin/shasum -a 256 Hood-Warfare-2-on-Mac.zip > SHA256SUMS.txt
print -- "Built ${PWD}/Hood-Warfare-2-on-Mac.zip"
