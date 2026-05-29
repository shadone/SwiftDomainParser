# ICANN vs PRIVATE

Why `alice.github.io` and `bob.github.io` are different sites.

## Overview

The PSL has two sections. ICANN rules are real registry suffixes (`com`,
`co.uk`). PRIVATE rules are operators who delegate subdomains to untrusted
third parties (`github.io`, `blogspot.com`). For credential isolation you must
consult PRIVATE rules — otherwise per-tenant subdomains collapse to one
registrable domain. ``MatchScope/all`` (the default) includes PRIVATE rules;
``MatchScope/icannOnly`` ignores them.
