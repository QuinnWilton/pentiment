# Changelog

All notable changes to this project are documented in this file.

## 0.2.0

### Added

- Syntax highlighting of source context lines, powered by the optional
  makeup lexers: consumers add `{:makeup_elixir, "~> 1.0"}` and/or
  `{:makeup_erlang, "~> 1.0"}` to their own deps to enable it; without
  them, diagnostics render unhighlighted. The palette is restrained
  (comments dim, literals in subtle colors, never red/yellow) so label
  pointers stay visually dominant.
- `:syntax` format option (default `:auto`: highlight when colors are
  active, a highlighter is available, and the source's language is known;
  `false` disables).
- `:highlighter` format option and the `Pentiment.Highlighter` behaviour
  for custom highlighters (default: `Pentiment.Highlighter.Makeup`).
- `Pentiment.Source` `:language` field (`:elixir | :erlang | nil`),
  inferred from the source name's extension by the constructors, with a
  `:language` option to override.
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

- Highlighting never reaches `colors: false` output; the existing golden
  tests pin this. It is strictly subordinate to the colors gate —
  `colors: false` remains the single plain-text switch.
- Stripping ANSI escapes from highlighted output yields the plain output
  exactly (golden + property tested), so highlighting can never change
  visible characters or pointer alignment.
- Diagnostics whose labels set no `:source` (or set it equal to the
  report's source) render byte-identically to 0.1.5; a golden test pins
  this.

## 0.1.5 and earlier

No changelog was kept before 0.2.0; see the git history.
