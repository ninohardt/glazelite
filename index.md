# glazelite

Fast JSON reading and writing for R, built on the
[Glaze](https://github.com/stephenberry/glaze) C++ library.

glazelite offers the familiar
[`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
/
[`fromJSON()`](https://ninohardt.github.io/glazelite/reference/fromJSON.md)
interface of [jsonlite](https://CRAN.R-project.org/package=jsonlite) for
the common cases, with the encoding and parsing done by Glaze, a
header-only C++23 library by Stephen Berry.

- **Familiar.** The same function names, arguments and output as
  jsonlite (see [A substitute for
  jsonlite](#a-substitute-for-jsonlite)).
- **Fast.** Typically 5 to 10 times faster than jsonlite for vectors and
  data frames, and far more for nested lists (see
  [Performance](#performance)).
- **Streams to disk.**
  [`write_json()`](https://ninohardt.github.io/glazelite/reference/write_json.md)
  and
  [`stream_out()`](https://ninohardt.github.io/glazelite/reference/stream_out.md)
  write incrementally, so a document can be larger than a single R
  string, which is limited to 2 GB.
- **Exact numbers.** Doubles are written with full round-trip precision.
- **Strict input.** Truncated documents and trailing content are errors,
  not partial results.

## Installation

``` r

# once the package is on CRAN
install.packages("glazelite")

# development version from GitHub
# install.packages("remotes")
remotes::install_github("ninohardt/glazelite")
```

Building from source needs R 4.3.0 or later and a C++23 compiler;
upstream Glaze currently tests with GCC 13+ and Clang 19+.

## Usage

### Convert R objects to JSON and back

``` r

library(glazelite)

toJSON(list(id = 1L, tags = c("a", "b"), ok = TRUE), auto_unbox = TRUE)
#> {"id":1,"tags":["a","b"],"ok":true}

df <- data.frame(id = 1:2, name = c("Ada", "Grace"), score = c(9.5, NA))
toJSON(df)
#> [{"id":1,"name":"Ada","score":9.5},{"id":2,"name":"Grace"}]

toJSON(df, dataframe = "columns", pretty = TRUE)
#> {
#>   "id": [1, 2],
#>   "name": ["Ada", "Grace"],
#>   "score": [9.5, null]
#> }

toJSON(array(1:8, c(2, 2, 2)))
#> [[[1,5],[3,7]],[[2,6],[4,8]]]
```

Arrays of records come back as data frames, and arrays of scalars as
vectors:

``` r

fromJSON('[{"id":1,"name":"Ada","score":9.5},{"id":2,"name":"Grace"}]')
#>   id  name score
#> 1  1   Ada   9.5
#> 2  2 Grace    NA

str(fromJSON('{"id": 1, "tags": ["a", "b"], "nested": {"ok": true, "x": [1.5, null]}}'))
#> List of 3
#>  $ id    : int 1
#>  $ tags  : chr [1:2] "a" "b"
#>  $ nested:List of 2
#>   ..$ ok: logi TRUE
#>   ..$ x : num [1:2] 1.5 NA
```

### Read and write files

``` r

path <- tempfile(fileext = ".json")
write_json(df, path)
read_json(path)
#>   id  name score
#> 1  1   Ada   9.5
#> 2  2 Grace    NA
```

[`write_json()`](https://ninohardt.github.io/glazelite/reference/write_json.md)
writes to a temporary file next to `path` and moves it into place when
it is complete, so a failed write never leaves a damaged file.

### Stream newline-delimited JSON

[`stream_out()`](https://ninohardt.github.io/glazelite/reference/stream_out.md)
writes one record per line from a data frame, a list of records, or a
function that returns one batch at a time and finally `NULL`:

``` r

ndjson <- tempfile(fileext = ".ndjson")
i <- 0L
stream_out(function() {
  i <<- i + 1L
  if (i > 3L) return(NULL)
  data.frame(batch = i, value = c(0.5, 1.5))
}, ndjson)

readLines(ndjson, n = 2)
#> [1] "{\"batch\":1,\"value\":0.5}" "{\"batch\":1,\"value\":1.5}"

stream_in(ndjson)
#>   batch value
#> 1     1   0.5
#> 2     1   1.5
#> 3     2   0.5
#> 4     2   1.5
#> 5     3   0.5
#> 6     3   1.5
```

Pass a `handler` to
[`stream_in()`](https://ninohardt.github.io/glazelite/reference/stream_in.md)
to process the file page by page without holding all of it in memory:

``` r

total <- 0
stream_in(ndjson, handler = function(page) total <<- total + sum(page$value),
          pagesize = 2)
total
#> [1] 6
```

## Performance

Median of seven runs in seconds on one Windows 10 machine (R 4.5.2, GCC
14.2, glazelite 0.1.2, yyjsonr 0.1.22, jsonlite 2.0.0), converting in
memory with
[`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
/
[`fromJSON()`](https://ninohardt.github.io/glazelite/reference/fromJSON.md)
and their counterparts. jsonlite was called with `digits = NA`. Treat
the numbers as indicative only.

| Task                            | glazelite | yyjsonr | jsonlite |
|---------------------------------|----------:|--------:|---------:|
| Write 1e6 doubles               |      0.09 |    0.07 |     0.86 |
| Write 1000 x 1000 double matrix |      0.09 |    0.08 |     0.93 |
| Write data frame, 2e5 rows x 6  |      0.17 |    0.11 |     0.81 |
| Write nested list, 2e4 records  |      0.02 |    0.02 |     5.69 |
| Read 1e6 doubles                |      0.08 |    0.03 |     0.94 |
| Read data frame, 2e5 rows x 6   |      0.25 |    0.11 |     1.53 |
| Read nested list, 2e4 records   |      0.04 |    0.01 |     0.30 |

[yyjsonr](https://CRAN.R-project.org/package=yyjsonr) is faster still,
particularly for reading.

## A substitute for jsonlite

glazelite keeps jsonlite’s function names, argument names and output.
For the common cases, replacing
[`library(jsonlite)`](https://jeroen.r-universe.dev/jsonlite) with
[`library(glazelite)`](https://ninohardt.github.io/glazelite/) is all
that is needed, and the JSON that is written stays the same. The
package’s tests compare its output with jsonlite’s for vectors, arrays
of every shape and all data frame layouts.

yyjsonr, the fastest JSON package for R, makes a different trade-off: it
has its own interface (`write_json_str()`, `read_json_str()`, options
objects), and what it writes differs from jsonlite in places. With
default options (jsonlite with `digits = NA`, yyjsonr 0.1.22):

| R object | jsonlite and glazelite | yyjsonr |
|----|----|----|
| `c(1.5, 2)` | `[1.5,2]` | `[1.5,2.0]` |
| `array(1:4)` | `[1,2,3,4]` | error |
| `array(1:12, c(2, 3, 2))` | `[[[1,7],[3,9],[5,11]],[[2,8],[4,10],[6,12]]]` | `[[[1,3,5],[2,4,6]],[[7,9,11],[8,10,12]]]` |
| `array(1:16, c(2, 2, 2, 2))` | four nested levels | error: more than three dimensions |
| `array(integer(), c(2, 0, 3))` | `[[],[]]` | `[[[],[]],[[],[]],[[],[]]]` |
| data frame with a 2 x 2 matrix column `m` | `[{"id":1,"m":[1,3]},{"id":2,"m":[2,4]}]` | `[{"id":1,"m":1},{"id":2,"m":2}]` |
| `data.frame(id = 1:2, v = c(NA, 2.5))` | `[{"id":1},{"id":2,"v":2.5}]` | `[{"id":1,"v":null},{"id":2,"v":2.5}]` |

glazelite does not cover all of jsonlite yet. The differences that
remain:

**Writing**

- Supported inputs are logical, integer, double, character, and factor
  vectors; arrays of any dimension; lists; and data frames of those
  types, including matrix, list, and data-frame columns. Other classes,
  such as dates and date-times, and complex and raw vectors raise an
  error instead of being converted; jsonlite and yyjsonr write dates as
  strings.
- The `dataframe`, `auto_unbox`, `na`, `factor`, `always_decimal`, and
  `pretty` options are implemented. `digits` must be `NA`: numbers
  always keep full precision, and rounding is not implemented.
- Missing values are written as `null` by default (`na = "string"`
  writes `"NA"`). In the row layout of a data frame, missing fields are
  omitted, as in jsonlite.
- Arrays keep their dimension order and dimensions of length one or
  zero. As with jsonlite, `auto_unbox = TRUE` keeps dimensioned
  length-one vectors and values wrapped in
  [`I()`](https://rdrr.io/r/base/AsIs.html) as JSON arrays.
- Factors are written as labels; `factor = "integer"` writes their level
  indices. `always_decimal = TRUE` keeps a decimal point or exponent for
  doubles, while integers and factor codes stay integers.

**Reading**

- Arrays of scalars of one type become atomic vectors, and arrays of
  records with scalar fields become data frames.
- There is no matrix simplification: `[[1,2],[3,4]]` becomes a list of
  two vectors, where jsonlite and yyjsonr return a matrix.
- Arrays of mixed types stay lists instead of being coerced to
  character, and records with nested fields stay lists of records.

## Large files

[`toJSON()`](https://ninohardt.github.io/glazelite/reference/toJSON.md)
returns one R string and therefore cannot exceed R’s string limit.
[`write_json()`](https://ninohardt.github.io/glazelite/reference/write_json.md)
and
[`stream_out()`](https://ninohardt.github.io/glazelite/reference/stream_out.md)
do not have that limit: values are split and flushed to the file through
an output buffer of about 64 KiB, including pretty-printed output. The R
object being written must still fit in memory; with
[`stream_out()`](https://ninohardt.github.io/glazelite/reference/stream_out.md)
a generated batch need not be kept once it is written.

On a Linux development machine, a batch generator wrote an NDJSON file
of 2,181,230,740 bytes in 7.86 seconds with a peak process memory of
about 64 MiB.

[`read_json()`](https://ninohardt.github.io/glazelite/reference/read_json.md)
avoids loading the file as an R string, but the parsed result still
occupies R memory.

## Credits

All JSON encoding and parsing is done by
[Glaze](https://github.com/stephenberry/glaze), a header-only C++
library by Stephen Berry, licensed under the MIT license. Glaze in turn
contains code from [fast_float](https://github.com/fastfloat/fast_float)
(Daniel Lemire, João Paulo Magalhaes and contributors),
[zmij](https://github.com/vitaut/zmij) (Victor Zverovich) and a
constexpr xxh64 implementation (Daniel Kirchner). Copyright holders and
licenses are listed in `inst/COPYRIGHTS`.

The bundled Glaze headers are pinned to commit
`c5ed7ddc249a2c3d15ede60f985adf447aa11ed3` under `inst/include/glaze`.
Only the headers needed for JSON are included, and pragmas that suppress
compiler diagnostics are removed to comply with CRAN policy;
`tools/vendor-glaze.R` reproduces both steps from a Glaze checkout.

## License

MIT. See `LICENSE` and, for the bundled code, `inst/COPYRIGHTS`.
