# Rails Modernization Skills

A set of [Claude Code](https://claude.com/claude-code) skills for dragging legacy
Rails applications forward: major-version upgrades, Ruby version jumps, security
alert remediation, and legacy asset conversion.

They exist because I used an in-house version of them to modernize a
21-application Ruby estate in under six months, with a two-developer team. This
repository is a clean-room reimplementation of that toolkit — same ideas,
written fresh and generic, with no employer-specific code.

---

## What the approach actually achieved

Across 21 applications, in under six months, with two developers:

| | |
|---|---|
| Rails | 5.1 → 7.1/7.2 across every application |
| Ruby | 2.4–2.6 → 3.2/3.3, crossing the Ruby 3 keyword-argument boundary |
| Legacy assets | 4,600+ CoffeeScript and Hamlc files converted to ES6 and EJS |
| Security | 500+ high and critical vulnerability alerts remediated |
| Test coverage | 52% → 89% |

That is scope normally staffed as a multi-year platform program. It did not
happen because AI wrote the code. It happened because the work was turned into
**repeatable tooling** instead of being done by hand 21 times.

---

## The method

The skills matter less than the sequence they run in. Five ideas do most of the
work.

### 1. Find what is actually pinning you

Legacy Rails applications are rarely stuck on Rails. They are stuck on something
Rails depends on. In our case 4,600 CoffeeScript and Hamlc files pinned the asset
pipeline, and the asset pipeline pinned Rails. No amount of `bundle update` was
ever going to move that.

Spend the first week identifying the true blocker. Upgrading around it wastes
months.

### 2. Build the safety net before you need it

We took test coverage from 52% to 89% *before* touching 4,600 files, not after.
Coverage work is unglamorous and easy to defer, and it is the only reason a
refactor at that scale shipped with a handful of user-reported regressions
instead of an outage.

If you are choosing between "start the migration now" and "get coverage up
first", get coverage up first. Always.

Two details that made this work, both in
[`test-coverage-writer`](skills/test-coverage-writer/SKILL.md):

**Coverage was concentrated, not uniform.** The goal was never a percentage. It
was being able to tell whether a specific upcoming change broke something, which
means covering the migration path heavily and admin tooling not at all.

**Every test was proven to fail.** A test that passes against broken code is
worse than no test, because it produces false confidence exactly when you need
real confidence. Break the code, watch the test fail, restore it. It is the
highest-value habit in the whole toolkit and the one most often skipped.

### 3. Automate the work, then automate the verification

Machine conversion is the easy half. The hard half is knowing whether 4,600
converted files still behave correctly — no human reads that diff.

So every converter here has a matching auditor. `legacy-asset-converter` does
the transformation; `conversion-auditor` independently reviews the output and
reports what looks wrong. Generation and verification must be separate passes,
because a tool that checks its own work grades its own homework.

### 4. Work from the guide, not from memory

Every upgrade skill here fetches the official upgrade guide or release notes
before doing anything. That instruction is deliberate and it is aimed at the
model: version-specific breaking changes are exactly the detail an LLM
reproduces confidently and incorrectly, and a wrong checklist is worse than none
— it sends you hunting for problems that do not exist while missing the ones
that do.

Same discipline for deprecation warnings. Read them from the logs, deduplicate
them, and work the distinct messages one at a time. A single offending call in a
shared helper emits hundreds of identical lines; the raw count makes a small job
look enormous.

### 5. Fix the class, not the instance

When a defect surfaced, we did not just fix it. We searched the whole fleet for
the same pattern and fixed every occurrence. One bug found by hand becomes
thirty found by grep. This is the difference between a migration that converges
and one that produces a long tail of mystery bugs for a year.

---

## The skills

Listed in the order you would actually run them.

| Skill | What it does |
|---|---|
| [`test-coverage-writer`](skills/test-coverage-writer/SKILL.md) | **Start here.** Builds the safety net before anything risky happens — characterization tests concentrated on the migration path, not a uniform coverage number. The other skills stop and point back at this one when coverage is too low. |
| [`rails-upgrader`](skills/rails-upgrader/SKILL.md) | Walks a Rails app one minor version at a time, using `app:update` and the framework defaults mechanism rather than a big-bang jump. |
| [`ruby-upgrader`](skills/ruby-upgrader/SKILL.md) | Ruby version upgrades, with particular attention to the Ruby 3.0 keyword-argument separation, which is where most of the real work lives. |
| [`upgrade-failure-triage`](skills/upgrade-failure-triage/SKILL.md) | For when the suite goes red after a version bump. Groups failures by signature before fixing any of them, and enforces the rule that you may only change a test if you can say why the behaviour is still correct. |
| [`dependency-security-fixer`](skills/dependency-security-fixer/SKILL.md) | Triages and remediates dependency vulnerability alerts in bulk, grouping by root cause instead of working the list top to bottom. |
| [`legacy-asset-converter`](skills/legacy-asset-converter/SKILL.md) | Converts CoffeeScript to ES6 and legacy template languages to modern equivalents, in reviewable batches. |
| [`conversion-auditor`](skills/conversion-auditor/SKILL.md) | Independently reviews machine-converted files for silent behaviour changes. Run after any bulk conversion. |
| [`index-auditor`](skills/index-auditor/SKILL.md) | Independent of the upgrade sequence. Finds missing and unused database indexes from foreign keys, query patterns and Postgres statistics — and requires evidence plus a before/after `EXPLAIN` for every recommendation, because adding indexes blindly is its own performance problem. |

---

## Installing

Copy the skills you want into your project or personal skills directory:

```bash
# project-scoped
mkdir -p .claude/skills
cp -r skills/rails-upgrader .claude/skills/

# or available everywhere
cp -r skills/rails-upgrader ~/.claude/skills/
```

Claude Code discovers them automatically. Invoke by name (`/rails-upgrader`) or
just describe the task and let the description match.

---

## A note on expectations

These are not magic. They encode a method — sequencing, verification, and
pattern-based remediation — that makes AI assistance useful on large migrations
instead of merely fast. The judgment about *what* to upgrade and *when* is still
yours. What these remove is the part where you do the same careful thing
twenty-one times and lose concentration on the fourteenth.

Run them on a branch. Read the diffs. Keep the test suite green between steps.

---

## Consulting

I take on Rails modernization work — version upgrades, dependency security
remediation, and legacy asset migration — including subcontract and overflow
engagements for agencies.

judesamp@gmail.com · [linkedin.com/in/jeremysamples](https://linkedin.com/in/jeremysamples)

## License

MIT — see [LICENSE](LICENSE).
