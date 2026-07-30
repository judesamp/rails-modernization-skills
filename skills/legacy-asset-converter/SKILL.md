---
name: legacy-asset-converter
description: Convert legacy front-end assets to modern equivalents at scale — CoffeeScript to ES6, legacy template languages to maintained ones. Use when the user has CoffeeScript, Haml variants, or other legacy asset formats blocking a Rails or asset pipeline upgrade, or asks how to convert thousands of files safely.
---

# Legacy Asset Converter

For bulk conversion of legacy front-end assets — hundreds or thousands of files —
where the file count makes hand conversion impossible and blind automation
unsafe.

Almost always run because these files are **pinning something else**. Establish
that first: if CoffeeScript is blocking an asset pipeline upgrade which is
blocking Rails, the conversion is a means, and knowing the actual goal shapes how
far to take it.

## Prerequisites — check before converting anything

**Test coverage.** No human reviews 4,600 diffs. The suite is the only thing that
will catch a behaviour change. **Below roughly 70% on the affected code, stop and
say so** — the correct next step is coverage work, not conversion. This is not
caution for its own sake; it is the single decision that most determines whether
this goes well.

**A green baseline.** Record the current pass count. You cannot tell what you
broke without knowing what already failed.

**Runtime coverage of the UI.** Unit tests do not exercise JavaScript. Identify
what browser-level coverage exists (system tests, Playwright, Cypress) and treat
anything outside it as needing manual verification.

## Step 1 — inventory and classify

Count and categorize before converting:

```bash
find app -name "*.coffee" | wc -l
```

Sort into three buckets, because they need different handling:

- **Mechanical.** Straightforward syntax with a reliable automated translation.
  The bulk of any codebase.
- **Idiomatic.** Uses features with no clean modern equivalent — CoffeeScript's
  implicit returns, comprehensions, the existential operator, `@` bindings in
  callbacks. Converts, but the output needs reading.
- **Suspect.** Metaprogramming, dynamic dispatch, anything clever. Convert by
  hand or not at all.

Report the split. If "suspect" is large, the project is bigger than it looks.

## Step 2 — establish the pattern on a small batch

Convert **five to ten files first** and stop. Read every line of output. You are
looking for systematic problems, because a converter that mishandles one
construct mishandles it everywhere:

- Implicit returns becoming explicit `return` where the value was never used —
  harmless, noisy, and it inflates every subsequent diff
- `this`/`@` binding changes, especially in callbacks — the most common source
  of genuine behaviour change
- Truthiness differences: CoffeeScript's `?` existential operator is not
  equivalent to a JavaScript truthiness check, and `0` and `""` are where that
  bites
- String interpolation and regex escaping

Once the pattern is right, apply it. If the tooling systematically gets a
construct wrong, fix the approach before running it at scale rather than fixing
the same defect a thousand times downstream.

## Step 3 — convert in reviewable batches

**By directory or feature area, never all at once.** A batch is one commit, and
a commit should be revertable without losing unrelated work.

For each batch: convert, run the suite, run whatever browser tests exist, commit.
Never let two batches ride in one commit.

## Step 4 — audit the output

**Run [`conversion-auditor`](../conversion-auditor/SKILL.md) on every batch.**

This is not optional and it is not the same as the conversion pass. A tool that
reviews its own output grades its own homework — the audit needs to be a
separate pass with fresh eyes on the before/after pair.

## Step 5 — fix the class, not the instance

When a defect is found, **do not just fix that file.** Search the entire
converted corpus for the same pattern and fix every occurrence.

This is what separates a converging migration from one that produces mystery
bugs for a year. One bug found by hand is thirty found by grep.

## Step 6 — remove the old toolchain

Conversion is not done while the old pipeline still exists. Remove the gems, the
build steps, and the configuration. Confirm nothing references the old extension.
Leaving it means the next developer adds a new file in the old format.

## Rules

- **Never convert without a test baseline.** Recommending coverage work first is
  a legitimate outcome.
- **Never convert everything in one pass**, however well the sample went.
- **Read the idiomatic bucket by hand.** Mechanical translation is right about
  syntax and silent about intent.
- **Preserve behaviour, do not improve it.** Resist refactoring during
  conversion — mixing them makes every diff unreviewable.

## Reporting

Report: file counts by bucket, batches and their commits, defect patterns found
and how many occurrences each had fleet-wide, files needing manual review, and
whether the old toolchain has been fully removed.
