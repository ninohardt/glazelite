# Convert an R object to JSON text

This function returns one R string, so it retains R's string-size limit.
Use
[`jsonlite::write_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html)
for large output.

## Usage

``` r
toJSON(
  x,
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

A length-one character vector of class `c("glazelite_json", "json")`. It
prints as plain JSON text; use
[`as.character()`](https://rdrr.io/r/base/character.html) to drop the
class.

## See also

[`jsonlite::fromJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html)
for the reverse conversion,
[`jsonlite::write_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html)
to write to a file.

## Examples

``` r
toJSON(c(1.5, NA, 3))
#> [1.5,null,3]
toJSON(list(id = 1L, tags = c("a", "b")), auto_unbox = TRUE)
#> {"id":1,"tags":["a","b"]}
toJSON(matrix(1:6, nrow = 2))
#> [[1,3,5],[2,4,6]]

df <- data.frame(id = 1:2, group = factor(c("a", "b")))
toJSON(df)
#> [{"id":1,"group":"a"},{"id":2,"group":"b"}]
toJSON(df, dataframe = "columns", factor = "integer")
#> {"id":[1,2],"group":[1,2]}
toJSON(df, pretty = TRUE)
#> [
#>   {
#>     "id": 1,
#>     "group": "a"
#>   },
#>   {
#>     "id": 2,
#>     "group": "b"
#>   }
#> ]
```
