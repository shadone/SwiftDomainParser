# PublicSuffixListKit

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
.package(url: "https://github.com/shadone/PublicSuffixListKit.git", from: "3.0.0"),
```

then add `"PublicSuffixListKit"` to your target's dependencies.

## Usage

```swift
import PublicSuffixListKit

let psl = PublicSuffixList.shared   // bundled list, decoded once, cached

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

`PublicSuffixList.shared` is the bundled list: an immutable `Sendable` value,
decoded from a precompiled binary blob once on first access (synchronous,
thread-safe, ~2 ms) and cached for the process lifetime. No `await`, no `try`
— `lookup` is a pure value query.

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
| `canonicalPublicSuffix` | `String`    | `"github.io"`                 |
| `canonicalRegistrableDomain` | `String?` | `"alice.github.io"`        |
| `asciiRegistrableDomain` | `String?`  | `"alice.github.io"`           |

`MatchSource` values: `.icann`, `.privateRule`, `.defaultRule`.

The `publicSuffix` / `registrableDomain` fields preserve the caller's input
spelling (A-label or U-label). The `canonical*` fields give the UTS-46 U-label
(NFC) form for comparison and storage, and `asciiRegistrableDomain` the A-label
(`xn--`) form — see [Internationalized domain names](#internationalized-domain-names).

### Loading from custom data

To load a PSL you fetched yourself, pass its raw `Data`:

```swift
let data = try Data(contentsOf: myPSLURL)
let psl = try PublicSuffixList.loading(from: data)
```

### Error handling

`loading(from:)` is synchronous and `throws(PublicSuffixListError)`, with the
single case `ruleParsingError` (malformed UTF-8 or an unsupported rule shape):

```swift
do {
    let psl = try PublicSuffixList.loading(from: data)
} catch .ruleParsingError(let message) {
    // custom PSL data is malformed UTF-8 or has an unsupported rule shape
}
```

`PublicSuffixList.shared` never throws: its blob is a build-time artifact, so a
missing or corrupt one is a package defect and traps rather than throwing.

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
`Sources/PublicSuffixListKit/Resources/public_suffix_list.dat`. To refresh:

```bash
swift script/UpdatePSL.swift
```

The script fetches the current list from `publicsuffix.org`, strips comments
and whitespace, sorts rules by descending label count (so highest-priority
matches come first), and overwrites the bundled file. Run from anywhere —
the target path is resolved relative to the script, not the current
directory.

## Internationalized domain names

Hosts are normalized with **UTS-46** (nontransitional, `UseSTD3ASCIIRules =
false` — the WHATWG URL / browser default): a mapping table compiled from
Unicode's `IdnaMappingTable.txt`, NFC normalization, and Punycode
decode/encode. So a host may be passed in any form — Unicode (`公司.cn`),
ACE/Punycode (`xn--55qx5d.cn`), or a compatibility/case variant — and they all
fold to one canonical form.

Lookup output preserves the caller's spelling, while the `canonical*` fields and
comparison use the canonical form:

```swift
let psl = PublicSuffixList.shared

// Display fields round-trip the caller's spelling:
psl.lookup("shishi.公司.cn")?.registrableDomain        // "shishi.公司.cn"
psl.lookup("shishi.xn--55qx5d.cn")?.registrableDomain  // "shishi.xn--55qx5d.cn"

// ...but canonical forms (and equality) treat them as the same domain:
psl.lookup("shishi.公司.cn")?.canonicalRegistrableDomain   // "shishi.公司.cn"
psl.lookup("shishi.公司.cn")?.asciiRegistrableDomain       // "shishi.xn--55qx5d.cn"
psl.haveSameRegistrableDomain("食狮.公司.cn",
                              "xn--85x722f.xn--55qx5d.cn")  // true
```

Correctness is verified against Unicode's official `IdnaTestV2.txt` conformance
vectors. The IDNA2008 **Bidi rule** and **ContextJ/ContextO** joiner checks are
not implemented — they govern whether a name may be *registered*, not which
registrable domain a host belongs to.

## Refreshing the bundled Unicode data

The bundled UTS-46 mapping table lives at
`Sources/PublicSuffixListKit/Resources/idna_mapping.bin`. To regenerate it from
a newer Unicode version:

```bash
swift script/UpdateIDNAMapping.swift
```

It fetches `IdnaMappingTable.txt` from `unicode.org` and compiles it into the
compact binary table. As with `UpdatePSL.swift`, the target path is resolved
relative to the script, so it runs from anywhere.

## License

MIT — see [LICENSE](LICENSE). Upstream is Copyright © 2018 Dashlane.
