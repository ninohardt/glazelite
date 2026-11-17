# glazelite

`glazelite` is an early R package that uses [Glaze](https://github.com/stephenberry/glaze)
to encode and parse JSON. Its main use is writing JSON files larger than R's
single-string limit. `write_json()` writes an ordinary JSON document;
`stream_out()` writes newline-delimited JSON (NDJSON) from a data frame, list of
records, or function that supplies batches.

## Installation

```r
# once the package is on CRAN
install.packages("glazelite")

# development version from GitHub
# install.packages("remotes")
remotes::install_github("ninohardt/glazelite")

# from a source checkout
install.packages(".", repos = NULL, type = "source")
```

Building from source needs a C++23 compiler (see below) and R 4.3.0 or later.

## Usage

```r
library(glazelite)

write_json(data.frame(id = 1:3, name = c("A", "B", "C")), "data.json")

i <- 0L
stream_out(function() {
  i <<- i + 1L
  if (i > 100L) return(NULL)
  data.frame(batch = i, value = seq_len(1000L))
}, "data.ndjson")
```

The package also offers `toJSON()`, `fromJSON()`, `read_json()`, and `stream_in()`.
`toJSON()` returns an R string and therefore cannot exceed R's string limit.
`read_json()` avoids an input R string, but the parsed result still occupies
R memory. `stream_in()` processes NDJSON in pages; supply a `handler` to avoid
collecting the whole input.

## Current scope

This is a compatible subset, not yet a drop-in replacement for jsonlite.
Supported writing inputs are logical, integer, double, character, and factor
vectors; arrays of any dimension; lists; and data frames containing those
types, including matrix, list, and data-frame columns. Missing
data-frame fields are omitted in row layout, as in jsonlite's default output.
The `dataframe`, `auto_unbox`, `na`, `factor`, `always_decimal`, and `pretty`
options are implemented. `digits = NA` retains full round-trip numeric precision;
numeric rounding is not implemented. Unsupported R classes, complex and raw
vectors, and other jsonlite serialization options raise errors or are not
provided.

JSON parsing simplifies arrays of scalars of one type to atomic vectors and
arrays of records with scalar fields to data frames; the simplification is
done in C++ while converting the parsed document. It is narrower than
jsonlite's: there is no matrix simplification, arrays of mixed types stay
lists instead of being coerced to character, and records with nested fields
stay lists of records. Truncated documents and content after a document are
errors.

Arrays preserve dimension order and dimensions of length one or zero, without
transposing or copying the input. As with jsonlite, `auto_unbox = TRUE` keeps
dimensioned length-one vectors and values wrapped in `I()` as JSON arrays.
Factors default to labels; `factor = "integer"` writes their level indices.
`always_decimal = TRUE` retains a decimal point or exponent for doubles while
integer inputs and factor codes remain integers. Pretty printing also streams
through the bounded file buffer. `stream_out()` supports the factor and numeric
options while keeping each record on one line.

For data already validated and converted to atomic Stan inputs, use:

```r
write_json(stan_data, "data.json", auto_unbox = TRUE, factor = "integer",
           always_decimal = TRUE, na = "string")
```

Stan requires logical inputs to be converted to 0/1 and missing values to be
rejected beforehand, as in CmdStanR's data preparation. Standalone glazelite
keeps its general JSON defaults for logical and missing values.

Glaze's own stream writer can grow its buffer for a large string or numeric
array. The R writer here splits values and flushes to the file, keeping its
output buffer around 64 KiB. A single input R string still must fit R's own
limits. A generated batch need not be retained after `stream_out()` writes it.

## Credits and bundled code

All JSON encoding and parsing is done by
[Glaze](https://github.com/stephenberry/glaze), a header-only C++ library by
Stephen Berry, licensed under the MIT license. Glaze in turn contains code
from [fast_float](https://github.com/fastfloat/fast_float) (Daniel Lemire,
João Paulo Magalhaes and contributors), [zmij](https://github.com/vitaut/zmij)
(Victor Zverovich) and a constexpr xxh64 implementation (Daniel Kirchner).
Copyright holders and licenses are listed in `inst/COPYRIGHTS`.

The vendored Glaze headers are pinned to commit
`c5ed7ddc249a2c3d15ede60f985adf447aa11ed3` under `inst/include/glaze`; the
Glaze license is in `inst/include/GLAZE-LICENSE`. Only the headers reachable
from the JSON entry points are bundled, and pragmas that suppress compiler
diagnostics are removed to comply with CRAN policy.
`tools/vendor-glaze.R` reproduces both steps from a Glaze checkout.

Building requires a C++23 compiler; upstream currently tests with GCC 13+ and
Clang 19+.

## Verification

On the development host, a batch generator wrote an NDJSON file of
2,181,230,740 bytes in 7.86 seconds with peak process RSS of about 64 MiB.
The generated file was removed after the check. This verifies the file-size
path; it is not a general performance claim. A separate local benchmark of
one million doubles took 0.035 seconds with `glazelite::write_json()` versus
0.086 seconds with `jsonlite::write_json()` at its default settings. The two
files used different numeric precision, so those timings are directional.

## Performance

Median of seven runs in seconds on one Windows 10 machine (R 4.5.2, GCC 14.2,
glazelite 0.1.2, yyjsonr 0.1.22, jsonlite 2.0.0); in-memory conversion with
`toJSON()`/`fromJSON()` and their counterparts. jsonlite was called with
`digits = NA`. Treat the numbers as indicative only.

| Task                               | glazelite | yyjsonr | jsonlite |
|------------------------------------|----------:|--------:|---------:|
| Write 1e6 doubles                  |      0.09 |    0.07 |     0.86 |
| Write 1000 x 1000 double matrix    |      0.09 |    0.08 |     0.93 |
| Write data frame, 2e5 rows x 6     |      0.17 |    0.11 |     0.81 |
| Write nested list, 2e4 records     |      0.02 |    0.02 |     5.69 |
| Read 1e6 doubles                   |      0.08 |    0.03 |     0.94 |
| Read data frame, 2e5 rows x 6      |      0.25 |    0.11 |     1.53 |
| Read nested list, 2e4 records      |      0.04 |    0.01 |     0.30 |
