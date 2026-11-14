---
name: rails-upgrader
description: Upgrades a Rails application one minor version at a time in a fixed order (Ruby prerequisite, prep on the current version, bump, app:update, green suite, deprecations, framework defaults one by one, load_defaults, deploy). Use when the user wants to upgrade Rails, is stuck on an old Rails version, asks how to get from an old Rails to a current one, or mentions app:update, load_defaults, new_framework_defaults, Zeitwerk or the classic autoloader.
argument-hint: "[target-rails-version]"
allowed-tools: Bash(ruby ${CLAUDE_SKILL_DIR}/scripts/*)
---

# Rails Upgrader

Moves a Rails application forward one minor version at a time, keeping the
suite green at every step. Built for applications several versions behind,
where a direct jump is not survivable.

**The order of work is the method.** Each step below exists so that when
something breaks there is exactly one candidate cause. Do not reorder steps,
merge them, or start the next Rails version before the current one is finished
and deployed.

## Before touching anything

Run the preflight from the application root:

```bash
ruby ${CLAUDE_SKILL_DIR}/scripts/preflight.rb . $ARGUMENTS
```

It reports the current Rails and Ruby, whether the last upgrade step was left
unfinished (`load_defaults` behind the Rails version, a leftover
`new_framework_defaults_*.rb`, the classic autoloader), and the ordered list of
steps to the target, marking each one that needs a Ruby upgrade first. **If it
lists anything under "Finish first", that is the first job.**

Then establish two more facts and report all of it:

1. **Test coverage.** Run the suite and get a real number. **Below roughly 60%,
   stop and say so**: the next step is
   [`test-coverage-writer`](../test-coverage-writer/SKILL.md), concentrated on
   the code this upgrade will touch. Recommending coverage work first is a
   legitimate outcome of this skill.
2. **The real blocker.** Applications are rarely pinned by Rails itself. Look
   for a JavaScript toolchain tied to Sprockets, template languages with no
   maintained successor, gems abandoned before the target version, and anything
   monkey-patching Rails internals. `bundle outdated --strict` and gems with no
   release in years are the starting point.

## Where the knowledge for each step comes from

Version-specific breaking changes are exactly the detail a model reproduces
confidently and wrongly. **Never work a step from memory.**

- **If preflight found a playbook** (a directory of per-step files, located by
  `RAILS_UPGRADE_PLAYBOOK` or `~/.claude/rails-upgrade-playbook`), read
  `steps/rails-X.Y-to-A.B.md` for this step only. Follow its "Order of
  operations"; use its other sections as the checklist. If the playbook has a
  `bin/scan`, run it (`<playbook>/bin/scan . rails-X.Y-to-A.B`) to list where
  the step's changes appear in this codebase.
- **Otherwise, fetch the official sources for this step:** the section for this
  version pair in https://guides.rubyonrails.org/upgrading_ruby_on_rails.html,
  the release notes at `https://guides.rubyonrails.org/A_B_release_notes.html`,
  and the component CHANGELOGs when a change is ambiguous.

Either way, narrow it to this codebase: for each listed change, **grep for the
affected API** to see whether it applies. Most of any guide is irrelevant to any
one application. Write down the changes that survive.

## The order of work for one step

Copy this checklist into the conversation for each step and tick it off. One
step per branch; a commit at the end of every numbered item.

```
Rails X.Y -> A.B
- [ ] 1. Ruby is supported by both X.Y and A.B (otherwise: ruby-upgrader first, deployed)
- [ ] 2. Prep on X.Y: latest X.Y patch, zero deprecation warnings, gems on versions supporting both
- [ ] 3. Bump rails to the latest A.B patch, bundle update rails
- [ ] 4. bin/rails app:update, keeping load_defaults at X.Y
- [ ] 5. Suite green on A.B
- [ ] 6. Deprecations new in A.B cleared
- [ ] 7. new_framework_defaults_A_B.rb adopted one entry at a time
- [ ] 8. load_defaults A.B, initializer deleted
- [ ] 9. Deployed and soaked
```

### 1. Ruby first, separately

Each Rails version has a minimum Ruby, and old Rails versions have a highest
Ruby they support. If the current Ruby is not supported by **both** the current
and the target Rails, upgrade Ruby first with
[`ruby-upgrader`](../ruby-upgrader/SKILL.md), on the current Rails, and deploy
it. **Never bump Ruby and Rails in the same commit or the same deploy.**

### 2. Prep on the current version

All of this happens before the Rails constraint changes, while the app still
runs on the version it is known to work on:

- **Move to the latest patch release of the current minor.** This is the first
  step of the official upgrade process: patch releases carry fixes and,
  sometimes, deprecation warnings for what the next minor removes.
- **Get the deprecation count to zero.** Today's deprecations are the next
  version's removals. Fix them here, where they are warnings, not after the
  bump, where they are errors.
- **Move gems to versions that support both the current and the target Rails.**
  Do these one gem (or one tight group) per commit, suite green between each.
  Gems that only support the new version are noted for step 3.

How to work deprecations: read them from the log, not from scrollback, and
deduplicate first. One deprecated call in a shared helper produces hundreds of
identical lines.

```bash
ruby ${CLAUDE_SKILL_DIR}/scripts/warnings.rb --sites log/test.log
```

Fix by message, not by occurrence: one message is one change applied
everywhere it appears. Re-run the suite after each. To make them impossible to
miss during the upgrade, set `config.active_support.deprecation = :raise` in
`config/environments/test.rb` (on 7.1+, also consider
`Rails.application.deprecators.behavior = :raise`).

### 3. Bump the constraint

Change only the `rails` gem in the `Gemfile`, to the latest patch of the next
minor, plus any gem noted in step 2 that must move with it. Run
`bundle update rails`. If Bundler cannot resolve, **the conflict is the
finding**: report which gem blocks the upgrade and its maintained alternatives
rather than forcing the resolution.

### 4. Run `app:update`, keep the old defaults

```bash
bin/rails app:update
```

It offers to overwrite config files. **Never accept blindly.** Diff each one
and take only the framework changes, keeping application-specific
configuration; `config/application.rb`, `config/routes.rb`, the environment
files and `config/initializers/` are usually customized. Decline new-app
extras (deployment tooling, CI templates, new asset toolchains): they are
separate decisions, not part of the upgrade.

It also writes `config/initializers/new_framework_defaults_A_B.rb` with every
new default commented out. **Leave them commented and keep
`config.load_defaults X.Y`.** This separates "running on A.B" from "adopting
A.B's behaviour". Doing both at once means a failure could be either.

### 5. Get the suite green

If it is badly red, use
[`upgrade-failure-triage`](../upgrade-failure-triage/SKILL.md) rather than
working failures one by one: post-upgrade failures cluster, and two hundred of
them are usually four or five causes.

### 6. Clear the new deprecations

Same procedure as step 2. These are the next step's removals.

This is a working state worth deploying on its own: new Rails, old behaviour.

### 7. Adopt the new defaults one at a time

Uncomment the entries in `new_framework_defaults_A_B.rb` **individually**,
running the suite after each and committing each.

Some defaults change data that outlives a deploy: cookie and message
serialization, signed or encrypted cookie formats, key generator digests, cache
formats, encryption settings. Once written in the new format by new servers,
old servers (and a rollback) may not read it. **Each of these gets its own
deploy**, usually after a release that can read both formats; follow the
step's playbook entry or guide section for the exact sequence. A green suite
says nothing about these.

### 8. Raise `load_defaults`

When every entry is adopted, set `config.load_defaults A.B` and delete the
initializer. Run the suite. Commit.

### 9. Deploy, then soak

Deploy and watch errors and logs before starting the next step. **Do not start
the next step to see whether it fixes something.** It does not.

## Special cases

- **Rails 6.0 and Zeitwerk.** Get onto 6.0 on the classic autoloader first,
  then migrate the autoloader as its own change, before the 7.0 step. Read
  [references/zeitwerk.md](references/zeitwerk.md) when the target is 6.0, 6.1
  or 7.0 and `config.autoloader = :classic` is set, or when `zeitwerk:check`
  fails.

## Rules

- **One version step per branch, one commit per item.** When something breaks
  three steps later, you need to bisect to a single change.
- **Never bump Ruby and Rails together.**
- **Never edit the lockfile by hand.**
- **A failing suite stops the ladder.**
- **Report blockers instead of routing around them.** An abandoned gem with no
  successor is a decision for a human, not something to monkey-patch past.

## Reporting

After each step, report: versions moved from and to, the Ruby it ran on, how
many tests failed at peak and the causes, which defaults were adopted and which
were deferred and why (with any that need a staged deploy), and the deprecation
count at the end.
