library(glazelite)

json <- function(...) as.character(toJSON(...))
stopifnot(identical(json(array(42), auto_unbox = TRUE), "[42]"))
stopifnot(identical(json(array(42, c(1, 1, 1)), auto_unbox = TRUE), "[[[42]]]"))
stopifnot(identical(json(I(42), auto_unbox = TRUE), "[42]"))
stopifnot(identical(json(array(1:8, c(2, 2, 2))),
                    "[[[1,5],[3,7]],[[2,6],[4,8]]]"))
stopifnot(identical(json(array(integer(), c(2, 0, 3))), "[[],[]]"))
stopifnot(identical(json(array(integer(), c(2, 3, 0))),
                    "[[[],[],[]],[[],[],[]]]"))
stopifnot(identical(json(array(integer(), c(0, 2, 3))), "[]"))

f <- factor(c("b", "c", NA), levels = c("a", "b", "c"))
stopifnot(identical(json(f), '["b","c",null]'))
stopifnot(identical(json(f, factor = "integer"), "[2,3,null]"))
stopifnot(identical(json(f, factor = "integer", na = "string"), '[2,3,"NA"]'))
stopifnot(identical(json(list(i = 1L, r = 2), auto_unbox = TRUE,
                         always_decimal = TRUE), '{"i":1,"r":2.0}'))
stopifnot(identical(json(matrix(c(1, 2), 1), always_decimal = TRUE),
                    "[[1.0,2.0]]"))
stopifnot(identical(json(c(NA_real_, NaN, Inf, -Inf), na = "string"),
                    '["NA","NaN","Inf","-Inf"]'))

# File and string paths must agree, including values across buffer flushes.
path <- tempfile(fileext = ".json")
x <- list(i = 1L, r = 2, factor = f, a = array(1:12000, c(2, 3, 2000)))
for (pretty in c(FALSE, TRUE)) {
  expected <- json(x, auto_unbox = TRUE, factor = "integer",
                   always_decimal = TRUE, pretty = pretty)
  if (pretty) expected <- paste0(expected, "\n")
  write_json(x, path, auto_unbox = TRUE, factor = "integer",
             always_decimal = TRUE, pretty = pretty, digits = NA)
  stopifnot(identical(readChar(path, file.info(path)$size, useBytes = TRUE), expected))
}

# Options apply to generated batches and each record stays on one line.
batch <- data.frame(code = factor(c("b", "c"), levels = c("a", "b", "c")),
                    value = c(1, 2))
n <- 0L
stream_out(function() {
  n <<- n + 1L
  if (n <= 2L) batch else NULL
}, path, factor = "integer", always_decimal = TRUE)
stopifnot(identical(readLines(path), rep(c('{"code":2,"value":1.0}',
                                         '{"code":3,"value":2.0}'), 2)))

# Rejected options must not replace a previously completed destination.
original <- readChar(path, file.info(path)$size, useBytes = TRUE)
for (options in list(list(always_decimal = NA), list(always_decimal = 1),
                     list(pretty = NA), list(pretty = c(TRUE, FALSE)),
                     list(factor = "invalid"), list(digits = -1), list(digits = c(1, 2)),
                     list(digits = numeric()), list(digits = "NA"))) {
  result <- try(do.call(write_json, c(list(x = x, path = path), options)), silent = TRUE)
  stopifnot(inherits(result, "try-error"))
  stopifnot(identical(readChar(path, file.info(path)$size, useBytes = TRUE), original))
}
unlink(path)

if (requireNamespace("jsonlite", quietly = TRUE)) {
  # Non-symmetric dimensions and distinct values expose dimension permutations.
  dims <- list(1L, 4L, c(2L, 3L), c(1L, 3L), c(3L, 1L), c(2L, 3L, 4L),
               c(2L, 1L, 3L, 4L), c(1L, 1L, 1L), c(0L, 2L), c(2L, 0L),
               c(2L, 0L, 3L), c(2L, 3L, 0L), c(0L, 2L, 3L))
  for (d in dims) {
    values <- seq_len(prod(d))
    for (v in list(values, as.double(values), values %% 2L == 0L,
                   as.character(values))) {
      a <- array(v, d)
      for (pretty in c(FALSE, TRUE)) {
        actual <- json(a, auto_unbox = TRUE, pretty = pretty)
        reference <- as.character(jsonlite::toJSON(a, auto_unbox = TRUE,
                                                    digits = NA, pretty = pretty))
        stopifnot(identical(actual, reference))
      }
    }
  }

  # Compare the scalar type distinction, factor codes, and all data-frame layouts.
  for (layout in c("rows", "columns", "values")) {
    for (pretty in c(FALSE, TRUE)) {
      actual <- json(batch, dataframe = layout, factor = "integer",
                      always_decimal = TRUE, pretty = pretty)
      reference <- as.character(jsonlite::toJSON(batch, dataframe = layout,
        factor = "integer", always_decimal = TRUE, digits = NA, pretty = pretty))
      stopifnot(identical(actual, reference))
    }
  }
  # Scientific notation and very large finite values must round-trip exactly.
  numbers <- c(pi, 1.2345678901234567, 1e-300, 1e100,
               .Machine$double.xmin, .Machine$double.xmax)
  stopifnot(identical(jsonlite::fromJSON(json(numbers, always_decimal = TRUE)), numbers))
}

# Data frames with matrix, list, and data-frame columns write one value per row.
nested <- data.frame(id = 1:2)
nested$m <- matrix(c(1L, 2L, 3L, 4L), 2)
nested$l <- list(1:2, "a")
nested$d <- data.frame(u = c(1.5, NA), v = c("p", "q"))
stopifnot(identical(json(nested),
  '[{"id":1,"m":[1,3],"l":[1,2],"d":{"u":1.5,"v":"p"}},{"id":2,"m":[2,4],"l":["a"],"d":{"v":"q"}}]'))
stopifnot(identical(json(nested[c("id", "m")], dataframe = "values"), "[[1,[1,3]],[2,[2,4]]]"))
stopifnot(identical(json(nested[c("id", "m")], dataframe = "columns"),
                    '{"id":[1,2],"m":[[1,3],[2,4]]}'))
first <- data.frame(id = 1:2)[, 0]
first$m <- matrix(1:6, 2)
first$id <- 1:2
stopifnot(identical(json(first), '[{"m":[1,3,5],"id":1},{"m":[2,4,6],"id":2}]'))
stream_out(first, path)
stopifnot(identical(readLines(path), c('{"m":[1,3,5],"id":1}', '{"m":[2,4,6],"id":2}')))
unlink(path)

# Malformed data frames are rejected instead of being read out of bounds.
ragged <- structure(list(a = 1:3, b = 1:2), class = "data.frame", row.names = 1:3)
cube <- structure(list(a = array(1:8, c(2, 2, 2))), class = "data.frame", row.names = 1:2)
unnamed <- structure(list(1:2), class = "data.frame", row.names = 1:2)
for (x in list(ragged, cube, unnamed)) {
  stopifnot(inherits(try(json(x), silent = TRUE), "try-error"))
}

if (requireNamespace("jsonlite", quietly = TRUE)) {
  for (layout in c("rows", "columns", "values")) {
    stopifnot(identical(json(nested[c("id", "m", "l")], dataframe = layout),
                        as.character(jsonlite::toJSON(nested[c("id", "m", "l")],
                                                      dataframe = layout, digits = NA))))
  }
}
