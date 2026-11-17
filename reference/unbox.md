# Mark a value as a JSON scalar

By default a vector of length one is written as a JSON array with one
element. `unbox()` marks a single value so that
[`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html)
writes it as a scalar, without unboxing every length-one vector as
`auto_unbox = TRUE` does. A data frame with one row is written as a
single object.

## Usage

``` r
unbox(x)
```

## Arguments

- x:

  An atomic vector of length one, or a data frame with one row.

## Value

`x` with the additional class `"scalar"`; `NULL` is returned as is.

## See also

The `auto_unbox` argument of
[`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html).

## Examples

``` r
toJSON(list(id = unbox(1L), tags = "a"))
#> {"id":1,"tags":["a"]}
toJSON(list(first = unbox(data.frame(id = 1L, name = "A"))))
#> {"first":{"id":1,"name":"A"}}
```
