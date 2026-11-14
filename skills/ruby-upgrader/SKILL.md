---
name: ruby-upgrader
description: Upgrades the Ruby version of a Rails or Ruby application one minor version at a time, placed correctly between Rails upgrade steps, with Ruby 2.7 used as the detector for the Ruby 3.0 keyword-argument break. Use when the user wants to upgrade Ruby, is on Ruby 2.x, sees keyword argument warnings or ArgumentError (wrong number of arguments) after an upgrade, hits Psych 4 YAML errors or missing net-smtp/base64-style bundled gems, or asks which Ruby a given Rails version needs.
argument-hint: "[target-ruby-version]"
allowed-tools: Bash(ruby ${CLAUDE_SKILL_DIR}/scripts/*)
---

# Ruby Upgrader

Moves an application to a newer Ruby, one minor version at a time. In a Rails
app the Ruby steps are interleaved with the Rails steps, and **where each Ruby
step sits is as important as how it is done.**

## Where a Ruby step sits

Two limits decide it:

- **The next Rails step's minimum Ruby.** From the official upgrade guide:
  Rails 5.x needs 2.2.2+, 6.x needs 2.5+, 7.0 and 7.1 need 2.7+, 7.2 needs
  3.1+, 8.0 and 8.1 need 3.2+.
- **The newest Ruby the current Rails is tested on.** Rails' own CI hard-tests
  Rails below 6.1 up to Ruby 2.7 and Rails below 8 up to Ruby 3.3; newer Rubies
  run there only as allowed-to-fail jobs. Beyond that ceiling you are the test.

So: **move Ruby before any Rails step that raises the minimum, and never past
what the current Rails is tested on.** Each Ruby step happens between two
finished Rails steps, on its own branch, with its own deploy. Never in the same
commit or deploy as a Rails bump: when something breaks you need to know which
one did it.

If `rails-upgrader`'s preflight is available, it prints both limits for every
step. If a playbook is present (`RAILS_UPGRADE_PLAYBOOK`, default
`~/.claude/rails-upgrade-playbook`), read `ruby/compatibility.md` for the
full pairing table and the Ruby file for this step under `ruby/`.

Two placements that catch people out:

- **Ruby 2.7 → 3.0** belongs after the keyword-argument warnings are cleared
  on 2.7, and on a Rails that supports 3.0 (6.1 is the safe choice).
- **Ruby 3.1** ships Psych 4, where `YAML.load` no longer loads aliases.
  Older Rails versions load `database.yml` with plain `YAML.load`, so a
  `database.yml` using `<<: *default` breaks. Ruby 3.1 also moved `net-smtp`,
  `net-imap` and `net-pop` out of the default gems. Do Ruby 3.1 on a Rails that
  handles both (7.0.1 or later), or add the workarounds deliberately.

## The order of work for one Ruby step

Copy this checklist for each step and tick it off, one commit per item:

```
Ruby X.Y -> A.B (on Rails R)
- [ ] 1. A.B is within the range Rails R is tested on
- [ ] 2. Prep on X.Y: latest X.Y patch; gems with native extensions or Ruby pins on versions that support A.B
- [ ] 3. Warnings for A.B's changes cleared on X.Y (on 2.7: keyword arguments)
- [ ] 4. Version bumped everywhere in one commit; bundle install
- [ ] 5. Suite green on A.B, warnings counted
- [ ] 6. Deployed (web, workers, cron) and soaked
```

### 1. Fetch the release notes. Do not work from memory

Which Ruby release changed what is exactly the detail a model reproduces
confidently and wrongly. Read the playbook's Ruby file for this step if there is
one; otherwise the release announcement on https://www.ruby-lang.org/en/news/ and
the `NEWS.md` for the target version. Take the incompatibilities for this step
only, grep for each, and keep the ones that apply.

### 2. Prep on the old Ruby

While still on the version that works: move to its latest patch, and move gems
that compile native extensions or pin Ruby (`nokogiri`, `pg`, `mysql2`, `ffi`,
`bcrypt`, `grpc`, `sassc` and the like) to versions that support both Rubies.
One gem per commit, suite green between each.

### 3. Clear the warnings that predict the break

The headline case is 2.7 → 3.0, below. For later steps, run the suite on the
old Ruby with deprecation warnings on and clear what the target removes.

### 4. Bump the version everywhere, in one commit

`.ruby-version`, the `ruby` line in the `Gemfile`, `Gemfile.lock` (via
`bundle update --ruby`), Dockerfiles, CI workflow files, `.tool-versions`, and
deployment config. **Search the whole repository for the old version string.**
A stale pin in `Dockerfile.prod` or a workflow is the most common cause of
"works locally, fails in CI".

```bash
# leaving 2.7, for example
git grep -n -E "2\.7(\.[0-9]+)?" -- ':!Gemfile.lock' ':!vendor' ':!node_modules'
```

### 5. Get the suite green

If it comes back badly red, use
[`upgrade-failure-triage`](../upgrade-failure-triage/SKILL.md): group failures by
signature before fixing any.

### 6. Deploy every process type, then soak

Web, background workers and scheduled jobs. A worker image left on the old Ruby
hides problems until the queue reaches the code that breaks.

## The one that matters: keyword arguments (2.7 → 3.0)

Ruby 3.0 separated positional and keyword arguments. In 2.x a trailing hash was
silently converted into keywords; in 3.0 it is not. It touches more call sites
than any other change, and it fails at **runtime**, not at boot.

```ruby
def configure(name, **options); end

configure("thing", {timeout: 5})   # Ruby 2.7: works, warns.  Ruby 3.0: ArgumentError
configure("thing", timeout: 5)     # correct in both
configure("thing", **opts)         # correct when opts is a hash
```

**Ruby 2.7 is the detector.** It warns about exactly the code 3.0 breaks. Since
2.7.2 these warnings are **off by default**, so turn them on explicitly:

```bash
RUBYOPT="-W:deprecated" bin/rails test 2>&1 \
  | ruby ${CLAUDE_SKILL_DIR}/scripts/warnings.rb --sites --match keyword
```

The script deduplicates by message and shows where each comes from. One call in
a shared helper emits the same warning hundreds of times; the distinct count is
the real backlog, and it is usually small. Work one message at a time.

**A clean 2.7 run with warnings on is the gate for 3.0.** Watch for:

- `delegate`, `method_missing` and other forwarding that passes `*args`; use
  `...` or explicit `**kwargs` (`ruby2_keywords` where it must also run on 2.6)
- Service objects taking `(args = {})` and reading keys
- Test helpers and factories passing option hashes positionally
- `send` / `public_send` with a trailing hash

A green suite on 3.0 is necessary, not sufficient: keyword failures occur on
paths tests do not reach. Review dynamic forwarding by hand.

## Later steps in brief

- **3.1:** Psych 4 and the `net-*` gems (above).
- **3.2, 3.3, 3.4, 4.0:** usually quieter. 3.4 moves more default gems
  (`base64`, `bigdecimal`, `mutex_m`, `drb`, `csv` and others) to bundled gems,
  which must then be in the `Gemfile`. Bootsnap can hide Bundler's warnings
  about them, so run the suite once with `DISABLE_BOOTSNAP=1` on the old Ruby.
  Check the release notes per step for removals.

## Rules

- **Never bump Ruby and Rails together.**
- **Never move Ruby past what the current Rails is tested on.**
- **Never skip 2.7** on the way to 3.x, and never leave it with keyword
  warnings outstanding.
- **Grep the entire repository for the old version string.**
- **Deploy every process type** before calling a step done.

## Reporting

Report: versions moved between and the Rails it ran on, gems that needed bumps,
every file where the version string changed, warning counts before and after
(for 2.7, the distinct keyword messages and where they clustered), and any
dynamic-forwarding code that needs manual review because tests cannot reach it.
