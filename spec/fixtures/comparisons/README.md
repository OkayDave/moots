# Comparison acceptance fixture

This standalone project has no dependency on Moots. Its subject contains exactly
six comparison sites. The cases are handwritten expected outcomes, shared by
two real test runners; they do not use Moots' operator maps or inspect source.

From this directory, with the repository's bundle active:

```sh
bundle exec ruby run_rspec.rb strong
bundle exec ruby run_rspec.rb weak
bundle exec ruby run_minitest.rb strong
bundle exec ruby run_minitest.rb weak
```

All four original suites pass. Strong suites cover below, at and above each boundary
and must kill all six mutations. Weak suites omit equality cases: they still
kill `==`/`!=` inversions, but must leave all four boundary mutations alive.

The acceptance spec copies this project into a temporary directory before running
Moots. Only `lib/comparison_rules.rb` is mutated. Every result, expression change,
source location and restored project file is checked against explicit expectations.
