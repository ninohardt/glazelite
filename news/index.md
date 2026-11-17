# Changelog

## glazelite 0.1.2

- First release prepared for CRAN.
- All exported functions now document their return value and have
  runnable examples.
- [`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
  returns an object of class `c("glazelite_json", "json")` that prints
  as plain JSON text.
- The package has a logo and a website at
  <https://ninohardt.github.io/glazelite/>.
- [`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
  opens a connection that is not yet open once, instead of re-reading
  its first page indefinitely, and rejects inputs that are neither a
  path nor a connection.
- [`fromJSON()`](https://ninohardt.github.io/glazelite/reference/fromJSON.md),
  [`read_json()`](https://ninohardt.github.io/glazelite/reference/read_json.md)
  and
  [`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
  now simplify arrays to vectors and data frames in C++ while converting
  the parsed document, which makes reading several times faster than
  before.
- Simplification follows the JSON structure: `[[1], [2]]` is a list of
  two vectors instead of a vector, an array of arrays of records is a
  list of data frames, integer arrays containing `null` stay integer,
  and `[{}, {}]` is a data frame with two rows and no columns.
- [`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
  without a `handler` reads all lines and parses them together;
  `pagesize` applies to pages passed to a `handler`.
- Data frames with matrix columns or data-frame columns are written one
  row at a time as nested arrays or records instead of using only their
  first column, and data frames whose columns differ in length are
  rejected.
- [`fromJSON()`](https://ninohardt.github.io/glazelite/reference/fromJSON.md)
  and
  [`read_json()`](https://ninohardt.github.io/glazelite/reference/read_json.md)
  now reject truncated documents, input with content after the document,
  and empty input, instead of returning a partial result.
- File paths are tilde-expanded.
- Interrupting a long write no longer leaves the output file open;
  errors and interrupts are raised only after the native writer has
  released its resources.
- Bundle only the Glaze headers needed for JSON, and credit the authors
  of the third-party code contained in Glaze (see `inst/COPYRIGHTS`).

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
