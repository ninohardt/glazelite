# Reformat or check JSON text

`prettify()` adds line breaks and indentation to JSON text and
`minify()` removes all optional whitespace. Neither changes the content:
numbers and strings are kept exactly as they are written. `validate()`
tests whether a string is valid JSON.

## Usage

``` r
prettify(txt, indent = 4)

minify(txt)

validate(txt)
```

## Arguments

- txt:

  A length-one JSON string.

- indent:

  Number of spaces per indentation level.

## Value

`prettify()` and `minify()` return the reformatted JSON as a length-one
character vector of class `c("glazelite_json", "json")`, and raise an
error when `txt` is not valid JSON. `validate()` returns `TRUE` or
`FALSE`; a `FALSE` result has an attribute `"err"` with a message.

## Examples

``` r
json <- toJSON(list(id = 1L, tags = c("a", "b")), auto_unbox = TRUE)
prettify(json)
#> {
#>     "id": 1,
#>     "tags": [
#>         "a",
#>         "b"
#>     ]
#> }
prettify(json, indent = 2)
#> {
#>   "id": 1,
#>   "tags": [
#>     "a",
#>     "b"
#>   ]
#> }
minify('{ "id" : 1 , "tags" : [ "a", "b" ] }')
#> {"id":1,"tags":["a","b"]}
validate(json)
#> [1] TRUE
validate('{"id": 1')
#> [1] FALSE
#> attr(,"err")
#> [1] "invalid JSON input"
```
