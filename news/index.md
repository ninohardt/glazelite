# Changelog

## glazelite 0.1.2

First release prepared for CRAN.

### Closer to jsonlite

- [`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
  writes `Date` objects and date-times (`POSIXct`, `POSIXlt`), with the
  `Date`, `POSIXt` and `UTC` arguments of jsonlite.
- New
  [`unbox()`](https://ninohardt.github.io/glazelite/reference/unbox.md)
  marks single values that should be written as scalars.
- `digits` rounds numbers as jsonlite does: a number gives decimal
  digits and `I(n)` significant digits. The default, `NA`, still keeps
  full precision.
- `NULL` is written as [`{}`](https://rdrr.io/r/base/Paren.html) by
  default (`null = "null"` writes `null`), list elements without a name
  are keyed by their position, and character row names of data frames
  are written as `_row` (see `rownames`).
- `pretty` also accepts the number of spaces to indent by.
- [`fromJSON()`](https://ninohardt.github.io/glazelite/reference/fromJSON.md),
  [`read_json()`](https://ninohardt.github.io/glazelite/reference/read_json.md)
  and
  [`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
  gain `simplifyMatrix`: regular arrays of arrays become matrices and
  higher-dimensional arrays, so `fromJSON(toJSON(x))` returns a matrix
  or array `x` unchanged.
- [`read_json()`](https://ninohardt.github.io/glazelite/reference/read_json.md)
  returns nested lists unless `simplifyVector = TRUE`, as in jsonlite.
  `simplifyDataFrame` and `simplifyMatrix` default to `simplifyVector`.
- New
  [`prettify()`](https://ninohardt.github.io/glazelite/reference/prettify.md),
  [`minify()`](https://ninohardt.github.io/glazelite/reference/prettify.md)
  and
  [`validate()`](https://ninohardt.github.io/glazelite/reference/prettify.md).
- [`stream_out()`](https://ninohardt.github.io/glazelite/reference/stream_out.md)
  and
  [`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
  take `con`, a file path or a connection, and accept `verbose`.
  [`stream_out()`](https://ninohardt.github.io/glazelite/reference/stream_out.md)
  can write to connections such as
  [`gzfile()`](https://rdrr.io/r/base/connections.html). The argument
  was called `path` before.
- [`write_json()`](https://ninohardt.github.io/glazelite/reference/write_json.md)
  and
  [`stream_out()`](https://ninohardt.github.io/glazelite/reference/stream_out.md)
  pass their options on to
  [`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
  through `...`.
- [`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
  returns an object of class `c("glazelite_json", "json")` that prints
  as plain JSON text.

### Reading

- [`fromJSON()`](https://ninohardt.github.io/glazelite/reference/fromJSON.md),
  [`read_json()`](https://ninohardt.github.io/glazelite/reference/read_json.md)
  and
  [`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
  simplify arrays to vectors, matrices and data frames in C++ while
  converting the parsed document, which makes reading several times
  faster than before.
- Simplification follows the JSON structure: an array of arrays of
  records is a list of data frames, integer arrays containing `null`
  stay integer, and `[{}, {}]` is a data frame with two rows and no
  columns.
- Truncated documents, input with content after the document, and empty
  input are rejected instead of returning a partial result.
- [`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
  without a `handler` reads all lines and parses them together;
  `pagesize` applies to pages passed to a `handler`. A connection that
  is not yet open is opened once, instead of re-reading its first page
  indefinitely.

### Writing

- Data frames with matrix columns or data-frame columns are written one
  row at a time as nested arrays or records instead of using only their
  first column, and data frames whose columns differ in length are
  rejected.
- An empty named list is written as
  [`{}`](https://rdrr.io/r/base/Paren.html).
- File paths are tilde-expanded.
- Interrupting a long write no longer leaves the output file open;
  errors and interrupts are raised only after the native writer has
  released its resources.

### Package

- All exported functions document their return value and have runnable
  examples.
- Bundle only the Glaze headers needed for JSON, and credit the authors
  of the third-party code contained in Glaze (see `inst/COPYRIGHTS`).
- The package has a logo and a website at
  <https://ninohardt.github.io/glazelite/>.

## glazelite 0.1.1

- Write one-dimensional and higher-dimensional atomic arrays in their
  existing dimension order, preserving singleton and empty dimensions
  without copying.
- Preserve length-one values wrapped in
  [`I()`](https://rdrr.io/r/base/AsIs.html) when `auto_unbox = TRUE`.
- Add `factor = "integer"` and `always_decimal` to the JSON and NDJSON
  writers.
- Add buffered `pretty` output to
  [`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
  and
  [`write_json()`](https://ninohardt.github.io/glazelite/reference/write_json.md).
- Accept `digits = NA` for full round-trip precision and reject
  unsupported rounding requests explicitly.
- Add regression checks for Stan-compatible shapes, types, and file
  streaming.
