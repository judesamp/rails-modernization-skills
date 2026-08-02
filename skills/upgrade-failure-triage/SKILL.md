---
name: upgrade-failure-triage
description: Investigate and fix test failures caused by a framework or language upgrade. Use after bumping Rails or Ruby when the suite goes red, when there are many failures and it is unclear where to start, or when deciding whether a failing test indicates broken code or a test coupled to something that moved.
---

# Upgrade Failure Triage

For the moment after a version bump when the suite turns red. Not general
debugging — the failure profile of an upgrade is distinctive, and treating it
like ordinary debugging wastes most of the day.

## The premise

**Upgrade failures cluster.** Two hundred failures are rarely two hundred
problems; they are usually four or five root causes with wide blast radius. The
instinct to open the first failure and start fixing is the single most expensive
mistake available here, because you will fix the same thing forty times without
noticing.

Group first. Always.

## Step 1 — get the distinct signatures, not the failures

Never read failures one by one. Extract the error signatures and count them:

```bash
bin/rails test 2>&1 | grep -E "^(Failure|Error):" -A2 \
  | grep -oE "[A-Z][A-Za-z:]*(Error|Exception)[^\\n]*" \
  | sort | uniq -c | sort -rn
```

Adjust to your reporter. The output you want is *"NoMethodError: undefined
method 'update_attributes' — 47 occurrences"*, not a scrolling wall.

**Report the distinct count before doing anything.** "212 failures, 6 distinct
causes" reframes the work from impossible to an afternoon, and it is almost
always the true shape.

## Step 2 — categorize each signature

Post-upgrade failures fall into a small number of buckets, and the bucket
determines the fix:

**Removed or renamed API.** `NoMethodError` on a framework method. The clearest
category — the upgrade guide names it, the fix is mechanical, and it applies
everywhere the call appears.

**Changed default behaviour.** The nastiest. No error, just different results —
serialization formats, timezone handling, `nil` treatment in queries, cache key
generation. If you adopted framework defaults in the same commit as the version
bump, this is why the skill tells you not to.

**Test coupled to internals.** The application is fine; the test reached into
something that moved. Mocks and stubs of framework internals, assertions on
private methods, fixtures depending on load order.

**Gem incompatibility.** The failure is inside a dependency, not your code. Check
whether a newer version supports this framework version before touching
anything.

**Autoloading and load order.** Constant resolution failures, especially in the
Rails 6 Zeitwerk transition. Frequently appear only under eager loading.

**Ruby-level semantics.** Keyword arguments, frozen string literals, `Psych` 4
YAML aliases. These fail at runtime on paths tests may not fully cover.

## Step 3 — the app-or-test question

For each signature, answer one question before writing anything:

> **Did the behaviour change, or did the test's grip on the implementation slip?**

**Default to assuming the application broke.** Editing a test until it passes is
the fastest way to make a red suite green and ship a real regression. The whole
point of having the suite was this moment.

You may change the test only when you can state, in a sentence, why the observed
behaviour is still correct. For example: *"the test stubbed
`ActiveRecord::Base.connection.execute`, which Rails now calls differently — the
query and its result are unchanged."* If you cannot write that sentence, the
application is broken.

**Warning signs that you are rationalizing:** loosening an assertion rather than
updating it, deleting a test because it is "testing the framework", adding
`skip` without a specific reason, or changing an expected value to whatever the
code now returns. That last one is a false negative in a bottle.

## Step 4 — use the commit structure to bisect

If the upgrade followed the intended sequence, there is a commit for the version
bump and a separate commit per adopted framework default. That structure is what
makes the ambiguous failures tractable:

```bash
git stash
git checkout <version-bump-commit>
bin/rails test path/to/failing_test.rb
```

Passing at the version bump and failing after a defaults commit tells you
exactly which default did it — which is otherwise very hard to determine, since
defaults change behaviour silently.

If the upgrade was done as one commit, this is unavailable. Say so, and
recommend redoing it in the correct sequence rather than guessing.

## Step 5 — fix by signature, verify by count

Fix one signature at a time. After each, re-run and confirm the **count** moved
as expected.

This is the check that catches mistakes: if a fix should have resolved 47
failures and resolved 9, the signature covered more than one root cause and
needs splitting. If it resolved 47 and introduced 3 new ones, the fix has a side
effect worth understanding now rather than later.

Commit per signature. When something surfaces a week later you want one
candidate change, not a single "fix upgrade failures" commit touching ninety
files.

## Rules

- **Never fix failures one at a time before grouping them.**
- **Never change a test to make it pass** without being able to state why the
  behaviour is still correct.
- **Never `skip` a failing test to move on.** If it must be deferred, the skip
  message names the defect and it goes in the bug log. A vague skip is how a
  suite rots.
- **Do not refactor while triaging.** Smallest change that resolves the
  signature; cleanup is a separate pass.
- **A gem failure is not your bug.** Check for a compatible release before
  patching around it.

## Reporting

Report: total failures and **distinct signatures**, each signature with its
count and category, which were application defects versus test coupling and the
one-sentence justification for every test you modified, anything deferred with
its bug-log entry, and the final count. If any signature was resolved by
changing an expected value, call it out explicitly — that is the change most
likely to be hiding a real regression.
