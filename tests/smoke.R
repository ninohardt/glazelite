library(glazelite)

assert_json <- function(x, expected, ...) {
  stopifnot(identical(as.character(toJSON(x, ...)), expected))
}

assert_json(c(1L, NA_integer_, 3L), "[1,null,3]")
assert_json(matrix(1:6, 2, 3), "[[1,3,5],[2,4,6]]")
assert_json(list(a = 1L, b = TRUE), '{"a":[1],"b":[true]}')
assert_json(factor(c("a", "b", NA)), '["a","b",null]')

df <- data.frame(id = 1:3, text = c('quote "', "snow \u2603", NA_character_))
expected <- '[{"id":1,"text":"quote \\\""},{"id":2,"text":"snow \u2603"},{"id":3}]'
assert_json(df, expected)
path <- tempfile(fileext = ".json")
write_json(df, path)
stopifnot(identical(readChar(path, file.info(path)$size), expected))
stopifnot(identical(read_json(path), df))

long <- paste0(strrep("a", 8192), '"\\\n\u2603')
write_json(list(text = long), path, auto_unbox = TRUE)
stopifnot(identical(read_json(path)$text, long))

count <- 0L
stream_out(function() {
  count <<- count + 1L
  if (count > 2L) NULL else df
}, path)
stopifnot(length(readLines(path)) == 6L)
stopifnot(nrow(stream_in(path, pagesize = 2L)) == 6L)
seen <- 0L
stream_in(path, handler = function(page) seen <<- seen + nrow(page), pagesize = 2L)
stopifnot(seen == 6L)

old <- readChar(path, file.info(path)$size)
stopifnot(inherits(try(write_json(Sys.Date(), path), silent = TRUE), "try-error"))
stopifnot(identical(readChar(path, file.info(path)$size), old))
unlink(path)

# Malformed, truncated, or trailing input must be rejected, as text and as file.
fails <- function(expr) inherits(try(expr, silent = TRUE), "try-error")
bad <- c('[1, 2,, 3]', '{"a": tru}', '{"a": 1', '[1, 2', '[1, 2] x', '', '   ',
         '"abc', '[1,2]]')
good <- list('[1, 2] ' = 1:2, ' {"a": 1}\n' = list(a = 1L), '42' = 42L,
             '"x"' = "x", 'true' = TRUE, '[]' = list(), '[1,2]\n\n  ' = 1:2)
for (txt in bad) {
  stopifnot(fails(fromJSON(txt)))
  writeBin(charToRaw(txt), path)
  stopifnot(fails(read_json(path)))
}
for (txt in names(good)) {
  stopifnot(identical(fromJSON(txt), good[[txt]]))
  writeBin(charToRaw(txt), path)
  stopifnot(identical(read_json(path), good[[txt]]))
}
stopifnot(is.null(fromJSON("null")))
writeBin(charToRaw(" null\n"), path)
stopifnot(is.null(read_json(path)))

# A connection that is not yet open is read once, page by page.
stream_out(data.frame(id = 1:7), path)
stopifnot(identical(stream_in(file(path), pagesize = 3L)$id, 1:7))
unlink(path)
