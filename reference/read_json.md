# Parse a JSON file with Glaze

This avoids loading the file as an R string, but the parsed R object
still occupies memory. A JSON token longer than the native input window
is not supported; use
[`jsonlite::stream_in()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
for NDJSON records.

## Usage

``` r
read_json(path, simplifyVector = TRUE, simplifyDataFrame = TRUE)
```

## Arguments

- path:

  Input file path.

- simplifyVector:

  Simplify arrays of scalar values to atomic vectors.

- simplifyDataFrame:

  Simplify arrays of records to data frames. Has no effect unless
  `simplifyVector` is also `TRUE`.

## Value

An R object: a named list for a JSON object, a list, atomic vector or
data frame for a JSON array, a length-one vector for a JSON scalar, and
`NULL` for JSON `null`.

## See also

[`jsonlite::write_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html)
to write a JSON file,
[`jsonlite::stream_in()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
for newline-delimited JSON.

## Examples

``` r
path <- tempfile(fileext = ".json")
write_json(list(id = 1L, values = c(1.5, 2.5)), path, auto_unbox = TRUE)
read_json(path)
#> $id
#> [1] 1
#> 
#> $values
#> [1] 1.5 2.5
#> 
unlink(path)
```
