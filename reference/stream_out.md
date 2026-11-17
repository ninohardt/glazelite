# Stream batches as newline-delimited JSON

`x` may be a data frame, a list of records, or a zero-argument function
returning successive batches and finally `NULL`. Each data-frame row or
list element is written as one JSON record. This never creates the full
output as an R string.

## Usage

``` r
stream_out(
  x,
  path,
  auto_unbox = TRUE,
  na = c("null", "string"),
  factor = c("string", "integer"),
  always_decimal = FALSE,
  digits = NA
)
```

## Arguments

- x:

  A data frame, list of records, or batch-producing function.

- path:

  Destination file path.

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

- digits:

  Must be `NA`. Numbers retain full round-trip precision; rounding to a
  specified number of digits is not implemented.

## Value

The path, invisibly.

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
unlink(path)
```
