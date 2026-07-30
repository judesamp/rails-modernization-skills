---
name: test-coverage-writer
description: Raise test coverage on a legacy codebase ahead of a risky change — an upgrade, a bulk conversion, or a large refactor. Use when coverage is too low to migrate safely, when the user needs a safety net before touching a lot of code, or when another skill has stopped and asked for coverage work first.
---

# Test Coverage Writer

Builds a safety net on legacy code **before** something risky happens to it.

This is not general test-writing advice. The goal is narrow and it changes every
decision below: **make a specific upcoming change safe.** You are not trying to
reach a coverage number, and you are not trying to write the tests this codebase
deserves. You are trying to be able to tell, quickly, whether a migration broke
something.

Usually run because [`rails-upgrader`](../rails-upgrader/SKILL.md) or
[`legacy-asset-converter`](../legacy-asset-converter/SKILL.md) stopped and asked
for coverage first.

## The hard constraint

**Do not modify application code. At all.**

Not to fix a bug. Not to make something easier to test. Not to rename a
confusing variable while you are in there. No changes under `app/`, `lib/`, or
`config/` beyond the SimpleCov setup.

This is the single most important rule in this skill, and it is not stylistic.
The entire value of a safety net is that it was built against the code *as it
exists*. If the code changes while the net is being built, you can no longer
tell whether a later failure came from the migration or from something done
during coverage work — which defeats the reason for doing any of this.

It also protects against a specific failure mode: touching business logic while
holding a partial understanding of it. You are writing tests precisely because
nobody currently knows what this code does. That is the worst possible moment to
change it.

**Verify before finishing:**

```bash
git diff --name-only
```

Everything should be under `test/` or `spec/`, plus `docs/known-bugs.md` and the
SimpleCov configuration. **Any application file in that list is a violation** —
revert it and log the intended change instead.

If a piece of code genuinely cannot be tested without modification — a hard-coded
dependency, an untestable singleton — **stop and report it** rather than
refactoring for testability. That is a real finding and a decision for a human,
not a licence to change the code.

## Step 0 — establish what change is coming

Ask, or infer from context. The answer determines everything:

- A **Rails upgrade** → cover framework boundaries: controllers, callbacks,
  serialization, anything touching `ActiveRecord` query behaviour or params.
- A **bulk asset conversion** → cover the UI paths those assets drive. Unit
  tests will not help; you need request and system-level coverage.
- A **dependency upgrade** → cover the call sites of that dependency.
- A **refactor** → cover the seams the refactor will move.

**Uniform coverage is the wrong goal.** 89% overall with the migration path
untested is worse than 60% concentrated where the change lands.

## Step 1 — measure honestly

Get a real per-file baseline, not just a headline number.

```ruby
# test/test_helper.rb — before anything else loads
require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch
end
```

Report the overall figure **and** the distribution. "72% overall" hides
"the payments service is at 11%".

### Find the coverage that lies

A line marked covered is a line that *executed*, not a line that was *verified*.
Legacy suites are full of tests that exercise code and assert nothing meaningful.
Before writing anything new, look for:

- Tests with no assertions, or only `assert_response :success`
- Tests asserting on mocks they configured themselves — verifying the mock, not
  the code
- Setup blocks that execute half the application so that a trivial assertion
  passes

Enable **branch coverage**. Line coverage rates an `if` with no `else` case as
fully covered.

Say plainly how much of the existing coverage you consider real. That number
matters more than the reported one.

## Step 2 — prioritize by blast radius

Rank by `(likelihood the change touches it) × (cost if it breaks silently)`.

Highest value first:

1. **Money, auth, and data-integrity paths.** Silent breakage here is
   unacceptable regardless of what the migration touches.
2. **Code the change will definitely touch.** From Step 0.
3. **Code with the most callers.** Grep for call sites; heavily-called code
   fails loudly and broadly.
4. **Anything with no coverage at all** in a file that has some — usually the
   error branch, which is where upgrade breakage surfaces.

**Explicitly deprioritize:** admin tooling, rake tasks, anything already
scheduled for deletion, and code the migration will not reach. Say what you are
skipping and why — leaving it uncovered on purpose is a decision, not an
oversight.

## Step 3 — capture behaviour, and never fix bugs here

You are building a net, not improving the codebase. **Do not fix any bug you
find during coverage work.** Fixing means the safety net and the thing it
protects change at the same time, and you lose the ability to attribute any
later failure to either.

