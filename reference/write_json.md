# Write JSON directly to a file

The document is written incrementally. Its total size may exceed 2 GB;
the input R object must still fit in R memory. For generated batches,
use
[`jsonlite::stream_out()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html).

## Usage

``` r
write_json(
  x,
  path,
  dataframe = c("rows", "columns", "values"),
  auto_unbox = FALSE,
  na = c("null", "string"),
  factor = c("string", "integer"),
  always_decimal = FALSE,
  pretty = FALSE,
  digits = NA
)
```

## Arguments

- x:

  An atomic vector, array, list, or data frame. Array dimensions are
  written in their existing order, including dimensions of length one or
  zero.

- path:

  Destination file path.

- dataframe:

  Data frame layout: rows, columns, or values.

- auto_unbox:

  Whether length-one atomic vectors become scalars.

- na:

  Encode missing and non-finite values as JSON null or as strings.

- factor:

  Encode factors as level labels (`"string"`, the default) or integer
  level indices (`"integer"`).

- always_decimal:

  Distinguish doubles from integers by retaining a decimal point or
  exponent in finite double output.

- pretty:

  Whether to indent JSON with two spaces per level. Pretty file output
  ends with a newline.

- digits:

  Must be `NA`. Numbers retain full round-trip precision; rounding to a
  specified number of digits is not implemented.

## Value

The path, invisibly.

## Details

The document is first written to a temporary file in the directory of
`path` and moved into place once it is complete, so an existing file at
`path` is left untouched when writing fails.

## See also

[`jsonlite::read_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html)
to read the file back,
[`jsonlite::stream_out()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
for newline-delimited JSON.

## Examples

``` r
path <- tempfile(fileext = ".json")
write_json(data.frame(id = 1:3, name = c("A", "B", "C")), path)
readLines(path, warn = FALSE)
#> [1] "[{\"id\":1,\"name\":\"A\"},{\"id\":2,\"name\":\"B\"},{\"id\":3,\"name\":\"C\"}]"
read_json(path)
#>   id name
#> 1  1    A
#> 2  2    B
#> 3  3    C
unlink(path)
```
