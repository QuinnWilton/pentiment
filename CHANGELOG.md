# Changelog

All notable changes to this project are documented in this file.

## 0.2.0

### Added

- Cross-file label rendering. Labels with `:source` set now render as
  continuation frames (`├─[file:line:col]`) against their own file, inside
  the same diagnostic frame: the report's own file opens with `╭─[...]`,
  each additional file gets its own header, context lines, bracket gutters,
  and `Search`/`Byte` span resolution against its own source, and a single
  `╰─────` closes the frame. Groups whose source is missing from the
  provided sources render header-only. The `Label` `:source` field was
  previously documented for multi-file diagnostics but ignored by the
  renderer — cross-file labels rendered at their line numbers in the
  report's primary file.
- `CHANGELOG.md` (this file).

### Changed

- `Pentiment.Formatter.Compact` locations now name the first label's own
  `:source` when set, falling back to the report's source.

### Compatibility

- Diagnostics whose labels set no `:source` (or set it equal to the
  report's source) render byte-identically to 0.1.5; a golden test pins
  this.

## 0.1.5 and earlier

No changelog was kept before 0.2.0; see the git history.
