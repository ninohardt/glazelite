library(glazelite)

same <- function(txt, expected, ...) {
  actual <- fromJSON(txt, ...)
  if (!identical(actual, expected)) {
    stop("unexpected result for ", txt, ":\n",
         paste(utils::capture.output(str(actual)), collapse = "\n"))
  }
}
fails <- function(expr) inherits(try(expr, silent = TRUE), "try-error")

# Scalars
same("1", 1L)
same("1.5", 1.5)
same("true", TRUE)
same('"a"', "a")
same("null", NULL)
same("3000000000", 3e9)
same("2147483647", .Machine$integer.max)
same("-2147483648", -2147483648)  # R's integer NA bit pattern stays a double

# Arrays of scalars become atomic vectors, with NA for null
same("[1, 2, 3]", 1:3)
same("[1, 2.5]", c(1, 2.5))
same("[1, null, 3]", c(1L, NA, 3L))
same("[null, 1.5]", c(NA, 1.5))
same("[1, 3000000000]", c(1, 3e9))
same("[true, null, false]", c(TRUE, NA, FALSE))
same('["a", null, "b"]', c("a", NA, "b"))
same('["\\u2603", "a\\nb", "q\\"q"]', c("☃", "a\nb", "q\"q"))

# Arrays that are not uniform scalars stay lists
same("[]", list())
same("[null, null]", list(NULL, NULL))
same('[1, "a"]', list(1L, "a"))
same("[true, 1]", list(TRUE, 1L))
same("[[1, 2], [3]]", list(1:2, 3L))
same("[[1], [2]]", list(1L, 2L))
same("[1, [2]]", list(1L, 2L))
same("[1, 2]", list(1L, 2L), simplifyVector = FALSE)

# Objects keep their key order; the last duplicate key wins
same('{"b": 1, "a": [1.5, 2], "c": {"d": null}}',
     list(b = 1L, a = c(1.5, 2), c = list(d = NULL)))
same("{}", structure(list(), names = character()))
same('{"a": 1, "a": 2}', list(a = 2L))
same('{"my key": 1, "\\u2603": 2}', list("my key" = 1L, "☃" = 2L))

# Arrays of records become data frames
same('[{"a": 1, "b": "x"}, {"a": 2, "b": "y"}]',
     data.frame(a = 1:2, b = c("x", "y")))
same('[{"a": 1, "b": 2}, {"b": 3, "a": 4.5}]',
     data.frame(a = c(1, 4.5), b = 2:3))
same('[{"a": 1}, {"b": true}, {"c": "z", "a": null}]',
     data.frame(a = c(1L, NA, NA), b = c(NA, TRUE, NA), c = c(NA, NA, "z")))
same('[{"a": null}, {"a": null}]', data.frame(a = c(NA, NA)))
same('[{"my key": 1}]', data.frame("my key" = 1L, check.names = FALSE))
empty <- fromJSON("[{}, {}]")
stopifnot(is.data.frame(empty), identical(dim(empty), c(2L, 0L)))

# Records with nested or mixed-type fields stay lists of records
same('[{"a": [1, 2]}, {"a": [3]}]', list(list(a = 1:2), list(a = 3L)))
same('[{"a": 1}, {"a": "x"}]', list(list(a = 1L), list(a = "x")))
same('[{"a": 1}, 2]', list(list(a = 1L), 2L))
same('[{"a": {"b": 1}}]', list(list(a = list(b = 1L))))

# Simplification switches
records <- '[{"a": 1, "b": "x"}, {"a": 2, "b": "y"}]'
same(records, list(list(a = 1L, b = "x"), list(a = 2L, b = "y")),
     simplifyDataFrame = FALSE)
same(records, list(list(a = 1L, b = "x"), list(a = 2L, b = "y")),
     simplifyVector = FALSE)
stopifnot(fails(fromJSON("[1]", simplifyVector = NA)),
          fails(fromJSON("[1]", simplifyDataFrame = "yes")))

# Simplification applies at every level
same('{"rows": [{"a": 1}, {"a": 2}], "n": 2}',
     list(rows = data.frame(a = 1:2), n = 2L))
same('[[{"a": 1}], [{"a": 2}, {"a": 3}]]',
     list(data.frame(a = 1L), data.frame(a = 2:3)))

# Strings R cannot represent are rejected with an error
stopifnot(fails(fromJSON('"a\\u0000b"')), fails(fromJSON('{"a\\u0000b": 1}')))

# Files give the same results as text
path <- tempfile(fileext = ".json")
for (txt in c("[1, null, 3]", records, '{"rows": [{"a": 1}, {"a": 2}], "n": 2}',
              '[{"a": [1, 2]}, {"a": [3]}]', "[]", "{}")) {
  writeLines(txt, path)
  for (sv in c(TRUE, FALSE)) for (sdf in c(TRUE, FALSE)) {
    stopifnot(identical(read_json(path, sv, sdf), fromJSON(txt, sv, sdf)))
  }
}

# A wide table round-trips with its column types
n <- 2000L
df <- data.frame(id = seq_len(n), x = seq_len(n) / 7, flag = seq_len(n) %% 3L == 0L,
                 label = sprintf("item-%d ☃", seq_len(n)))
df$x[5] <- NA
df$label[7] <- NA
write_json(df, path)
stopifnot(identical(read_json(path), df), identical(fromJSON(toJSON(df)), df))

# NDJSON: records are simplified together, or page by page with a handler
writeLines(c('{"a": 1, "b": "x"}', "", "   ", '{"a": 2}', '{"b": "z", "a": 3.5}'), path)
stopifnot(identical(stream_in(path),
                    data.frame(a = c(1, 2, 3.5), b = c("x", NA, "z"))))
stopifnot(identical(stream_in(path, simplifyDataFrame = FALSE),
                    list(list(a = 1L, b = "x"), list(a = 2L), list(b = "z", a = 3.5))))
pages <- list()
stream_in(path, handler = function(page) pages[[length(pages) + 1L]] <<- page,
          pagesize = 2L)
stopifnot(identical(pages, list(data.frame(a = 1L, b = "x"), data.frame(a = 2L),
                                data.frame(b = "z", a = 3.5))))
writeLines(c("1", "2", "3"), path)
stopifnot(identical(stream_in(path), 1:3))
writeLines(character(), path)
stopifnot(identical(stream_in(path), data.frame()))
writeLines(c('{"a": 1}', '{"a": '), path)
message <- tryCatch(stream_in(path), error = conditionMessage)
stopifnot(grepl("record 2", message, fixed = TRUE))
unlink(path)

if (requireNamespace("jsonlite", quietly = TRUE)) {
  # Shapes on which glazelite and jsonlite simplify alike.
  for (txt in c("[1, 2, 3]", "[1, 2.5, null]", '["a", null]', "[true, false]",
                records, '[{"a": 1}, {"b": true}]', '{"rows": [{"a": 1}], "n": 2}',
                '{"b": 1, "a": [1.5, 2], "c": {"d": "e"}}')) {
    stopifnot(isTRUE(all.equal(fromJSON(txt), jsonlite::fromJSON(txt))))
  }
  # jsonlite writes doubles with 15 significant digits, hence all.equal().
  stopifnot(isTRUE(all.equal(fromJSON(as.character(jsonlite::toJSON(df, digits = NA))), df)))
}
