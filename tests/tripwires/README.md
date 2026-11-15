# Tripwires

Each file here breaks one engineering rule on purpose. `./tests/check.sh --tripwires`
loads them one at a time (as if they were config code) and insists the matching
check FAILS. A check that cannot fail is worse than no check, because it is believed.

Never loaded in normal use: this folder is only added to the runtimepath when
`CHECK_TRIPWIRE` is set.
