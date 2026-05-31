# ``PublicSuffixListKit``

Match hostnames against the Public Suffix List.

## Overview

Given a host like `app.alice.github.io`, ``PublicSuffixList`` tells you the
public suffix (`github.io`), the registrable domain (`alice.github.io`), and
the subdomain (`app`). Use ``PublicSuffixList/shared`` — it decodes the
bundled precompiled list once, synchronously, on first access and caches the
immutable, `Sendable` value for the process lifetime. No `await`, no `try`:

```swift
let info = PublicSuffixList.shared.lookup("app.alice.github.io")
```

Custom (non-bundled) `.dat` text lists load via
``PublicSuffixList/loading(from:)``, which parses text and so `throws`.

## Topics

### Essentials
- ``PublicSuffixList``
- ``HostInfo``
- ``MatchScope``

### Articles
- <doc:ICANNvsPrivate>
- <doc:ChoosingAScope>
- <doc:IDNHandling>
