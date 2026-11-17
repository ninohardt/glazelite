library(glazelite)

json <- function(...) as.character(toJSON(...))
is <- function(actual, expected) {
  if (!identical(actual, expected)) stop("expected ", expected, "\n  but got ", actual)
}
fails <- function(expr) inherits(try(expr, silent = TRUE), "try-error")

# Dates
days <- as.Date(c("2026-01-02", NA, "1969-12-31", "0001-01-01", "9999-12-31", "2024-02-29"))
is(json(days), '["2026-01-02",null,"1969-12-31","0001-01-01","9999-12-31","2024-02-29"]')
is(json(days, na = "string"), '["2026-01-02","NA","1969-12-31","0001-01-01","9999-12-31","2024-02-29"]')
is(json(days[-2], Date = "epoch"), "[20455,-1,-719162,2932896,19782]")
is(json(days[1], auto_unbox = TRUE), '"2026-01-02"')
is(json(structure(20455L, class = "Date")), '["2026-01-02"]')
is(json(structure(c(20455.7, -0.5), class = "Date")), '["2026-01-02","1969-12-31"]')

# Date-times
times <- as.POSIXct(c("2026-01-02 03:04:05", NA, "2026-06-30 23:59:59"), tz = "UTC")
is(json(times), '["2026-01-02 03:04:05",null,"2026-06-30 23:59:59"]')
is(json(times, POSIXt = "ISO8601"), '["2026-01-02T03:04:05",null,"2026-06-30T23:59:59"]')
is(json(times, POSIXt = "ISO8601", UTC = TRUE),
   '["2026-01-02T03:04:05Z",null,"2026-06-30T23:59:59Z"]')
is(json(times, POSIXt = "epoch"), "[1767323045000,null,1782863999000]")
is(json(times, POSIXt = "mongo"),
   '[{"$date":1767323045000},null,{"$date":1782863999000}]')
is(json(as.POSIXlt(times)), '["2026-01-02 03:04:05",null,"2026-06-30 23:59:59"]')
is(json(as.POSIXct(c("2026-01-02", "2026-01-03"), tz = "UTC")), '["2026-01-02","2026-01-03"]')

dated <- data.frame(id = 1:2, day = days[1:2], at = times[1:2])
is(json(dated), '[{"id":1,"day":"2026-01-02","at":"2026-01-02 03:04:05"},{"id":2}]')
is(json(dated, dataframe = "columns"),
   '{"id":[1,2],"day":["2026-01-02",null],"at":["2026-01-02 03:04:05",null]}')
is(json(list(when = days[1], at = times[1]), auto_unbox = TRUE),
   '{"when":"2026-01-02","at":"2026-01-02 03:04:05"}')
stopifnot(fails(json(structure(1, class = "unknown_class"))), fails(json(1i)), fails(json(as.raw(1))))

# unbox()
is(json(unbox(1)), "1")
is(json(list(a = unbox("x"), b = 1:2, c = unbox(TRUE), d = unbox(factor("f")))),
   '{"a":"x","b":[1,2],"c":true,"d":"f"}')
is(json(list(r = unbox(data.frame(a = 1, b = "x")))), '{"r":{"a":1,"b":"x"}}')
is(json(unbox(NA)), "null")
is(json(unbox(days[1])), '"2026-01-02"')
stopifnot(is.null(unbox(NULL)), fails(unbox(1:2)), fails(unbox(list(1))),
          fails(unbox(data.frame(a = 1:2))), fails(unbox(matrix(1:4, 2))))

# NULL and names
is(json(NULL), "{}")
is(json(NULL, null = "null"), "null")
is(json(list(a = NULL)), '{"a":{}}')
is(json(list(a = NULL), null = "null"), '{"a":null}')
is(json(list(NULL, 1)), "[{},[1]]")
is(json(list(a = 1, 2)), '{"a":[1],"2":[2]}')
is(json(structure(list(1, 2), names = c("a", NA))), '{"a":[1],"2":[2]}')
is(json(structure(list(1, 2), names = c("", ""))), '{"1":[1],"2":[2]}')
is(json(structure(list(), names = character())), "{}")
is(json(list()), "[]")
stopifnot(identical(fromJSON(json(fromJSON("{}"))), fromJSON("{}")))

# Row names
named <- data.frame(x = 1:2, y = c("p", NA), row.names = c("a", "b"))
is(json(named), '[{"x":1,"y":"p","_row":"a"},{"x":2,"_row":"b"}]')
is(json(named, dataframe = "columns"), '{"x":[1,2],"y":["p",null],"_row":["a","b"]}')
is(json(named, dataframe = "values"), '[[1,"p","a"],[2,null,"b"]]')
is(json(named, rownames = FALSE), '[{"x":1,"y":"p"},{"x":2}]')
is(json(data.frame(x = 1:2), rownames = TRUE), '[{"x":1,"_row":1},{"x":2,"_row":2}]')
is(json(data.frame(x = 1:3)[c(3, 1), , drop = FALSE]), '[{"x":3},{"x":1}]')

