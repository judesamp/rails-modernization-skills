---
name: dependency-security-fixer
description: Triage and remediate dependency vulnerability alerts in bulk, grouping by root cause rather than working the list one by one. Use when the user has a backlog of Dependabot or security alerts, mentions CVEs in dependencies, bundle audit findings, or asks how to clear hundreds of vulnerability alerts.
---

# Dependency Security Fixer

For clearing a large backlog of dependency vulnerability alerts — hundreds
rather than a handful. Works the backlog by root cause, because a long alert
list is usually a much shorter list of underlying problems.

## Why not just take the Dependabot PRs

Merging alerts one at a time in an old codebase produces churn without
convergence: each merge re-resolves the lockfile, invalidates the others, and
the queue regenerates. Worse, alert count is a bad priority signal — a critical
CVE in a gem only loaded in development matters far less than a moderate one in
your request path.

Group first, then fix.

## Step 1 — get the real inventory

```bash
bundle exec bundle-audit check --update    # or: bundle audit
```

Cross-reference with the platform's alert list (`gh api` for GitHub). The two
disagree more often than you would expect — the platform sees the lockfile, and
`bundle-audit` sees the advisory database.

## Step 2 — group by root cause

This is the step that turns hundreds of alerts into a handful of decisions.

**By transitive parent.** Most alerts are not in gems you chose. Run
`bundle viz` or walk `Gemfile.lock` to find which direct dependency pulls the
vulnerable gem in. Twenty alerts frequently resolve to two parent upgrades.

**By framework version.** In an old Rails app a large share of alerts are Rails
components — `actionpack`, `activerecord`, `activesupport`. These do not get
fixed individually; they get fixed by upgrading Rails. If that is the case,
**say so and stop**: the correct next action is `rails-upgrader`, not patching
gems one at a time.

**By exploitability, not severity.** For each group establish whether the
vulnerable code path is actually reachable:

- Is the gem in a `:development`/`:test` group? Real, but not urgent.
- Is the vulnerable function ever called? Grep for it.
- Does exploitation require input the application never accepts?

A moderate CVE in request-path code outranks a critical one in a build tool.

## Step 3 — fix in order

1. **Direct dependencies with a safe patch release.** Cheapest, safest.
   `bundle update <gem> --conservative` bumps only what is needed.
2. **Transitive dependencies via their parent.** One upgrade, many alerts.
3. **Gems needing a major bump.** These carry breaking changes — one per commit,
   suite green between each.
4. **Gems with no fixed version.** Abandoned upstream. This is a decision, not a
   task: replace the gem, vendor and patch it, or accept and document the risk.
   **Report it rather than choosing unilaterally.**

Run the full suite after every group, not at the end.

## Step 4 — leave the door shut

Clearing the backlog is worthless if it refills. Before finishing, confirm:

- Automated dependency updates are enabled and configured to group minor and
  patch bumps into single PRs rather than one per gem.
- CI runs a dependency audit on every pull request, so new vulnerable
  dependencies fail the build rather than becoming next quarter's backlog.

## Rules

- **Never bump a major version to clear an alert without reading the changelog.**
  A security fix is not worth a silent behaviour change.
- **Never edit `Gemfile.lock` by hand.**
- **Do not mix groups in one commit.** When something breaks you need to know
  which upgrade did it.
- **If most alerts trace to the framework, stop and recommend the framework
  upgrade instead.** Patching around an old Rails is wasted effort.

## Reporting

Report: total alerts at start and end, how they grouped by root cause and how
many each fix resolved, anything deferred with the reason, any gem with no fixed
version and the options for it, and whether automated updates plus CI auditing
are now in place.
