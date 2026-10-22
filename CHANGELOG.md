# Changelog

## Unreleased

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

## 0.1.0

- Initial release.