# digits
values <- c(pi, 2 / 3, 123456.789, 1e10, 1e-6, 100, 0.125, 2.675, 0.05, -1.2345678)
is(json(values, digits = 4), "[3.1416,0.6667,123456.789,10000000000,1e-06,100,0.125,2.675,0.05,-1.2346]")
is(json(values, digits = 1), "[3.1,0.7,123456.8,10000000000,1e-06,100,0.1,2.7,0,-1.2]")
is(json(values, digits = 0), "[3,1,123457,1e+10,1e-06,100,0,3,0,-1]")
is(json(values, digits = I(3)), "[3.14,0.667,1.23e+05,1e+10,1e-06,100,0.125,2.67,0.05,-1.23]")
is(json(c(1, 2.5, 3.004), digits = 2, always_decimal = TRUE), "[1.0,2.5,3.0]")
is(json(c(7L, NA), digits = 2), "[7,null]")
is(json(pi), "[3.141592653589793]")
stopifnot(fails(json(1, digits = -1)), fails(json(1, digits = "2")), fails(json(1, digits = c(1, 2))))

# pretty with a given indentation
is(json(list(a = 1:2, b = list(c = "x")), pretty = 4),
   '{\n    "a": [1, 2],\n    "b": {\n        "c": ["x"]\n    }\n}')
is(json(list(a = 1:2), pretty = 0), '{\n"a": [1, 2]\n}')
is(json(list(a = 1:2), pretty = TRUE), '{\n  "a": [1, 2]\n}')

# prettify(), minify(), validate()
text <- '{ "a" : [1, 2 , {"b" : null, "s": "x  y\\n"} ] ,\n "c" : 1.50, "e": [] }'
is(as.character(minify(text)), '{"a":[1,2,{"b":null,"s":"x  y\\n"}],"c":1.50,"e":[]}')
is(as.character(prettify("[1,{\"a\":2}]", indent = 2)), "[\n  1,\n  {\n    \"a\": 2\n  }\n]")
is(as.character(minify(prettify(text))), as.character(minify(text)))
stopifnot(inherits(minify(text), "json"), inherits(prettify(text), "json"))
stopifnot(isTRUE(validate(text)), !validate("[1,2"), is.character(attr(validate("[1,2"), "err")))
stopifnot(fails(prettify("[1,2")), fails(minify('{"a":}')), fails(prettify("[1]", indent = -1)))
stopifnot(identical(fromJSON(prettify(text)), fromJSON(text)))

# Matrices and arrays read back
stopifnot(identical(fromJSON("[[1,2],[3,4]]"), matrix(c(1L, 3L, 2L, 4L), 2)))
stopifnot(identical(fromJSON("[[1,null],[3.5,4]]"), matrix(c(1, 3.5, NA, 4), 2)))
stopifnot(identical(fromJSON('[["a","b"],["c","d"]]'), matrix(c("a", "c", "b", "d"), 2)))
stopifnot(identical(fromJSON("[[1,2],[3]]"), list(1:2, 3L)))
stopifnot(identical(fromJSON("[[1,2],[3,4]]", simplifyMatrix = FALSE), list(1:2, 3:4)))
stopifnot(identical(fromJSON("[[1,2],[3,4]]", simplifyVector = FALSE),
                    list(list(1L, 2L), list(3L, 4L))))
stopifnot(identical(fromJSON("[[1,2],[true,false]]"), list(1:2, c(TRUE, FALSE))))
stopifnot(identical(fromJSON("[[],[]]"), list(list(), list())))
stopifnot(identical(fromJSON('{"m":[[1,2],[3,4]]}'), list(m = matrix(c(1L, 3L, 2L, 4L), 2))))
for (d in list(c(2, 3), c(3, 2, 4), c(2, 1, 3, 4), c(1, 1, 1), c(4, 1))) {
  n <- prod(d)
  for (v in list(seq_len(n), seq_len(n) + 0.5, as.character(seq_len(n)), seq_len(n) %% 2 == 0)) {
    a <- array(v, d)
    stopifnot(identical(fromJSON(toJSON(a)), a))
  }
}

# read_json() returns lists unless asked to simplify, as jsonlite does
path <- tempfile(fileext = ".json")
write_json(data.frame(a = 1:2), path)
stopifnot(identical(read_json(path), list(list(a = 1L), list(a = 2L))))
stopifnot(identical(read_json(path, simplifyVector = TRUE), data.frame(a = 1:2)))
write_json(matrix(1:4, 2), path)
stopifnot(identical(read_json(path, simplifyVector = TRUE), matrix(1:4, 2)))

# write_json() passes its options on
write_json(list(d = days[1], x = pi), path, auto_unbox = TRUE, digits = 2, pretty = 4)
is(readChar(path, file.info(path)$size), '{\n    "d": "2026-01-02",\n    "x": 3.14\n}\n')
stopifnot(fails(write_json(1, path, no_such_option = TRUE)))

