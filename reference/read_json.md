# Parse a JSON file with Glaze

This avoids loading the file as an R string, but the parsed R object
still occupies memory. A JSON token longer than the native input window
is not supported; use
[`jsonlite::stream_in()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
for NDJSON records.

## Usage

``` r
read_json(
  path,
  simplifyVector = FALSE,
  simplifyDataFrame = simplifyVector,
  simplifyMatrix = simplifyVector
)
```

## Arguments

- path:

  Input file path.

- simplifyVector:

  Simplify arrays of scalar values to atomic vectors.

- simplifyDataFrame:

  Simplify arrays of records to data frames. Has no effect unless
  `simplifyVector` is also `TRUE`.

- simplifyMatrix:

  Simplify regular arrays of arrays to matrices and higher-dimensional
  arrays. Has no effect unless `simplifyVector` is also `TRUE`.

## Value

An R object: a named list for a JSON object; a list, atomic vector,
matrix, array or data frame for a JSON array; a length-one vector for a
JSON scalar; and `NULL` for JSON `null`.

## Details

As in jsonlite, `read_json()` returns nested lists unless
`simplifyVector = TRUE`.

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
#> $values[[1]]
#> [1] 1.5
#> 
#> $values[[2]]
#> [1] 2.5
#> 
#> 
read_json(path, simplifyVector = TRUE)
#> $id
#> [1] 1
#> 
#> $values
#> [1] 1.5 2.5
#> 
unlink(path)
```