But you will find bugs — coverage work on legacy code always does. Handle them
like this:

### When the correct behaviour is clear

**Write the test asserting the behaviour you believe is correct, then skip it,
then log it.**

```ruby
test "returns zero for an account with no transactions" do
  skip "KNOWN BUG #7 — returns nil, not 0. See docs/known-bugs.md"

  assert_equal 0, account.balance
end
```

This is better than asserting the broken behaviour, because the test is already
written correctly for the day someone fixes it — they delete one line. Asserting
the bug means the eventual fix has to remember to invert a passing test, which
nobody does.

It also makes the suite itself the to-do list. A skipped test with a specific,
honest message is a durable marker that survives sprint boards and personnel
changes.

**The skip message must name the actual defect and point at the log.**
`skip "broken"` is worthless; the message is the entire value.

### When the correct behaviour is not clear

Sometimes you cannot tell whether something is a bug or load-bearing weirdness
somebody depends on. Then write a **characterization test**: assert what the code
currently does, comment that the behaviour is suspect and why, and log it as a
question rather than a defect. It still protects you during migration, which is
the job.

### Keep the log outside the test suite

Maintain a markdown file — `docs/known-bugs.md` — with an entry per finding:

```markdown
## 7. Account#balance returns nil for accounts with no transactions

- **Found:** while covering app/models/account.rb
- **Expected:** 0
- **Actual:** nil
- **Blast radius:** 4 call sites, 2 of them in the payments path
- **Test:** test/models/account_test.rb, skipped
- **Fix:** not attempted — coverage work only
```

Two reasons this matters more than it looks. It gives the team a triage queue
that outlives the migration. And **it is frequently the most valuable artifact
the whole exercise produces** — a catalogue of real defects nobody knew about,
each with a test already written and waiting.

## Step 4 — test at the level with the best coverage-per-effort

In legacy Rails, integration and request tests almost always win. One request
test exercises routing, controller, model, and view together — enormous coverage
per line written, and it tests the path a user actually takes.

Unit tests are better *tests* and worse *nets*. They are worth writing for
complex pure logic, and a poor use of limited time everywhere else.

**Prefer, in order:** request/integration tests → system tests for UI-driven
changes → unit tests for algorithmic code → mocked unit tests last, because
mocks encode current implementation and break during exactly the refactors you
are trying to protect.

## Step 5 — prove each test can fail

**A test that passes against broken code is worse than no test**, because it
produces false confidence at the moment you most need real confidence.

For every meaningful test you write, verify it fails when it should:

1. Deliberately break the code it covers — invert a condition, return `nil`,
   comment out the call.
2. Confirm the test fails, with a message that identifies the problem.
3. Restore the code.

Do this at least once per file. On the critical paths from Step 2, do it for
every test. This is the single highest-value habit in the whole skill, and it is
the one most often skipped.

## Step 6 — lock it in

Coverage decays. Before finishing:

- Set `minimum_coverage` in the SimpleCov config, at or just below the level
  reached, so regression fails the build.
- Set `minimum_coverage_by_file` too — an overall floor lets a critical file rot
  while the average holds.
- Confirm CI actually runs coverage and fails on a drop. A threshold nothing
  enforces is a comment.

## Rules

- **Never modify application code.** See the hard constraint above. Verify with
  `git diff --name-only` before finishing.
- **Never fix a bug you discover.** Write the correct test, skip it with a
  message naming the defect, log it, move on.
- **Never refactor for testability.** If code cannot be tested as written, that
  is a finding to report, not a change to make.
- **Never leave a vague skip message.** A skip is only useful if it says what is
  broken and where the detail lives. Vague skips are how a suite rots.
- **Never chase a percentage.** Concentrated coverage on the migration path beats
  a uniform number.
- **Never trust a test you have not seen fail.**
- **Report hollow coverage rather than adding to it.** If 30% of existing
  coverage is assertion-free, say so — the real starting point is lower than the
  badge claims.

## Reporting

Report: starting coverage overall and for the files that matter, how much
existing coverage is real versus hollow, what you prioritized and what you
deliberately skipped, tests added by level, every test verified to fail
correctly, the thresholds now enforced in CI, and — **usually the most valuable
output** — `docs/known-bugs.md`, with a count of defects found, how many have a
skipped test waiting, and which sit on critical paths.
