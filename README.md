# DomainParser

![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%20%7C%20macOS%2015-blue.svg?style=flat)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](LICENSE)

A small Swift library for parsing hostnames against the
[Public Suffix List](https://publicsuffix.org). Given a host like
`api.example.co.uk`, it tells you that the **public suffix** is `co.uk` and the
**registrable domain** is `example.co.uk`.

> **Note** — this is a personal fork of
> [Dashlane/SwiftDomainParser](https://github.com/Dashlane/SwiftDomainParser),
> maintained for [Passie](https://github.com/shadone/passie). It modernizes the
> package for Swift 6 + iOS 18 / macOS 15, fixes a latent case-sensitivity bug,
> and keeps the bundled PSL current. See [`CHANGELOG.md`](CHANGELOG.md) for
> what's changed vs upstream.

## Why a PSL parser?

The PSL lists all known public suffixes (e.g. `com`, `co.uk`, `nt.edu.au`).
Without it you can't tell which part of `api.example.co.uk` is the registrable
domain — `example.co.uk` is owned by one party, but the string `co.uk` alone
isn't. The list also handles wildcards (`*.ck`) and exceptions (`!www.ck`);
see the [format spec](https://github.com/publicsuffix/list/wiki/Format).

| Host                       | Registrable domain | Public suffix | Rule       |
|----------------------------|--------------------|---------------|------------|
| `auth.example.com`         | `example.com`      | `com`         | `com`      |
| `sub.example.co.uk`        | `example.co.uk`    | `co.uk`       | `co.uk`    |
| `sub.example.gov.ck`       | `example.gov.ck`   | `gov.ck`      | `*.ck`     |
| `sub.example.any.ck`       | `example.any.ck`   | `any.ck`      | `*.ck`     |
| `www.ck`                   | `www.ck`           | `ck`          | `!www.ck`  |
| `sub.www.ck`               | `www.ck`           | `ck`          | `!www.ck`  |

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/shadone/SwiftDomainParser.git", from: "2.0.0"),
```

then add `"DomainParser"` to your target's dependencies.

## Usage

```swift
import DomainParser

let parser = try DomainParser()
```

Construction reads and parses the bundled PSL (~10K rules). Hold onto one
instance and reuse it — `DomainParser` is `Sendable`, safe to share across
isolation domains.

### From a host string

```swift
let result = parser.parse(host: "awesome.example.co.uk")
result?.registrableDomain  // "example.co.uk"
result?.publicSuffix       // "co.uk"
```

Host comparison is case-insensitive; `EXAMPLE.com`, `example.COM`, and
`example.com` all parse the same.

### From a URL

```swift
let result = parser.parse(url: URL(string: "https://www.example.com/path")!)
result?.registrableDomain  // "example.com"
result?.publicSuffix       // "com"
```

Returns `nil` if the URL has no host component (e.g. `file:///etc/hosts`).

### Basic-only parsing

If you don't need wildcard or exception rules, use `BasicDomainParser`
directly — the lookup is one `Set<String>.contains` per host label, with no
wildcard/exception logic on the hot path:

```swift
let basic = try BasicDomainParser()
basic.parse(host: "example.com")?.registrableDomain  // "example.com"
```

`BasicDomainParser` requires lowercase input. `DomainParser` lowercases for
you internally; if you reach for `BasicDomainParser` directly, pass
`host.lowercased()`.

### Error handling

`DomainParser()` and `BasicDomainParser()` both `throws(DomainParserError)`,
so `catch` can be exhaustive without a fallthrough clause:

```swift
do {
    let parser = try DomainParser()
} catch .missingPublicSuffixListResource {
    // bundled PSL file missing - should never happen in shipping builds
} catch .ruleParsingError(let message) {
    // bundled PSL file is malformed UTF-8 or has an unsupported rule shape
} catch .bundleLoadFailed(let underlying) {
    // an I/O error reading the bundled file (e.g. CocoaError from Data(contentsOf:))
}
```

### Testing

`FakeDomainParser` (DEBUG builds only) is a no-op `DomainParserProtocol`
implementation. Useful for SwiftUI previews and tests that need to inject a
parser but don't care about the result.

## Refreshing the bundled Public Suffix List

The PSL changes regularly. The bundled copy lives at
`Sources/DomainParser/Resources/public_suffix_list.dat`. To refresh:

```bash
swift script/UpdatePSL.swift
```

The script fetches the current list from `publicsuffix.org`, strips comments
and whitespace, sorts rules by descending label count (so highest-priority
matches come first), and overwrites the bundled file. Run from anywhere —
the target path is resolved relative to the script, not the current
directory.

## Known limitations

- **No Punycode / IDNA.** Hosts must be in lowercase Unicode form or
  pre-encoded ACE (`xn--...`). Most callers reading hostnames from system URL
  components already get ACE form, so this is rarely an issue in practice.

## License

MIT — see [LICENSE](LICENSE). Upstream is Copyright © 2018 Dashlane.
