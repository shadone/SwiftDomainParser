# Releasing PublicSuffixListKit

How to cut a new release. Written to be followed verbatim by a human or an LLM
agent. Steps are ordered; do not skip or reorder them.

## Facts about this package

- **Versioning is git tags only.** `Package.swift` carries no version string;
  Swift Package Manager resolves versions from annotated git tags. The release
  *is* the tag.
- **Tag format is bare SemVer**, no `v` prefix: `2.0.0`, not `v2.0.0`. Match the
  existing tags (`git tag` to confirm).
- **Default branch is `develop`.** Releases are cut from `develop`.
- **Remote `origin` is the source of truth:**
  `git@github.com:shadone/PublicSuffixListKit.git`. (Unlike the sibling `Passie/`
  and `KDBXKit/` repos, this one has no Forgejo upstream — GitHub is canonical.)
- **CHANGELOG** follows [Keep a Changelog](https://keepachangelog.com/) and the
  project adheres to [SemVer](https://semver.org/). Unreleased work accumulates
  under a `## [Unreleased]` heading.

Pick the version per SemVer: breaking API change → major; backward-compatible
feature → minor; backward-compatible fix → patch. A bundled-PSL data refresh
with no API change is a patch. Below, `X.Y.Z` is the version being released and
`<prev>` is the most recent existing tag.

## Preconditions

```sh
# Run from the repo root: .../PublicSuffixListKit
git switch develop
git pull --ff-only origin develop      # be on the latest develop
git status                             # MUST be clean; commit/stash any changes first
git tag                                # confirm X.Y.Z does not already exist
```

If the working tree is dirty, stop and resolve that before continuing.

## 1. Verify the build and tests

A release must build clean and pass the full suite locally first.

```sh
swift build
swift build -c release
swift test
```

All three must succeed. If anything fails, stop — fix it (or abandon the
release) before proceeding. Do not tag a red build.

## 2. Finalize the CHANGELOG

Edit `CHANGELOG.md`:

1. Rename the `## [Unreleased]` heading to `## [X.Y.Z] - YYYY-MM-DD`, using
   today's date in ISO form (e.g. `2026-05-29`).
2. Trim any "Targeting X.Y.Z…" wording that only made sense while unreleased so
   the section reads as a shipped release.
3. Confirm `### Added / Changed / Removed / Fixed` entries accurately describe
   what's in this tag. Remove empty subsections.
4. Update the link-reference block at the bottom of the file. Replace the
   `[Unreleased]` compare link with a concrete one for this version:

   ```
   [X.Y.Z]: https://github.com/shadone/PublicSuffixListKit/compare/<prev>...X.Y.Z
   ```

   Keep the existing per-version links below it.

If there is ongoing work that should *not* ship in this release, leave a fresh
empty `## [Unreleased]` section above the new version heading (with an
`[Unreleased]: …/compare/X.Y.Z...HEAD` link). Otherwise omit it.

## 3. Commit the changelog

```sh
git add CHANGELOG.md
git commit -m "docs: finalize X.Y.Z release in CHANGELOG"
```

Use a `docs:` conventional-commit subject. If the release also includes a PSL
data refresh staged in the same commit, prefer `data:` / `chore:` as fits.

## 4. Create the annotated tag

Tags must be **annotated** (`-a`), not lightweight, so they carry a message and
a tagger.

```sh
git tag -a X.Y.Z -m "PublicSuffixListKit X.Y.Z

<one or two lines summarizing the release; see CHANGELOG.md for details>"

git show X.Y.Z --stat --no-patch   # sanity-check the tag points at the new commit
```

The tag must point at the changelog commit from step 3 (the tip of `develop`).

## 5. Push the branch and the tag

```sh
git push origin develop
git push origin X.Y.Z
```

Pushing the tag is what publishes the release to SPM consumers. Push the branch
first so the commit the tag references exists on the remote.

## 6. Create the GitHub Release

Extract this version's CHANGELOG section as the release notes, then publish.
`--verify-tag` ensures the tag was pushed in step 5.

```sh
# Extract the X.Y.Z section (everything between its heading and the next ## heading)
awk '/^## \[X\.Y\.Z\]/{f=1; next} /^## \[/{f=0} f' CHANGELOG.md > /tmp/release-notes.md

gh release create X.Y.Z \
  --repo shadone/PublicSuffixListKit \
  --title "X.Y.Z" \
  --notes-file /tmp/release-notes.md \
  --verify-tag
```

For a pre-release (e.g. `X.Y.Z-beta.1`), add `--prerelease`.

## 7. Verify

```sh
gh release view X.Y.Z --repo shadone/PublicSuffixListKit --json url,tagName -q '.tagName + " -> " + .url'
```

Open the printed URL and confirm the notes render correctly and the tag is
attached. The `Tests` workflow runs on the push to `develop`; confirm it is
green:

```sh
gh run list --repo shadone/PublicSuffixListKit --branch develop --limit 3
```

## Rollback

If a mistake is caught **before** anyone has depended on the tag:

```sh
git push origin :refs/tags/X.Y.Z   # delete the remote tag
git tag -d X.Y.Z                   # delete the local tag
gh release delete X.Y.Z --repo shadone/PublicSuffixListKit --yes
```

Then fix the problem and start over from step 1. Avoid deleting a tag once it
may have been resolved by a downstream package — cut a new patch instead.

## Quick reference

| Step | Command |
|---|---|
| Verify | `swift build && swift build -c release && swift test` |
| Commit | `git commit -am "docs: finalize X.Y.Z release in CHANGELOG"` |
| Tag | `git tag -a X.Y.Z -m "PublicSuffixListKit X.Y.Z"` |
| Push | `git push origin develop && git push origin X.Y.Z` |
| Release | `gh release create X.Y.Z --title X.Y.Z --notes-file /tmp/release-notes.md --verify-tag` |
