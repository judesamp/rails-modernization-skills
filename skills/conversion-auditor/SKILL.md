---
name: conversion-auditor
description: Independently review machine-converted or bulk-refactored files for silent behaviour changes. Use after any large automated conversion, codemod, or find-and-replace refactor, when the user needs to verify that converted output still behaves identically and the volume is too large to review by hand.
---

# Conversion Auditor

Reviews the output of a bulk automated conversion for **behaviour changes**, not
style. Run it after `legacy-asset-converter`, a codemod, a large find-and-replace,
or any refactor touching more files than a person will actually read.

## The premise

Bulk conversion tools are reliable about syntax and silent about semantics. They
produce code that parses, runs, and is subtly different. At small scale a human
catches this in review; at four thousand files nobody reads the diff, and the
defects reach production one user report at a time.

This is a **separate pass from the conversion**. A tool that audits its own
output repeats its own blind spots — the same assumption that produced the
error passes it. Fresh eyes on the before/after pair is the entire point.

## What to actually look for

Work through the diff by category. Ignore formatting entirely.

### Truthiness and null handling

The largest source of real defects. Languages disagree about what is falsy.
CoffeeScript's existential operator `?` checks for `null`/`undefined` only,
while a JavaScript truthiness check also catches `0`, `""`, `NaN`, and `false`.

```coffee
if count?          # true when count is 0
```
```javascript
if (count)         // false when count is 0  ← behaviour change
if (count != null) // correct translation
```

Flag every one. This is where the bugs are.

### Implicit returns

Languages with implicit returns produce functions returning their last
expression. A converter usually preserves this, but where it does not, callers
depending on the value break silently — and nothing throws.

### `this` binding

Fat-arrow versus function binding in callbacks. If `this` resolves differently
the code fails at runtime, on a path tests may not cover. Check every callback,
event handler, and method passed as a reference.

### Scope and hoisting

`var` hoists to function scope; `let`/`const` are block-scoped and throw on use
before declaration. Conversion inside a loop or conditional can change what a
closure captures — a classic source of "all the handlers use the last value".

### Comparison semantics

Loose versus strict equality. Where a converter emits `==` for what was value
comparison, type coercion enters.

### String interpolation and escaping

Interpolation syntax differing in how it escapes, especially anything reaching
`innerHTML` or building markup. **Escaping regressions are security findings**,
not cosmetic ones — report them as such.

### Iteration order and comprehensions

Comprehensions converted to `map`/`filter`/`forEach` can differ in whether they
return a value, skip empty slots, or mutate.

## Procedure

1. **Get the pair.** Original and converted for the batch under review. Without
   the original you are reading code, not auditing a conversion.
2. **Work by category, not by file.** Scanning for one class of defect across
   all files is far more reliable than reading each file for everything.
3. **Rate each finding.** *Certain* behaviour change, *possible*, or *cosmetic*.
   Report only the first two. A noisy audit gets ignored, which is worse than no
   audit.
4. **For each real finding, search the whole corpus for the same pattern.** The
   count matters more than the instance — "found in 1 file" and "found in 47" are
   different projects.
5. **Verify test coverage of the affected paths.** A finding in covered code that
   passes is likely fine. A finding in uncovered code needs manual verification,
   and saying so is part of the job.

## Rules

- **Report behaviour changes only.** Formatting, naming, and idiom preferences
  are out of scope and dilute the signal.
- **Never fix while auditing.** Auditing and editing in one pass means losing
  track of what was verified. Produce the list; fix in a separate change.
- **Always give a fleet-wide count per pattern.**
- **Say what you could not check.** Dynamic dispatch, metaprogramming, and
  runtime-generated code are not statically reviewable — flag them for manual
  testing rather than passing them silently.

## Reporting

Report, in this order:

1. **Certain behaviour changes** — file, line, before/after, and the consequence.
2. **Possible changes needing human judgment.**
3. **Pattern counts** — for each defect class, how many occurrences fleet-wide.
4. **Coverage gaps** — findings in code no test exercises.
5. **Not statically checkable** — what needs manual verification and why.

If there are no findings, say so plainly and state what was checked. "Reviewed
340 files for truthiness, binding, scope, and escaping changes; no behaviour
differences found" is a useful result. "Looks good" is not.
