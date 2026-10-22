# Moots

Moots is a small, MIT-licensed mutation testing tool for Ruby. It changes one
operator in your source, runs your tests in a fresh process, and reports whether
the tests caught the change.

A **killed** mutation made the tests fail. A **surviving** mutation left them
passing and is worth investigating: it may reveal a missing assertion, untested
behavior, or an equivalent change.

Moots is still an early project with a deliberately small set of mutation
operators. A perfect score measures those operators; it does not prove that a
program is correct.

## Ruby support

Supports CRuby **3.3, 3.4 and 4.0**, with a minimum of Ruby 3.3. These are the
[maintained Ruby series](https://www.ruby-lang.org/en/downloads/branches/).
CI runs all three on Linux and Ruby 4.0 on Windows and macOS.

Parsing uses [Prism](https://github.com/ruby/prism), including modern Ruby syntax.
The old `parser` gem only handles syntax through Ruby 3.3. Runtime dependencies
are Prism and JSON; development tools are kept in the Gemfile.

## Installation

Add Moots to your test/development bundle:

```ruby
group :development, :test do
  gem "moots"
end
```

For this unreleased checkout, use `gem "moots", path: "/path/to/moots"` instead,
or run `bundle exec rake install` here. Then run `bundle install`.

Windows installations need RubyInstaller's MSYS2 development toolchain to build
Prism and development dependencies (`ridk install`). This repository can also be
developed under WSL with a supported Linux Ruby.

## Usage

From the project root:

```sh
bundle exec moots
bundle exec moots --config config/moots.yml
bundle exec moots --format json > moots-report.json
bundle exec moots --mutation MUTATION_ID
bundle exec moots --help
```

Moots reads `.moots.yml` when present. Without it, the defaults below apply:

```yaml
include:
  - app/**/*.rb
  - lib/**/*.rb
exclude: []
test_command: bundle exec rspec
timeout: 60
mutation: null
```

Paths are relative to the current working directory, including when using an
explicit configuration path. Overlapping include patterns are deduplicated;
exclude patterns take precedence. Unknown options, malformed YAML and invalid
option values are errors.

`test_command` can also be an argument array, which passes arguments literally
without shell interpretation:

```yaml
test_command: [bundle, exec, rspec, spec/models]
```

The command must run the relevant tests in a fresh process and reload changed
source. Avoid persistent test preloaders such as Spring. A command that runs no
tests can still exit successfully; make sure your test runner rejects empty
suites when appropriate.

Exit statuses:

| Status | Meaning |
| --- | --- |
| 0 | At least one mutation, all killed (or help/version requested) |
| 1 | Survivors, or no mutations generated |
| 2 | Configuration, source, baseline or command execution error |
| 130 | Interrupted run |

## Progress, survivors and CI reports

Text output starts before the baseline tests run, then shows `[current/total]`
progress before each mutation's tests. Each result has an ID and a relative
`file:line` location. Survivors include an expression diff (`-` original, `+`
replacement) and a `Rerun argv` argument array. The diff covers the mutated
expression; it is not a patch for the whole file.

Use `--mutation ID` to run a reported mutation with a fresh baseline. It overrides
the optional `mutation` YAML setting. IDs use the relative file path, byte offset
and original/replacement bytes, so equivalent checkouts produce the same IDs.
Source edits can change IDs. An unknown ID is an error; it never silently runs
the full suite or reports success. Use the same working directory, configuration
and source revision when reproducing a result.

`--format json` writes one JSON document to stdout; progress and diagnostics go
to stderr. Test-process output is captured inside the document. The schema is
described in [docs/reporting.md](docs/reporting.md). It includes:

- `schema_version: 1` and `status: "completed"` or `"error"`.
- Summary counts and each completed mutation's ID, source location, expressions,
  killed/survived status, captured test output and rerun arguments.
- An `error` message on operational failure or interruption. Any partial results
  cover only completed mutations; an aborted run is never marked completed.

Completion does not mean all mutations were killed. Continue to check the exit
status (or the summary) in CI. Invalid UTF-8 in report text is replaced with `�`;
mutation identity and source restoration still use the original bytes.

## Mutation behavior

Supported replacements:

| Original | Replacement |
| --- | --- |
| `+` | `-` |
| `-` | `+` |
| `*` | `/` |
| `/` | `*` |
| `==` | `!=` |
| `!=` | `==` |
| `>` | `>=` |
| `>=` | `>` |
| `<` | `<=` |
| `<=` | `<` |
| `&&` | `||` |
| `||` | `&&` |
| `and` | `or` |
| `or` | `and` |

Each mutation changes exactly one operator token, including explicit operator
calls such as `a.+(b)`. Other operators on the same line, string contents,
comments and surrounding formatting are preserved. Byte offsets handle
multiline expressions, Unicode and CRLF files.

Boundary mutations switch between strict and inclusive comparisons, exposing
missing tests for the value exactly at a limit. Equality mutations invert the
comparison. Explicit calls such as `a.>=(b)` are supported too.

Compound assignments (`+=`, `&&=`, etc.), unary operators, other comparisons
(`===`, `<=>`, `=~`, `!~`), constants and method removal are not currently mutated.
Equivalent mutations are not automatically filtered.

## Execution and restoration

Moots first runs the original suite. A failing baseline aborts the run before
any source changes. It then processes source files sequentially and restores the
original bytes after every mutation using an `ensure` block, including when a
test command raises, times out or is interrupted.

Source read/write failures and invalid Ruby syntax are reported as errors;
they are not silently excluded from a score. Missing commands, shell execution
failures (exit 126/127), signal termination and timeouts are also errors rather
than successful kills. Other nonzero exits count as killed mutations.

The timeout applies to each test invocation, including the baseline. Standard
output and standard error are drained concurrently. On POSIX systems the runner
kills the process group on interruption or timeout; on Windows it uses
`taskkill /T /F` for the command's process tree.

Run in a disposable checkout or commit your work first. Moots edits selected
files in place; do not edit them or run another mutation job concurrently.
Hard process termination, power loss, a failed restoration write, or a child
that escapes its process group cannot be made safe by Ruby's `ensure` block.
Windows descendants whose parent has already exited may outlive tree cleanup.

## Ruby API

```ruby
require "moots"

results = Moots.run(
  include: ["lib/**/*.rb"],
  exclude: ["lib/generated/**/*.rb"],
  test_command: ["bundle", "exec", "rspec"],
  timeout: 60
)

results.each do |result|
  puts [result.mutation.file_path, result.mutation.line_number, result.killed].inspect
  puts result.test_result.output
end
```

`MutationGenerator#generate_mutations(code, file_path: "example.rb")` returns
mutations with original/replacement expressions and a byte offset.
`Mutation#apply(code)` returns a changed copy and rejects mismatched source.
`Mutation#id` returns the rerunnable ID; `Mutation#relative_path` returns its
project-relative path. Both accept an optional `root:` directory.
Directly constructed mutations now require `start_offset:`.
Invalid input raises `Moots::Error`; source I/O errors also propagate from the API.

An optional block receives progress hashes while `Moots.run` still returns the
results array. Events are `:baseline_started`, `:baseline_passed`,
`:mutation_started` (with `:mutation`, one-based `:index`, and `:total`) and
`:mutation_finished` (with `:result`, `:index`, and `:total`). Callbacks execute
before source modification or after restoration, and callback exceptions propagate.
After the baseline passes, Moots reads all selected source files to determine the
mutation count before executing any mutations.

## Development and verification

```sh
bundle install
bundle exec rake spec       # randomized RSpec suite
bundle exec rake acceptance # independent RSpec and Minitest comparison fixtures
bundle exec rake coverage   # 100% line and branch coverage, overall and per file
bundle exec rake rubocop
bundle exec rake mutation   # run Moots against all lib/**/*.rb files
bundle exec rake verify     # lint, coverage, then dogfood
bundle exec rake build
```

Coverage includes unloaded runtime files. Only `lib/moots/version.rb` is excluded,
because Bundler loads its release constant before coverage starts; the version
is checked separately. No runtime implementation file is excluded from
self-mutation. The mutation task disables coverage thresholds in child suites
so kills come from test failures rather than uncovered-line enforcement.

Tests use temporary projects, real subprocesses and controlled failures. They
exercise every supported operator, exact mutation locations, modern syntax,
encodings, configuration and CLI behavior, baseline validation, process output,
deadlines and byte-for-byte restoration. The integration suite proves that
strong tests kill mutations, weak tests leave survivors, and broken baselines
are rejected.

The [comparison acceptance corpus](spec/fixtures/comparisons/README.md) uses a
standalone subject with hand-written expected results, independent of Moots'
operator tables. RSpec and Minitest each run strong and deliberately weak suites.
The strong suites kill all six comparison mutations. The weak suites omit the
exact boundary: equality mutations still die, but all four boundary mutations
survive. These acceptance checks are also included in the normal spec suite.

The self-mutation run must generate at least one mutation and kill every one.
CI keeps this check on all supported Linux Ruby versions. Review surviving
mutations and improve behavioral assertions; do not exclude implementation
files just to get a green result.

## Contributing and license

Bug reports and pull requests are welcome at
[OkayDave/moots](https://github.com/OkayDave/moots).
Released under the [MIT License](LICENSE.txt).
Contributors must follow the [Code of Conduct](CODE_OF_CONDUCT.md).
