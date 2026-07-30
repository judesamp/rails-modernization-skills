---
name: rails-upgrader
description: Upgrade a Rails application one minor version at a time, using bin/rails app:update and the framework defaults mechanism. Use when the user wants to upgrade Rails, is stuck on an old Rails version, mentions app:update, load_defaults, new_framework_defaults, or asks how to get from an old Rails to a current one.
---

# Rails Upgrader

Moves a Rails application forward one version at a time, keeping the suite green
at every step. Designed for applications several major versions behind, where a
direct jump is not survivable.

## Before touching anything

Establish these four facts and report them. If any is missing, fix that first —
upgrading without them is how migrations turn into outages.

1. **Current and target versions.** Read `Gemfile.lock` (the `rails` line under
   `specs`) and `.ruby-version`. Do not trust the `Gemfile` constraint alone.
2. **Test coverage.** Run the suite and get a real number. **Below roughly 60%,
   stop and say so.** Coverage is the only thing standing between an upgrade and
   a silent behaviour change. Recommending coverage work first is a legitimate
   outcome of running this skill.
3. **The real blocker.** Applications are rarely pinned by Rails itself. Check
   for: a JavaScript runtime tied to Sprockets, template languages with no
   maintained successor (Haml variants, Slim forks), gems abandoned before the
   target version, and anything monkey-patching Rails internals.
   Run `bundle outdated --strict` and look for gems with no release in years.
4. **The upgrade path.** Rails does not support skipping majors. Enumerate the
   ladder — 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 — and say how many rungs there are.

## The loop, one rung at a time

For each version in the path, in order. Never batch two rungs.

### Step 1 — read the release notes

Fetch the official upgrade guide for the target version and list the breaking
changes that actually apply to this codebase. Not all of them; the ones with
matching call sites. Search the code to confirm each.

### Step 2 — bump the constraint

Change only the `rails` gem in the `Gemfile` to the next version. Run
`bundle update rails` and let Bundler resolve. If it cannot, the conflict is the
finding — report which gem blocks the upgrade and what its maintained
alternatives are, rather than forcing the resolution.

### Step 3 — run `app:update`

```bash
bin/rails app:update
```

This is interactive and it will offer to overwrite config files. **Never accept
blindly.** For each conflict, diff and take only the framework changes, keeping
application-specific configuration. Pay special attention to `config/routes.rb`,
`config/application.rb`, and anything under `config/initializers/`, which are
frequently customized.

### Step 4 — leave the defaults alone for now

`app:update` writes `config/initializers/new_framework_defaults_X_Y.rb`, with
every new default commented out. **Leave them commented.** Keep
`config.load_defaults` at the old version.

This is the single most useful property of the Rails upgrade mechanism: it lets
you separate "running on the new version" from "adopting the new behaviour".
Doing both at once means a failure could be either, and you cannot tell which.

### Step 5 — get green

Run the suite. Fix failures. Work through deprecation warnings now rather than
later — they are next version's breaking changes, and they are cheapest to fix
while you are already in this code.

Commit here. This is a working state worth having.

### Step 6 — adopt new defaults, one at a time

Now uncomment the entries in `new_framework_defaults_X_Y.rb` **individually**,
running the suite after each. When they all pass, raise
`config.load_defaults` to the new version and delete the initializer.

Some defaults change behaviour in ways tests do not catch — cookie serialization
and cache key formats are the classic examples, and they surface in production
as logged-out users or cold caches. Flag those explicitly and recommend a
deploy-time plan rather than assuming a green suite means it is safe.

Commit again, separately from Step 5.

### Step 7 — repeat

Move to the next rung. Do not skip ahead because the last one was easy.

## Rules

- **One version per branch, one commit per phase.** When something breaks three
  rungs later, you need to bisect to a single change.
- **Never edit the lockfile by hand.**
- **A failing suite stops the ladder.** Do not proceed to the next version to see
  if it "fixes itself". It does not.
- **Report blockers instead of routing around them.** An abandoned gem with no
  successor is a decision for a human, not something to monkey-patch past.

## Reporting

After each rung, report: version moved from and to, how many tests were failing
at peak and what caused them, which new defaults were adopted versus deferred
and why, and any deprecation warnings introduced that the next rung will turn
into errors.
