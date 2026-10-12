#!/bin/zsh
set -eu
cd "${0:A:h:h}"
for script in Install.command scripts/*.zsh tests/*.zsh(N); do
  /bin/zsh -n "$script"
done
/usr/bin/perl -c scripts/steam-options.pl
/usr/bin/perl tests/test-steam-options.pl
for check in tests/*.zsh(N); do /bin/zsh "$check"; done
print -- 'All checks passed.'
