# Reporting contract (schema version 1)

Run `bundle exec moots --format json > moots-report.json`. Standard output is
one JSON document; progress is flushed to standard error. The normal exit codes
still apply: 0 for a nonempty all-killed run, 1 for survivors or no mutations,
2 for operational errors, and 130 for interruption. Help/version requests print
their usual text instead of JSON. Put `--format json` before other arguments if
you also need option-parsing errors in JSON.

## Document fields

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer | Currently `1` |
| `status` | string | `completed` or `error` |
| `summary.mutations` | integer | Number of completed mutation tests |
| `summary.killed` | integer | Completed mutations that failed their tests |
| `summary.survived` | integer | Completed mutations that passed their tests |
| `results` | array | Completed results in execution order |
| `error` | string | Present on errors; describes why execution stopped |

Each result has these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | 16 lowercase hexadecimal characters identifying the mutation |
| `file` | string | Source path relative to the project working directory |
| `line` | integer | One-based line containing the changed operator |
| `start_offset` | integer | Zero-based byte offset of the replaced expression |
| `original` | string | Original expression |
| `mutated` | string | Replacement expression |
| `status` | string | `killed` or `survived` |
| `test_output` | string | Captured output from this mutation's test command |
| `rerun` | array of strings | Executable and literal arguments for rerunning this mutation |

IDs are the first 16 hexadecimal characters of SHA-256 over the compact JSON
array `[relative_path, start_offset, original_hex_bytes, mutated_hex_bytes]`.
Identical source at the same relative path has the same ID across checkouts.
The reported line describes the operator, while the byte offset describes the
whole replaced expression; these can start on different lines.

## Reproduction

From the original working directory, using the same source revision:

```sh
bundle exec moots --mutation MUTATION_ID
bundle exec moots --config config/moots.yml --mutation MUTATION_ID
```

The `rerun` array preserves the configuration path, including spaces, without
shell-specific quoting. A Ruby consumer can execute a result from its own report
with `system(*result.fetch("rerun"))`. The baseline is always checked again.
Missing IDs are errors, including when source changes invalidate an earlier ID.

## Failure and encoding

An error document retains results completed before the failure. Its summary is
not a score for the whole intended run. A failed or interrupted mutation is not
recorded as killed or survived. A failed baseline has an empty results array.
Hard termination cannot produce a final document.

Report strings are decoded as UTF-8 with invalid bytes replaced by `�`. IDs use
the exact source bytes. The test runner combines stdout/stderr and trims leading
and trailing whitespace before storing `test_output`.
