# IDN Handling

How internationalized names are normalized, matched, and compared.

## Overview

Hosts are processed with UTS-46 (Unicode IDNA Compatible Preprocessing),
nontransitional, using a mapping table compiled from Unicode's
`IdnaMappingTable.txt`: each code point is mapped/ignored/kept per UTS-46,
`xn--` labels are Punycode-decoded, and the result is NFC-normalized. This means
case, compatibility forms (e.g. fullwidth letters), and A-label vs U-label
spellings all fold to one canonical form.

``HostInfo`` therefore exposes both forms:

- ``HostInfo/registrableDomain`` (and ``HostInfo/publicSuffix``) preserve the
  caller's input spelling, so lookups round-trip the form you passed in.
- ``HostInfo/canonicalRegistrableDomain`` (and
  ``HostInfo/canonicalPublicSuffix``) give the canonical U-label form, and
  ``HostInfo/asciiRegistrableDomain`` gives the A-label (`xn--`) form.

Comparison uses the canonical form, so
``PublicSuffixMatching/haveSameRegistrableDomain(_:_:scope:)`` treats
`食狮.公司.cn` and `xn--85x722f.xn--55qx5d.cn` as the same domain.

## Profile and scope

Processing is **nontransitional** with **`UseSTD3ASCIIRules = false`** — the
WHATWG URL / browser default, appropriate for matching hosts that come from web
URLs. Correctness is verified against Unicode's official `IdnaTestV2.txt`
conformance vectors.

Two registration-time validity checks are intentionally **not** implemented,
because they govern whether a name may be *registered*, not which registrable
domain a host belongs to:

- the **Bidi rule** (RFC 5893), and
- **ContextJ / ContextO** joiner checks (ZWNJ / ZWJ).

Full UTS-46 mapping and NFC are applied; only those two validity rules are out
of scope.
