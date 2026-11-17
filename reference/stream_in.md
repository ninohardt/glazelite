# Read newline-delimited JSON in pages

Each non-empty line is parsed as one JSON record. Supply a `handler` to
process the input page by page without collecting all of it in memory.
Records are simplified as the elements of one JSON array would be by
[`jsonlite::fromJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html);
with a `handler`, each page is simplified on its own.

## Usage

``` r
stream_in(
  con,
  handler = NULL,
  pagesize = 500L,
  verbose = FALSE,
  simplifyVector = TRUE,
  simplifyDataFrame = simplifyVector,
  simplifyMatrix = simplifyVector
)
```

## Arguments

- con:

  An input path or an R connection. A connection that is not yet open is
  opened for reading and closed again on exit.

- handler:

  Optional function called for each page. When absent, pages are
  collected and returned.

- pagesize:

  Number of lines read per page when a `handler` is given.

- verbose:

  Accepted for compatibility with jsonlite and ignored.

- simplifyVector:

  Simplify arrays of scalar values to atomic vectors.

- simplifyDataFrame:

  Simplify arrays of records to data frames. Has no effect unless
  `simplifyVector` is also `TRUE`.

- simplifyMatrix:

  Simplify regular arrays of arrays to matrices and higher-dimensional
  arrays. Has no effect unless `simplifyVector` is also `TRUE`.

## Value

Without a `handler`, the collected records: a data frame when all
records are objects with scalar fields and `simplifyDataFrame = TRUE`,
otherwise a list or vector with one element per record. With a
`handler`, `NULL`, invisibly.

## See also

[`jsonlite::stream_out()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
to write newline-delimited JSON.

## Examples

``` r
path <- tempfile(fileext = ".ndjson")
stream_out(data.frame(id = 1:5, value = c(0.5, 1.5, 2.5, 3.5, 4.5)), path)

stream_in(path)
#>   id value
#> 1  1   0.5
#> 2  2   1.5
#> 3  3   2.5
#> 4  4   3.5
#> 5  5   4.5

# Process two records at a time instead of collecting them
total <- 0
stream_in(path, handler = function(page) total <<- total + sum(page$value),
          pagesize = 2)
total
#> [1] 12.5
unlink(path)
```