# stream_out() to a path and to connections gives the same lines
big <- data.frame(id = 1:1203, label = sprintf("r%d", 1:1203),
                  day = as.Date("2026-01-01") + 0:1202)
plain <- tempfile(); via_con <- tempfile(); zipped <- tempfile(fileext = ".gz")
stream_out(big, plain)
stream_out(big, file(via_con), pagesize = 100)
stream_out(big, con = gzfile(zipped), verbose = FALSE)
lines <- readLines(plain)
stopifnot(length(lines) == 1203L, identical(lines[2], '{"id":2,"label":"r2","day":"2026-01-02"}'),
          identical(readLines(via_con), lines), identical(readLines(gzfile(zipped)), lines))
stopifnot(identical(stream_in(con = file(via_con), verbose = FALSE)$id, big$id))
con <- file(via_con, "wb")
stream_out(big[1:2, ], con)
stream_out(function() NULL, con)
stream_out(big[3, ], con)
close(con)
stopifnot(identical(readLines(via_con), lines[1:3]))
stopifnot(fails(stream_out(1:3, file(via_con))), fails(stream_out(big, plain, pagesize = 0)))
unlink(c(path, plain, via_con, zipped))

if (requireNamespace("jsonlite", quietly = TRUE)) {
  same <- function(...) {
    theirs <- as.character(jsonlite::toJSON(...))
    ours <- json(...)
    if (!identical(ours, theirs)) stop("jsonlite wrote ", theirs, "\n  glazelite wrote ", ours)
  }
  set.seed(42)
  same(as.Date(round(runif(2000, -200000, 200000)), origin = "1970-01-01"))
  zoned <- as.POSIXct(c("2026-01-02 03:04:05", "2026-07-02 12:00:00"), tz = "America/New_York")
  for (mode in c("string", "ISO8601", "epoch", "mongo")) {
    for (utc in c(FALSE, TRUE)) {
      same(zoned, POSIXt = mode, UTC = utc)
      same(times[-2], POSIXt = mode, UTC = utc)
    }
  }
  for (layout in c("rows", "columns", "values")) {
    same(dated, dataframe = layout)
    same(named, dataframe = layout)
    same(named, dataframe = layout, rownames = FALSE)
    same(head(mtcars, 5), dataframe = layout)
    same(iris[c(1, 51, 101), ], dataframe = layout)
  }
  same(list(a = jsonlite::unbox("x"), b = 1:2, r = jsonlite::unbox(data.frame(a = 1))))
  for (x in list(NULL, list(a = NULL), list(NULL, 1), list(a = 1, 2), list(),
                 structure(list(), names = character()))) same(x)
  for (indent in list(TRUE, 0, 1, 4, 8)) {
    same(list(a = 1:2, b = list(c = "x", d = list()), e = data.frame(x = 1:2)), pretty = indent)
  }

  # Rounded numbers are written exactly as jsonlite writes them.
  numbers <- c(values, rnorm(2000), runif(2000) * 10^sample(-8:12, 2000, TRUE),
               round(rnorm(300), 2), sample(1e6, 300) / 100, 0, 0.5, 2.5, 99.99999,
               2147483646.5, 2^31, 1e15, 1e16, 1e300, 5e-324, 1e-5, 1.005)
  for (digits in list(0, 1, 2, 3, 4, 6, 9, 10, 12, 15, I(1), I(4), I(8), I(15))) {
    same(numbers, digits = digits)
    same(numbers, digits = digits, always_decimal = TRUE)
  }

  # Matrix simplification agrees with jsonlite for arrays of one type.
  for (txt in c("[[1,2],[3,4]]", "[[1,2],[3.5,4]]", "[[1,2],[3]]", "[[1],[2]]",
                "[[1,null],[3,4]]", '[["a","b"],["c","d"]]', "[[true,false],[true,true]]",
                "[[],[]]", "[[[1,2],[3,4]],[[5,6],[7,8]]]", "[[[1,2],[3,4]],[[5,6],[7]]]",
                "[[1,2],null]", "[[[1],[2]],[[3],[4]]]", "[[1,2,3]]", "[[[[1,2]]]]")) {
    for (matrix in c(TRUE, FALSE)) {
      stopifnot(identical(fromJSON(txt, simplifyMatrix = matrix),
                          jsonlite::fromJSON(txt, simplifyMatrix = matrix)))
    }
  }
  stopifnot(identical(as.character(minify(text)), as.character(jsonlite::minify(text))))

  theirs <- tempfile(); ours <- tempfile()
  jsonlite::stream_out(big, file(theirs), verbose = FALSE)
  stream_out(big, file(ours), verbose = FALSE)
  stopifnot(identical(readLines(ours), readLines(theirs)))
  unlink(c(theirs, ours))
}
