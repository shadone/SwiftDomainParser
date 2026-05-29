# Choosing a Scope

When to use ``MatchScope/all`` versus ``MatchScope/icannOnly``.

## Overview

Use ``MatchScope/all`` (default) for credential matching and any "are these the
same site for trust purposes" question — it isolates per-tenant subdomains.
Use ``MatchScope/icannOnly`` when you want registry-level grouping that matches
cookie-style semantics and intentionally treats `*.github.io` as one site.
