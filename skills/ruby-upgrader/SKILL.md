---
name: ruby-upgrader
description: Upgrade the Ruby version of a Rails or Ruby application, with particular attention to the Ruby 3.0 keyword-argument separation. Use when the user wants to upgrade Ruby, is on Ruby 2.x, mentions keyword argument errors, ArgumentError about wrong number of arguments after an upgrade, or asks about Ruby 3 migration.
---

# Ruby Upgrader

Moves a Ruby application to a newer Ruby, one minor version at a time. Most of
the difficulty in any 2.x → 3.x move is a single change, so this skill front-loads
it.

## The one that matters: keyword arguments

Ruby 3.0 separated positional and keyword arguments. In Ruby 2.x a trailing hash
was silently converted into keyword arguments; in 3.0 it is not. This is the
change that touches the most call sites in a mature codebase, and it fails at
**runtime**, not at boot — so a green boot means nothing.

```ruby
def configure(name, **options); end

configure("thing", {timeout: 5})   # Ruby 2.7: works, warns.  Ruby 3.0: ArgumentError
configure("thing", timeout: 5)     # correct in both
configure("thing", **opts)         # correct when opts is a hash
```

### Use 2.7 as the detector

Ruby 2.7 warns about exactly the code 3.0 breaks. This makes it a free
correctness pass, and it is the reason not to jump straight to 3.x.

```bash
RUBYOPT="-W:deprecated" bundle exec rails test 2>&1 | grep -i "keyword"
```

Fix every warning on 2.7 before going to 3.0. **A clean 2.7 deprecation run is
the gate.** Do not proceed while any remain — each one is a production
`ArgumentError` waiting for the right request.

Watch for these specifically, as they are easy to miss:

- `delegate` and `method_missing` forwarding that passes `*args` — needs `...`
  or explicit `**kwargs`
- Service objects and command classes taking `(args = {})` and reading keys
- Test helpers and factories passing option hashes positionally
- Any `send`/`public_send` with a trailing hash

## The path

Rungs, in order, never skipping:

**2.4 → 2.5 → 2.6 → 2.7 → 3.0 → 3.1 → 3.2 → 3.3**

2.7 is the important rung; the rest are usually quiet. 3.1 onward are generally
small, though check `Psych` 4 (`YAML.safe_load` became the default and
`load` no longer permits aliases — this bites Rails credentials and fixtures)
and the gems extracted from the standard library in 3.4.

## Procedure per rung

1. **Confirm the target is supported.** Check the Rails version's compatible
   Ruby range before choosing a target. Rails 6.1 and Ruby 3.2 is not a
   combination that works.
2. **Update the version everywhere.** `.ruby-version`, `Gemfile`,
   `Gemfile.lock` (via `bundle update --ruby`), Dockerfiles, and CI workflow
   files. **Search the whole repo for the old version string** — a stale pin in
   `Dockerfile.prod` or a workflow is the most common cause of "works locally,
   fails in CI".
3. **Reinstall and resolve.** Native extension gems frequently need newer
   versions for newer Rubies; `nokogiri`, `pg`, `ffi`, and `bcrypt` are the
   usual suspects.
4. **Run the suite with deprecations visible.**
5. **Fix, commit, move to the next rung.**

## Rules

- **Never skip 2.7.** It is the only version that tells you what 3.0 will break.
- **Grep the entire repository for the old version string**, including
  Dockerfiles, CI configs, and documentation. Version pins hide in surprising
  places.
- **A green suite on 3.0 is necessary but not sufficient.** Keyword-argument
  failures occur on paths tests do not cover. Weight extra scrutiny toward code
  that forwards arguments dynamically.
- **Do not upgrade Ruby and Rails in the same commit.** When something breaks
  you need to know which one did it.

## Reporting

Report: versions moved between, how many keyword-argument warnings existed on
2.7 and where they clustered, which gems required version bumps, every file
where a version string was updated, and any dynamic-forwarding code that should
get manual review because tests cannot reach it.
