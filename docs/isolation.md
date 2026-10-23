# Isolated working copies

`isolation: true` is the default for both the CLI and `Moots.run`. The project
root is the current working directory. Moots snapshots its current files, runs
the baseline and every mutation in the snapshot, then removes it. This does not
require Git and includes uncommitted changes and untracked files.

Files are copied independently, never hardlinked to the checkout. File bytes
and executable permissions are preserved. Hidden files and dependencies are
included. `.git`, `.hg` and `.svn` entries are always omitted at every depth.
Tests that need version-control metadata can use explicit in-place operation.

## Copy exclusions

```yaml
isolation: true
workspace_exclude:
  - tmp
  - coverage
  - pkg
  - .rspec_status
  - node_modules
```

Patterns match project-relative paths, with `/` as the separator. `*`, `**`,
brace alternatives and hidden names are supported. A matching directory omits
its entire subtree. `cache` matches the root cache directory; `**/cache` matches
cache directories at any depth. A custom list replaces the defaults. Use `[]`
to copy all ordinary files, including default-excluded directories.

`exclude` still only removes mutation targets. Tests, fixtures and support files
usually need to be copied even when they are excluded from mutation.

Links, directory junctions and special files are rejected with a diagnostic;
Moots does not follow or preserve them into the snapshot. Copy exclusions are
applied first, so unnecessary linked directories can be omitted explicitly.
Read failures and insufficient disk space abort the run and remove partial copies.

## Commands, Bundler and paths

The parent process keeps its original working directory and environment. Each
test subprocess starts in the snapshot. Relative paths therefore use the copied
files. Absolute project-local paths supplied as separate `test_command` array
arguments are rebased into the snapshot. External paths remain unchanged.
Use separate arguments for path-bearing options, for example `[ruby, -I, lib,
test.rb]`. Embedded paths such as `-I/checkout/lib` are not rewritten.

Moots also rebases project-local entries in `BUNDLE_GEMFILE`, `BUNDLE_APP_CONFIG`,
`BUNDLE_BIN_PATH`, `BUNDLE_PATH`, `GEM_HOME`, `GEM_PATH`, `RUBYLIB` and `PATH`,
including Bundler's saved `BUNDLER_ORIG_` values. Dependencies under `vendor/bundle`
are copied, preserving relative Bundler install paths. Dependencies outside the
project continue to be shared.

Shell command strings, Ruby snippets, `RUBYOPT`, configuration file contents and
other environment variables are not rewritten. Prefer relative paths in those
places. An absolute Bundler path or local gem override stored inside
`.bundle/config` can still point to the original project. Configure those paths
relatively, or use `isolation: false` when relocation is incompatible with the
project. Ensure the test command actually reloads the copied source; persistent
test preloaders are unsupported.

Include/exclude source globs must stay inside the project in isolated mode.
Results retain the original source paths and IDs; reported rerun commands should
be executed from the original project directory with the same source and config.

## Lifetime and limits

One temporary directory is used for the whole run. Source bytes are restored
between mutants; other files created by tests can persist until the run ends.
Tests should reset their own state between invocations. Cleanup runs on success,
failure, timeout and interruption. Hard termination can leave an orphan named
`moots-workspace-*` in the system temporary directory. The original source bytes
remain untouched by mutation writes even in that case.

The temporary directory must be outside the project to prevent recursive copying.
The snapshot is not atomic: avoid editing source while it is being copied.
Isolation does not confine test commands or isolate external databases/services.

`isolation: false` uses the original checkout and ignores copy exclusions. It
retains the previous source restoration behavior and its limits: force-killing
Moots or losing power while a mutation is active can leave a changed file. Use
a disposable checkout for this compatibility mode.
