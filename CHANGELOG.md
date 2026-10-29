# Changelog

## 0.1.0 - 2026-10-29

- Add optional parallel execution with `--jobs N` or YAML/API `jobs`, keeping one
  worker as the default. Each worker receives a copy of the verified baseline;
  errors and interruption cancel active commands and clean up all copies.
- Preserve source order in parallel API/JSON results, including partial errors,
  while serializing live progress callbacks on the calling thread. Check the
  independent RSpec/Minitest corpus with both one and two workers.
- Run baselines and mutations in isolated copies by default, preserving uncommitted
  project files and original report paths/IDs. Add configurable copy exclusions,
  Bundler path rebasing and an explicit `isolation: false` compatibility mode.
- Verify cleanup and original-source protection, including forced termination;
  reject linked paths, special files and source globs that escape the snapshot.
- Stream baseline and mutation progress, with IDs, survivor expression diffs and
  rerun arguments; select one mutation using `--mutation ID` or YAML.
- Add versioned JSON reports (`--format json`) with separate progress output,
  captured test output and explicit partial-error reports. Interruptions exit 130.
- Add optional Ruby API progress callbacks and declare the JSON runtime dependency.
- Mutate equality (`==`, `!=`) and strict/inclusive boundaries (`>`, `>=`, `<`, `<=`).
- Add an independent comparison acceptance corpus for RSpec and Minitest, checking
  exact kills and survivors against strong and deliberately weak test suites.
- Support maintained CRuby 3.3, 3.4 and 4.0; raise the minimum from 3.1 to 3.3.
- Replace the runtime parser dependency with Prism and remove OpenStruct.
- Refresh dependencies and add cross-platform CI, coverage and self-mutation gates.
- Add the documented `moots` executable and validated, safe YAML configuration.
- Replace exactly one operator by byte location, preserving repeated expressions,
  multiline source, encodings, comments and line endings.
- Support keyword boolean operators and explicit arithmetic operator calls.
- Require a passing baseline and restore original source even after execution errors.
- Add command deadlines, output capture and process cleanup; distinguish operational
  errors from killed mutations and fail empty mutation runs.
- Expand unit and subprocess integration tests with full runtime line/branch coverage.
