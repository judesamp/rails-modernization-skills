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
   stop and say so** — the correct next step is
   [`test-coverage-writer`](../test-coverage-writer/SKILL.md), concentrated on
   the code this upgrade will touch. Coverage is the only thing standing between
   an upgrade and a silent behaviour change. Recommending coverage work first is
   a legitimate outcome of running this skill.
3. **The real blocker.** Applications are rarely pinned by Rails itself. Check
   for: a JavaScript runtime tied to Sprockets, template languages with no
   maintained successor (Haml variants, Slim forks), gems abandoned before the
   target version, and anything monkey-patching Rails internals.
   Run `bundle outdated --strict` and look for gems with no release in years.
4. **The upgrade path.** Rails does not support skipping majors. Enumerate the
   ladder — 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 — and say how many rungs there are.

## The loop, one rung at a time

For each version in the path, in order. Never batch two rungs.

### Step 1 — fetch the actual upgrade guide

**Retrieve the official guide. Do not work from recollection.** Version-specific
breaking changes are precisely the kind of detail a model reproduces
confidently and incorrectly, and a wrong list is worse than no list because it
sends you looking for problems that do not exist while missing ones that do.

Primary source, which has a section per version pair:

```
https://guides.rubyonrails.org/upgrading_ruby_on_rails.html
```

Also worth pulling for the target version: the release notes guide
(`https://guides.rubyonrails.org/X_Y_release_notes.html`) and, when a change is
ambiguous, the CHANGELOG in the relevant Rails component.

Then narrow it to this codebase:

1. Extract the changes for **this rung only**. Ignore everything for later
   versions — you will read those guides when you get there.
2. For each change, **grep for the affected API** to confirm it actually applies.
   Most of any guide is irrelevant to any given application.
3. Produce a written checklist of the ones that survive.
4. **Work the checklist one item at a time**, running the suite after each. Do
   not batch them — when something breaks you want one candidate cause.

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

### Step 5 — get green, then clear deprecations one at a time

Run the suite and fix the failures.

Then deprecations, which matter more than they look: **they are the next rung's
breaking changes, arriving early with a free warning attached.** Clearing them
now is far cheaper than meeting them as errors two versions later, and you are
already in this code.

Read them from the logs rather than from scrollback, and **deduplicate before
fixing anything** — one deprecated call in a shared helper produces hundreds of
identical lines and makes the problem look far larger than it is:

```bash
grep "DEPRECATION WARNING" log/test.log | sort | uniq -c | sort -rn
```

That gives you a ranked list of **distinct messages**. Work it one message at a
time, re-running the suite after each. Fix by message, not by occurrence: one
message is one change applied everywhere it appears — the same fix-the-class-not-
the-instance discipline the rest of this toolkit uses.

To make them impossible to ignore, promote them to failures for the duration of
the upgrade:

```ruby
# config/environments/test.rb
config.active_support.deprecation = :raise
```

Aggressive, and the fastest route to zero. Revert it afterwards if the noise
during normal development is unwelcome.

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

## The 6.0 rung is different: Zeitwerk

Rails 6.0 replaced the classic autoloader with Zeitwerk, which enforces a strict
correspondence between file paths and constant names. On a mature codebase this
is routinely harder than every other rung combined, and it fails in a
particularly nasty way: **lazy loading in development hides problems that eager
loading in production surfaces immediately.**

Apply the same principle as framework defaults — separate "on the new version"
from "using the new behaviour":

```ruby
# config/application.rb
config.autoloader = :classic
```

**Get to 6.0 on the classic autoloader first.** Green suite, commit, done. Then
migrate the autoloader as its own change. Doing both at once means a failure
could be either.

### Migrating the autoloader

```bash
bin/rails zeitwerk:check
```

Run it repeatedly; it reports one class of problem at a time. What it typically
finds, roughly in order of frequency:

- **File and constant disagree.** `app/models/user.rb` must define `User`.
  Legacy codebases accumulate files defining something else, or nothing at all.
- **Acronyms.** `app/services/api/client.rb` resolves to `Api::Client`, not
  `API::Client`. Either rename the constant or register an inflection:
  ```ruby
  # config/initializers/inflections.rb
  ActiveSupport::Inflector.inflect { |inflect| inflect.acronym "API" }
  ```
- **Files defining no constant.** Monkey patches and initializer-ish code living
  under `app/`. Move them to `lib/` or `config/initializers/` — Zeitwerk expects
  every managed file to define the constant its path implies.
- **`require_dependency`.** Remove it. It exists for the classic autoloader and
  is meaningless under Zeitwerk.
- **Directories that should not be namespaces.** A `app/services/concerns`
  directory implies a `Concerns::` module. Use `collapse` if that is not wanted:
  ```ruby
  Rails.autoloaders.main.collapse("app/services/concerns")
  ```
- **Explicit `require` of autoloadable files.** Under Zeitwerk this produces
  duplicate constant definitions. Let the autoloader do it.

### Verify with eager loading

`zeitwerk:check` passing is necessary, not sufficient. Confirm the application
actually boots with everything loaded, the way production does:

```bash
RAILS_ENV=production bin/rails zeitwerk:check
bin/rails runner 'Rails.application.eager_load!'
```

Then set `config.autoloader = :zeitwerk` (or remove the line, since it is the
6.0 default), run the suite, and commit separately.

**Do not proceed to 6.1 while still on the classic autoloader.** It was removed
in Rails 7, so the debt comes due either way — and it is far cheaper to pay on
6.0, where the escape hatch still exists, than on 7.0, where it does not.

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
