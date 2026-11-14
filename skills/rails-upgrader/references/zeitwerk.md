# Zeitwerk migration (the 6.0 step)

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

## Migrating the autoloader

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

## Verify with eager loading

`zeitwerk:check` passing is necessary, not sufficient. Confirm the application
actually boots with everything loaded, the way production does:

```bash
RAILS_ENV=production bin/rails zeitwerk:check
bin/rails runner 'Rails.application.eager_load!'
```

Then set `config.autoloader = :zeitwerk` (or remove the line, since it is the
6.0 default), run the suite, and commit separately.

**Finish the migration before starting the 7.0 step.** The classic autoloader is
deprecated in 6.1 and removed in 7.0, so the debt comes due either way. Pay it
on 6.0 if you can, and on 6.1 at the latest, while the escape hatch still
exists.
