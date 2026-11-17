# Parse JSON text with Glaze

JSON objects become named lists, arrays become lists or, when
simplified, atomic vectors and data frames. JSON `null` becomes `NULL`,
or `NA` inside a simplified vector or data frame.

## Usage

``` r
fromJSON(txt, simplifyVector = TRUE, simplifyDataFrame = TRUE)
```

## Arguments

- txt:

  A length-one JSON string. If it names an existing file, that file is
  read with
  [`jsonlite::read_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html).

- simplifyVector:

  Simplify arrays of scalar values to atomic vectors.

- simplifyDataFrame:

  Simplify arrays of records to data frames. Has no effect unless
  `simplifyVector` is also `TRUE`.

## Value

An R object: a named list for a JSON object, a list, atomic vector or
data frame for a JSON array, a length-one vector for a JSON scalar, and
`NULL` for JSON `null`.

## Simplification

With `simplifyVector = TRUE`, an array whose elements are all strings,
all booleans or all numbers (apart from `null`) becomes a character,
logical, integer or double vector. Numbers are integers when every one
of them is a whole number that fits R's integer type, and doubles
otherwise. Arrays that mix these types, contain nested arrays or
objects, or contain only `null` stay lists.

With `simplifyDataFrame = TRUE` (which also requires
`simplifyVector = TRUE`), an array of objects becomes a data frame when
every field holds scalars of one type. Fields missing from a record are
`NA`. Arrays of objects with nested or mixed-type fields stay lists of
records.

## See also

[`jsonlite::toJSON()`](https://rdrr.io/pkg/jsonlite/man/fromJSON.html)
for the reverse conversion,
[`jsonlite::read_json()`](https://rdrr.io/pkg/jsonlite/man/read_json.html)
to parse a file.

## Examples

``` r
fromJSON('{"id": 1, "tags": ["a", "b"], "ok": true}')
#> $id
#> [1] 1
#> 
#> $tags
#> [1] "a" "b"
#> 
#> $ok
#> [1] TRUE
#> 
fromJSON('[1, 2.5, null]')
#> [1] 1.0 2.5  NA
fromJSON('[{"id": 1, "name": "A"}, {"id": 2, "name": "B"}]')
#>   id name
#> 1  1    A
#> 2  2    B
fromJSON('[{"id": 1}, {"id": 2}]', simplifyDataFrame = FALSE)
#> [[1]]
#> [[1]]$id
#> [1] 1
#> 
#> 
#> [[2]]
#> [[2]]$id
#> [1] 2
#> 
#> 
```
