# IDN Handling

How internationalized names are matched, and the UTS-46 caveat.

## Overview

Hosts are lowercased and any `xn--` labels are Punycode-decoded for matching
against the Unicode-form bundled rules; the output preserves whichever form
(ACE or Unicode) you passed in. Normalization is `lowercased()` + Punycode, not
full UTS-46/IDNA2008 mapping, which needs ICU-grade tables. This passes the
official PSL test suite; a deliberately exotic Unicode host could in principle
normalize differently than a fully IDNA-compliant implementation.
