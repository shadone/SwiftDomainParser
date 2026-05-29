# ``DomainParser``

Match hostnames against the Public Suffix List.

## Overview

Given a host like `app.alice.github.io`, ``PublicSuffixList`` tells you the
public suffix (`github.io`), the registrable domain (`alice.github.io`), and
the subdomain (`app`). Loading parses the bundled list once; build a
``PublicSuffixList`` (await ``PublicSuffixList/bundled()`` or
``PublicSuffixList/shared()``) and share the immutable, `Sendable` value.

## Topics

### Essentials
- ``PublicSuffixList``
- ``HostInfo``
- ``MatchScope``

### Articles
- <doc:ICANNvsPrivate>
- <doc:ChoosingAScope>
- <doc:IDNHandling>
