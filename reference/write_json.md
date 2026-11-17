# Write JSON directly to a file

The document is written incrementally. Its total size may exceed 2 GB;
the input R object must still fit in R memory. For generated batches,
use
[`jsonlite::stream_out()`](https://rdrr.io/pkg/jsonlite/man/stream_in.html).

## Usage

``` r
write_json(x, path, ...)
```

## Arguments

- x:

  An R object, as for
  [`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html).

- path:

  Destination file path.

- ...:

  Options passed on to
  [`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html),
  such as `auto_unbox`, `dataframe`, `digits` or `pretty`.

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
read_json(path, simplifyVector = TRUE)
#>   id name
#> 1  1    A
#> 2  2    B
#> 3  3    C
unlink(path)
```
