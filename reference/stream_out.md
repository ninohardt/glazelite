# Stream batches as newline-delimited JSON

`x` may be a data frame, a list of records, or a zero-argument function
returning successive batches and finally `NULL`. Each data-frame row or
list element is written as one JSON record. This never creates the full
output as an R string.

## Usage

``` r
stream_out(x, con, pagesize = 500L, verbose = FALSE, ...)
```

## Arguments

- x:

  A data frame, list of records, or batch-producing function.

- con:

  A file path or a connection, for example `gzfile("x.json.gz")`.

- pagesize:

  Number of records written to a connection at a time.

- verbose:

  Accepted for compatibility with jsonlite and ignored.

- ...:

  Options passed on to
  [`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html),
  such as `digits`, `factor` or `na`. `auto_unbox` defaults to `TRUE`
  here, and every record is written on one line.

## Value

The path, invisibly, or `NULL` when writing to a connection.

## Details

When `con` is a file path, the records are written to a temporary file
in the same directory, which is moved into place once it is complete.
When `con` is a connection, the records are written to it `pagesize` at
a time; a connection that is not yet open is opened and closed again.

## See also

[`jsonlite::stream_in()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html)
to read newline-delimited JSON.

## Examples

``` r
path <- tempfile(fileext = ".ndjson")

# One record per data-frame row
stream_out(data.frame(id = 1:3, name = c("A", "B", "C")), path)
readLines(path)
#> [1] "{\"id\":1,\"name\":\"A\"}" "{\"id\":2,\"name\":\"B\"}"
#> [3] "{\"id\":3,\"name\":\"C\"}"

# Batches produced on demand by a function that finally returns NULL
i <- 0L
stream_out(function() {
  i <<- i + 1L
  if (i > 3L) return(NULL)
  data.frame(batch = i, value = c(0.5, 1.5))
}, path)
stream_in(path)
#>   batch value
#> 1     1   0.5
#> 2     1   1.5
#> 3     2   0.5
#> 4     2   1.5
#> 5     3   0.5
#> 6     3   1.5

# A connection, here compressed
zipped <- tempfile(fileext = ".ndjson.gz")
stream_out(data.frame(id = 1:3), gzfile(zipped))
stream_in(gzfile(zipped))
#>   id
#> 1  1
#> 2  2
#> 3  3
unlink(c(path, zipped))
```
