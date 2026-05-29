# DomainParser

![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%20%7C%20macOS%2015%20%7C%20Linux%20%7C%20Windows-blue.svg?style=flat)
![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](LICENSE)

A small Swift library for parsing hostnames against the
[Public Suffix List](https://publicsuffix.org). Given a host like
`api.example.co.uk`, it tells you that the **public suffix** is `co.uk` and the
**registrable domain** is `example.co.uk`.

> **Note** — this is a personal fork of
> [Dashlane/SwiftDomainParser](https://github.com/Dashlane/SwiftDomainParser),
> maintained for [Passie](https://github.com/shadone/passie). It modernizes the
> package for Swift 6.2 + iOS 18 / macOS 15, adds Linux and Windows support,
> rewrites the API around `PublicSuffixList`, and keeps the bundled PSL current.
> See [`CHANGELOG.md`](CHANGELOG.md) for what's changed vs upstream.

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

let psl = try await PublicSuffixList.shared()   // load once, cached

let info = psl.lookup("app.alice.github.io")!
info.publicSuffix        // "github.io"   (PRIVATE rule)
info.registrableDomain   // "alice.github.io"
info.subdomain           // "app"
info.source              // .privateRule

// Credential-matching primitive:
psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io")  // false

// Registry-level grouping instead:
psl.lookup("alice.github.io", scope: .icannOnly)?.publicSuffix     // "io"
```

Build one instance and share it — `PublicSuffixList` is an immutable `Sendable`
value. Use `PublicSuffixList.bundled()` if you want to own its lifetime, or
`shared()` for a process-wide cached instance.

### From a URL

```swift
let info = psl.lookup(URL(string: "https://www.example.com/path")!)
info?.registrableDomain  // "example.com"
info?.publicSuffix       // "com"
```

Returns `nil` if the URL has no host component (e.g. `file:///etc/hosts`).

### ICANN-only scope

By default `lookup` matches both ICANN and PRIVATE rules. Pass `.icannOnly` to
restrict matching to the ICANN section of the PSL:

```swift
psl.lookup("alice.github.io", scope: .icannOnly)?.publicSuffix  // "io"
psl.registrableDomain(of: "alice.github.io", scope: .icannOnly)  // "github.io"
```

This is useful when you want registry-level grouping rather than
service-level grouping (e.g. treating `github.io` as one registrant, not each
`*.github.io` subdomain as its own registrable domain).

### HostInfo fields

`lookup` returns a `HostInfo` value (or `nil` for IP literals and
other inputs that cannot be looked up):

| Property            | Type            | Example                       |
|---------------------|-----------------|-------------------------------|
| `publicSuffix`      | `String`        | `"github.io"`                 |
| `registrableDomain` | `String?`       | `"alice.github.io"` (nil for a bare TLD) |
| `subdomain`         | `String?`       | `"app"` (nil if none)         |
| `source`            | `MatchSource`   | `.privateRule`                |
| `isPublicSuffix`    | `Bool`          | `false`                       |
| `isRegistrableDomain` | `Bool`        | `false`                       |

`MatchSource` values: `.icann`, `.privateRule`, `.defaultRule`.

### Loading from custom data

To load a PSL you fetched yourself, pass its raw `Data`:

```swift
let data = try Data(contentsOf: myPSLURL)
let psl = try await PublicSuffixList.loading(from: data)
```

### Error handling

All three factory methods are `async throws(PublicSuffixListError)`, so
`catch` can be exhaustive:

```swift
do {
    let psl = try await PublicSuffixList.bundled()
} catch .missingBundledResource {
    // bundled PSL file missing - should never happen in shipping builds
} catch .ruleParsingError(let message) {
    // PSL data is malformed UTF-8 or has an unsupported rule shape
} catch .bundleLoadFailed(let underlying) {
    // an I/O error reading the bundled file
}
```

### Protocol / dependency injection

`PublicSuffixMatching` is the DI seam. Only `lookup(_:scope:) -> HostInfo?`
is required; the protocol provides default implementations of
`lookup(_:URL, scope:)`, `registrableDomain(of:scope:)`,
`publicSuffix(of:scope:)`, `isPublicSuffix(_:scope:)`, and
`haveSameRegistrableDomain(_:_:scope:)`.

```swift
func classify(host: String, using psl: some PublicSuffixMatching) -> String? {
    psl.registrableDomain(of: host)
}
```

### List metadata

```swift
let meta = psl.metadata
meta.sourceDate        // Date the bundled PSL was fetched
meta.sourceRevision    // Upstream git revision string
meta.icannRuleCount    // Number of ICANN rules loaded
meta.privateRuleCount  // Number of PRIVATE rules loaded
```

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

## Internationalized domain names

Hosts may be passed in either Unicode form (e.g. `公司.cn`) or
ACE/Punycode form (e.g. `xn--55qx5d.cn`); the library handles both and
preserves the caller's form in the output. Internally each `xn--`-prefixed
label is RFC 3492-decoded and compared against the bundled PSL's
Unicode-form rules.

```swift
let psl = try await PublicSuffixList.shared()
psl.lookup("shishi.公司.cn")?.registrableDomain        // "shishi.公司.cn"
psl.lookup("shishi.xn--55qx5d.cn")?.registrableDomain  // "shishi.xn--55qx5d.cn"
```

Full UTS-46 IDNA normalization (NFC, Bidi checks, etc.) is **not**
implemented; this is a Punycode encode/decode-aware PSL lookup, not a
general IDNA processor.

## License

MIT — see [LICENSE](LICENSE). Upstream is Copyright © 2018 Dashlane.
