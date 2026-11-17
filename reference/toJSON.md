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
  Date = c("ISO8601", "epoch"),
  POSIXt = c("string", "ISO8601", "epoch", "mongo"),
  factor = c("string", "integer"),
  null = c("list", "null"),
  na = c("null", "string"),
  auto_unbox = FALSE,
  digits = NA,
  pretty = FALSE,
  always_decimal = FALSE,
  UTC = FALSE,
  rownames = NULL
)
```

## Arguments

- x:

  An atomic vector, array, list, or data frame. Array dimensions are
  written in their existing order, including dimensions of length one or
  zero. Data frames may contain matrix, list, and data-frame columns.

- dataframe:

  Data frame layout: rows, columns, or values.

- Date:

  Encode `Date` objects as ISO 8601 strings such as `"2026-01-31"`
  (`"ISO8601"`, the default) or as the number of days since 1970-01-01
  (`"epoch"`).

- POSIXt:

  Encode date-times as strings in the format R prints them (`"string"`,
  the default), as ISO 8601 strings (`"ISO8601"`), as milliseconds since
  1970-01-01 UTC (`"epoch"`), or as MongoDB-style objects such as
  `{"$date": 1767323045000}` (`"mongo"`).

- factor:

  Encode factors as level labels (`"string"`, the default) or integer
  level indices (`"integer"`).

- null:

  Encode `NULL` as an empty object,
  [`{}`](https://rdrr.io/r/base/Paren.html) (`"list"`, the default), or
  as JSON `null` (`"null"`).

- na:

  Encode missing and non-finite values as JSON null or as strings.

- auto_unbox:

  Whether length-one atomic vectors become scalars. Use
  [`jsonlite::unbox()`](https://rdrr.io/pkg/jsonlite/man/unbox.html) to
  mark individual values instead.

- digits:

  `NA` (the default) writes every number as the shortest text that reads
  back to the same value. A number gives the maximum number of decimal
  digits, and a number wrapped in
  [`I()`](https://rdrr.io/r/base/AsIs.html) the number of significant
  digits; both round as jsonlite does.

- pretty:

  Whether to indent the output: `TRUE` for two spaces per level, or the
  number of spaces. Pretty file output ends with a newline.

- always_decimal:

  Distinguish doubles from integers by retaining a decimal point or
  exponent in finite double output.

- UTC:

  Whether date-times are converted to UTC. With `POSIXt = "ISO8601"` the
  strings then end in `Z`.

- rownames:

  Whether row names of data frames are written, as a `_row` field. The
  default, `NULL`, writes character row names but not automatic ones.

## Value

A length-one character vector of class `c("glazelite_json", "json")`. It
prints as plain JSON text; use
[`as.character()`](https://rdrr.io/r/base/character.html) to drop the
class.

## Details

The arguments and the structure of the output follow
[`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html).
Two defaults differ: numbers keep full precision unless `digits` is set,
and missing numbers are written as `null` unless `na = "string"`.

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
toJSON(pi, digits = 3)
#> [3.142]

df <- data.frame(id = 1:2, group = factor(c("a", "b")),
                 day = as.Date(c("2026-01-31", NA)))
toJSON(df)
#> [{"id":1,"group":"a","day":"2026-01-31"},{"id":2,"group":"b"}]
toJSON(df, dataframe = "columns", factor = "integer", Date = "epoch")
#> {"id":[1,2],"group":[1,2],"day":[20484,null]}
toJSON(df, pretty = TRUE)
#> [
#>   {
#>     "id": 1,
#>     "group": "a",
#>     "day": "2026-01-31"
#>   },
#>   {
#>     "id": 2,
#>     "group": "b"
#>   }
#> ]
```
