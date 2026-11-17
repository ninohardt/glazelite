#' Convert an R object to JSON text
#'
#' This function returns one R string, so it retains R's string-size limit.
#' Use [write_json()] for large output.
#'
#' The arguments and the structure of the output follow
#' `jsonlite::toJSON()`. Two defaults differ: numbers keep full precision
#' unless `digits` is set, and missing numbers are written as `null` unless
#' `na = "string"`.
#' @param x An atomic vector, array, list, or data frame. Array dimensions are
#'   written in their existing order, including dimensions of length one or
#'   zero. Data frames may contain matrix, list, and data-frame columns.
#' @param dataframe Data frame layout: rows, columns, or values.
#' @param Date Encode `Date` objects as ISO 8601 strings such as
#'   `"2026-01-31"` (`"ISO8601"`, the default) or as the number of days since
#'   1970-01-01 (`"epoch"`).
#' @param POSIXt Encode date-times as strings in the format R prints them
#'   (`"string"`, the default), as ISO 8601 strings (`"ISO8601"`), as
#'   milliseconds since 1970-01-01 UTC (`"epoch"`), or as MongoDB-style
#'   objects such as `{"$date": 1767323045000}` (`"mongo"`).
#' @param factor Encode factors as level labels (`"string"`, the default) or
#'   integer level indices (`"integer"`).
#' @param null Encode `NULL` as an empty object, `{}` (`"list"`, the
#'   default), or as JSON `null` (`"null"`).
#' @param na Encode missing and non-finite values as JSON null or as strings.
#' @param auto_unbox Whether length-one atomic vectors become scalars. Use
#'   [unbox()] to mark individual values instead.
#' @param digits `NA` (the default) writes every number as the shortest text
#'   that reads back to the same value. A number gives the maximum number of
#'   decimal digits, and a number wrapped in [I()] the number of significant
#'   digits; both round as jsonlite does.
#' @param pretty Whether to indent the output: `TRUE` for two spaces per
#'   level, or the number of spaces. Pretty file output ends with a newline.
#' @param always_decimal Distinguish doubles from integers by retaining a decimal
#'   point or exponent in finite double output.
#' @param UTC Whether date-times are converted to UTC. With
#'   `POSIXt = "ISO8601"` the strings then end in `Z`.
#' @param rownames Whether row names of data frames are written, as a `_row`
#'   field. The default, `NULL`, writes character row names but not automatic
#'   ones.
#' @return A length-one character vector of class
#'   `c("glazelite_json", "json")`. It prints as plain JSON text; use
#'   [as.character()] to drop the class.
#' @seealso [fromJSON()] for the reverse conversion, [write_json()] to write
#'   to a file.
#' @examples
#' toJSON(c(1.5, NA, 3))
#' toJSON(list(id = 1L, tags = c("a", "b")), auto_unbox = TRUE)
#' toJSON(matrix(1:6, nrow = 2))
#' toJSON(pi, digits = 3)
#'
#' df <- data.frame(id = 1:2, group = factor(c("a", "b")),
#'                  day = as.Date(c("2026-01-31", NA)))
#' toJSON(df)
#' toJSON(df, dataframe = "columns", factor = "integer", Date = "epoch")
#' toJSON(df, pretty = TRUE)
#' @export
toJSON <- function(x, dataframe = c("rows", "columns", "values"),
                   Date = c("ISO8601", "epoch"),
                   POSIXt = c("string", "ISO8601", "epoch", "mongo"),
                   factor = c("string", "integer"), null = c("list", "null"),
                   na = c("null", "string"), auto_unbox = FALSE, digits = NA,
                   pretty = FALSE, always_decimal = FALSE, UTC = FALSE,
                   rownames = NULL) {
  opts <- .writer_options(dataframe, Date, POSIXt, factor, null, na,
                          auto_unbox, digits, pretty, always_decimal, UTC,
                          rownames)
  .as_json(.Call(glazelite_to_json, x, opts))
}

.as_json <- function(x) structure(x, class = c("glazelite_json", "json"))

#' @export
print.glazelite_json <- function(x, ...) {
  cat(x, "\n", sep = "")
  invisible(x)
}

#' Write JSON directly to a file
#'
#' The document is written incrementally. Its total size may exceed 2 GB; the
#' input R object must still fit in R memory. For generated batches, use
#' [stream_out()].
#'
#' The document is first written to a temporary file in the directory of
#' `path` and moved into place once it is complete, so an existing file at
#' `path` is left untouched when writing fails.
#' @param x An R object, as for [toJSON()].
#' @param path Destination file path.
#' @param ... Options passed on to [toJSON()], such as `auto_unbox`,
#'   `dataframe`, `digits` or `pretty`.
#' @return The path, invisibly.
#' @seealso [read_json()] to read the file back, [stream_out()] for
#'   newline-delimited JSON.
#' @examples
#' path <- tempfile(fileext = ".json")
#' write_json(data.frame(id = 1:3, name = c("A", "B", "C")), path)
#' readLines(path, warn = FALSE)
#' read_json(path, simplifyVector = TRUE)
#' unlink(path)
#' @export
write_json <- function(x, path, ...) {
  path <- .check_path(path)
  opts <- .writer_options(...)
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  .Call(glazelite_write_json, x, tmp, opts)
  if (!file.rename(tmp, path)) stop("could not move completed JSON file into place")
  invisible(path)
}

#' Stream batches as newline-delimited JSON
#'
#' `x` may be a data frame, a list of records, or a zero-argument function
#' returning successive batches and finally `NULL`. Each data-frame row or
#' list element is written as one JSON record. This never creates the full
#' output as an R string.
#'
#' When `con` is a file path, the records are written to a temporary file in
#' the same directory, which is moved into place once it is complete. When
#' `con` is a connection, the records are written to it `pagesize` at a time;
#' a connection that is not yet open is opened and closed again.
#' @param x A data frame, list of records, or batch-producing function.
#' @param con A file path or a connection, for example `gzfile("x.json.gz")`.
#' @param pagesize Number of records written to a connection at a time.
#' @param verbose Accepted for compatibility with jsonlite and ignored.
#' @param ... Options passed on to [toJSON()], such as `digits`, `factor` or
#'   `na`. `auto_unbox` defaults to `TRUE` here, and every record is written
#'   on one line.
#' @return The path, invisibly, or `NULL` when writing to a connection.
#' @seealso [stream_in()] to read newline-delimited JSON.
#' @examples
#' path <- tempfile(fileext = ".ndjson")
#'
#' # One record per data-frame row
#' stream_out(data.frame(id = 1:3, name = c("A", "B", "C")), path)
#' readLines(path)
#'
#' # Batches produced on demand by a function that finally returns NULL
#' i <- 0L
#' stream_out(function() {
#'   i <<- i + 1L
#'   if (i > 3L) return(NULL)
#'   data.frame(batch = i, value = c(0.5, 1.5))
#' }, path)
#' stream_in(path)
#'
#' # A connection, here compressed
#' zipped <- tempfile(fileext = ".ndjson.gz")
#' stream_out(data.frame(id = 1:3), gzfile(zipped))
#' stream_in(gzfile(zipped))
#' unlink(c(path, zipped))
#' @export
stream_out <- function(x, con, pagesize = 500L, verbose = FALSE, ...) {
  args <- list(...)
  if (!"auto_unbox" %in% names(args)) args$auto_unbox <- TRUE
  opts <- do.call(.writer_options, args)
  opts$dataframe <- "rows"
  opts$indent <- -1L
  if (!is.numeric(pagesize) || length(pagesize) != 1L || !is.finite(pagesize) ||
      pagesize < 1) {
    stop("pagesize must be a positive number", call. = FALSE)
  }
  next_batch <- if (is.function(x)) x else {
    used <- FALSE
    function() {
      if (used) return(NULL)
      used <<- TRUE
      x
    }
  }
  if (inherits(con, "connection")) {
    if (!isOpen(con)) {
      open(con, "wb")
      on.exit(close(con), add = TRUE)
    }
    repeat {
      batch <- next_batch()
      if (is.null(batch)) break
      n <- if (is.data.frame(batch)) nrow(batch) else length(batch)
      from <- 1
      repeat {
        # Also runs once for an empty batch, so that its type is checked.
        to <- min(n, from + pagesize - 1)
        text <- .Call(glazelite_stream_batch, batch, NULL, opts, c(from, to))
        writeLines(text, con, sep = "", useBytes = TRUE)
        from <- to + 1
        if (from > n) break
      }
    }
    return(invisible(NULL))
  }
  path <- .check_path(con)
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  # Create the file even when the iterator yields no records.
  if (!file.create(tmp)) stop("cannot create output file")
  repeat {
    batch <- next_batch()
    if (is.null(batch)) break
    .Call(glazelite_stream_batch, batch, tmp, opts, NULL)
  }
  if (!file.rename(tmp, path)) stop("could not move completed JSON file into place")
  invisible(path)
}

#' Mark a value as a JSON scalar
#'
#' By default a vector of length one is written as a JSON array with one
#' element. `unbox()` marks a single value so that [toJSON()] writes it as a
#' scalar, without unboxing every length-one vector as `auto_unbox = TRUE`
#' does. A data frame with one row is written as a single object.
#' @param x An atomic vector of length one, or a data frame with one row.
#' @return `x` with the additional class `"scalar"`; `NULL` is returned as is.
#' @seealso The `auto_unbox` argument of [toJSON()].
#' @examples
#' toJSON(list(id = unbox(1L), tags = "a"))
#' toJSON(list(first = unbox(data.frame(id = 1L, name = "A"))))
#' @export
unbox <- function(x) {
  if (is.null(x)) return(x)
  if (is.data.frame(x)) {
    if (nrow(x) != 1L) {
      stop("only data frames with one row can be unboxed, not ", nrow(x), " rows",
           call. = FALSE)
    }
  } else if (!is.atomic(x) || length(dim(x)) > 1L) {
    stop("only atomic vectors of length one and data frames with one row can be unboxed",
         call. = FALSE)
  } else if (length(x) != 1L) {
    stop("only vectors of length one can be unboxed, not length ", length(x),
         call. = FALSE)
  }
  class(x) <- c("scalar", class(x))
  x
}

.writer_options <- function(dataframe = c("rows", "columns", "values"),
                            Date = c("ISO8601", "epoch"),
                            POSIXt = c("string", "ISO8601", "epoch", "mongo"),
                            factor = c("string", "integer"),
                            null = c("list", "null"), na = c("null", "string"),
                            auto_unbox = FALSE, digits = NA, pretty = FALSE,
                            always_decimal = FALSE, UTC = FALSE,
                            rownames = NULL) {
  dataframe <- match.arg(dataframe)
  Date <- match.arg(Date)
  POSIXt <- match.arg(POSIXt)
  factor <- match.arg(factor)
  null <- match.arg(null)
  na <- match.arg(na)
  .check_flag(auto_unbox, "auto_unbox")
  .check_flag(always_decimal, "always_decimal")
  .check_flag(UTC, "UTC")
  if (!is.null(rownames)) .check_flag(rownames, "rownames")
  list(dataframe = dataframe, Date = Date, POSIXt = POSIXt, factor = factor,
       null = null, na = na, auto_unbox = auto_unbox,
       digits = .check_digits(digits), digits_signif = inherits(digits, "AsIs"),
       indent = .check_pretty(pretty), always_decimal = always_decimal,
       rownames = if (is.null(rownames)) NA else rownames,
       time_format = .time_formatter(POSIXt, UTC))
}

# Date-times are formatted by R, once per vector, so that time zones and
# daylight saving follow R's rules.
.time_formatter <- function(POSIXt, UTC) {
  force(POSIXt)
  force(UTC)
  function(x) {
    x <- as.POSIXct(x)
    if (POSIXt %in% c("epoch", "mongo")) return(floor(as.numeric(x) * 1000))
    template <- if (POSIXt == "string") {
      ""
    } else if (UTC) {
      "%Y-%m-%dT%H:%M:%SZ"
    } else {
      "%Y-%m-%dT%H:%M:%S"
    }
    as.vector(if (UTC) format(x, template, tz = "UTC") else format(x, template))
  }
}

.check_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    stop(name, " must be TRUE or FALSE", call. = FALSE)
  }
  invisible(NULL)
}

.check_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path))
    stop("path must be one non-empty string", call. = FALSE)
  path.expand(path)
}

.check_digits <- function(digits) {
  if (length(digits) == 1L && (is.numeric(digits) || is.logical(digits))) {
    if (is.na(digits)) return(NA_integer_)
    if (is.numeric(digits) && is.finite(digits) && digits >= 0) {
      return(as.integer(min(digits, 22)))
    }
  }
  stop("digits must be NA or a single non-negative number", call. = FALSE)
}

.check_pretty <- function(pretty) {
  if (length(pretty) == 1L && !is.na(pretty)) {
    if (is.logical(pretty)) return(if (pretty) 2L else -1L)
    if (is.numeric(pretty) && is.finite(pretty) && pretty >= 0) {
      return(as.integer(min(pretty, 64)))
    }
  }
  stop("pretty must be TRUE, FALSE or a non-negative number of spaces",
       call. = FALSE)
}

.check_txt <- function(txt) {
  if (!is.character(txt) || length(txt) != 1L || is.na(txt))
    stop("txt must be one JSON string", call. = FALSE)
  invisible(NULL)
}

#' Reformat or check JSON text
#'
#' `prettify()` adds line breaks and indentation to JSON text and `minify()`
#' removes all optional whitespace. Neither changes the content: numbers and
#' strings are kept exactly as they are written. `validate()` tests whether a
#' string is valid JSON.
#' @param txt A length-one JSON string.
#' @param indent Number of spaces per indentation level.
#' @return `prettify()` and `minify()` return the reformatted JSON as a
#'   length-one character vector of class `c("glazelite_json", "json")`, and
#'   raise an error when `txt` is not valid JSON. `validate()` returns `TRUE`
#'   or `FALSE`; a `FALSE` result has an attribute `"err"` with a message.
#' @examples
#' json <- toJSON(list(id = 1L, tags = c("a", "b")), auto_unbox = TRUE)
#' prettify(json)
#' prettify(json, indent = 2)
#' minify('{ "id" : 1 , "tags" : [ "a", "b" ] }')
#' validate(json)
#' validate('{"id": 1')
#' @export
prettify <- function(txt, indent = 4) {
  .check_txt(txt)
  if (!is.numeric(indent) || length(indent) != 1L || !is.finite(indent) ||
      indent < 0 || indent > 64) {
    stop("indent must be a number between 0 and 64", call. = FALSE)
  }
  .as_json(.Call(glazelite_prettify, txt, as.integer(indent)))
}

#' @rdname prettify
#' @export
minify <- function(txt) {
  .check_txt(txt)
  .as_json(.Call(glazelite_minify, txt))
}

#' @rdname prettify
#' @export
validate <- function(txt) {
  .check_txt(txt)
  ok <- .Call(glazelite_validate, txt)
  if (!ok) attr(ok, "err") <- "invalid JSON input"
  ok
}

#' Parse JSON text with Glaze
#'
#' JSON objects become named lists, arrays become lists or, when simplified,
#' atomic vectors, matrices and data frames. JSON `null` becomes `NULL`, or
#' `NA` inside a simplified vector, matrix or data frame.
#'
#' @section Simplification:
#' With `simplifyVector = TRUE`, an array whose elements are all strings, all
#' booleans or all numbers (apart from `null`) becomes a character, logical,
#' integer or double vector. Numbers are integers when every one of them is a
#' whole number that fits R's integer type, and doubles otherwise. Arrays that
#' mix these types, contain objects, or contain only `null` stay lists.
#'
#' With `simplifyMatrix = TRUE`, arrays of equally long arrays of scalars of
#' one type become a matrix, with one row per inner array. Deeper regular
#' nestings become arrays of three or more dimensions. This reverses what
#' [toJSON()] writes for a matrix or an array.
#'
#' With `simplifyDataFrame = TRUE`, an array of objects becomes a data frame
#' when every field holds scalars of one type. Fields missing from a record
#' are `NA`. Arrays of objects with nested or mixed-type fields stay lists of
#' records.
#' @param txt A length-one JSON string. If it names an existing file, that
#'   file is read with [read_json()].
#' @param simplifyVector Simplify arrays of scalar values to atomic vectors.
#' @param simplifyDataFrame Simplify arrays of records to data frames. Has no
#'   effect unless `simplifyVector` is also `TRUE`.
#' @param simplifyMatrix Simplify regular arrays of arrays to matrices and
#'   higher-dimensional arrays. Has no effect unless `simplifyVector` is also
#'   `TRUE`.
#' @return An R object: a named list for a JSON object; a list, atomic vector,
#'   matrix, array or data frame for a JSON array; a length-one vector for a
#'   JSON scalar; and `NULL` for JSON `null`.
#' @seealso [toJSON()] for the reverse conversion, [read_json()] to parse a
#'   file.
#' @examples
#' fromJSON('{"id": 1, "tags": ["a", "b"], "ok": true}')
#' fromJSON('[1, 2.5, null]')
#' fromJSON('[[1, 2, 3], [4, 5, 6]]')
#' fromJSON('[{"id": 1, "name": "A"}, {"id": 2, "name": "B"}]')
#' fromJSON('[{"id": 1}, {"id": 2}]', simplifyDataFrame = FALSE)
#' @export
fromJSON <- function(txt, simplifyVector = TRUE,
                     simplifyDataFrame = simplifyVector,
                     simplifyMatrix = simplifyVector) {
  if (!is.character(txt) || length(txt) != 1L || is.na(txt))
    stop("txt must be one JSON string")
  if (file.exists(txt)) {
    return(read_json(txt, simplifyVector, simplifyDataFrame, simplifyMatrix))
  }
  .Call(glazelite_from_json, txt, simplifyVector, simplifyDataFrame,
        simplifyMatrix)
}

#' Parse a JSON file with Glaze
#'
#' This avoids loading the file as an R string, but the parsed R object still
#' occupies memory. A JSON token longer than the native input window is not
#' supported; use [stream_in()] for NDJSON records.
#'
#' As in jsonlite, `read_json()` returns nested lists unless
#' `simplifyVector = TRUE`.
#' @param path Input file path.
#' @inheritParams fromJSON
#' @inherit fromJSON return
#' @seealso [write_json()] to write a JSON file, [stream_in()] for
#'   newline-delimited JSON.
#' @examples
#' path <- tempfile(fileext = ".json")
#' write_json(list(id = 1L, values = c(1.5, 2.5)), path, auto_unbox = TRUE)
#' read_json(path)
#' read_json(path, simplifyVector = TRUE)
#' unlink(path)
#' @export
read_json <- function(path, simplifyVector = FALSE,
                      simplifyDataFrame = simplifyVector,
                      simplifyMatrix = simplifyVector) {
  path <- .check_path(path)
  .Call(glazelite_read_json, path, simplifyVector, simplifyDataFrame,
        simplifyMatrix)
}

#' Read newline-delimited JSON in pages
#'
#' Each non-empty line is parsed as one JSON record. Supply a `handler` to
#' process the input page by page without collecting all of it in memory.
#' Records are simplified as the elements of one JSON array would be by
#' [fromJSON()]; with a `handler`, each page is simplified on its own.
#' @param con An input path or an R connection. A connection that is not yet
#'   open is opened for reading and closed again on exit.
#' @param handler Optional function called for each page. When absent, pages
#'   are collected and returned.
#' @param pagesize Number of lines read per page when a `handler` is given.
#' @param verbose Accepted for compatibility with jsonlite and ignored.
#' @inheritParams fromJSON
#' @return Without a `handler`, the collected records: a data frame when all
#'   records are objects with scalar fields and `simplifyDataFrame = TRUE`,
#'   otherwise a list or vector with one element per record. With a `handler`,
#'   `NULL`, invisibly.
#' @seealso [stream_out()] to write newline-delimited JSON.
#' @examples
#' path <- tempfile(fileext = ".ndjson")
#' stream_out(data.frame(id = 1:5, value = c(0.5, 1.5, 2.5, 3.5, 4.5)), path)
#'
#' stream_in(path)
#'
#' # Process two records at a time instead of collecting them
#' total <- 0
#' stream_in(path, handler = function(page) total <<- total + sum(page$value),
#'           pagesize = 2)
#' total
#' unlink(path)
#' @export
stream_in <- function(con, handler = NULL, pagesize = 500L, verbose = FALSE,
                      simplifyVector = TRUE,
                      simplifyDataFrame = simplifyVector,
                      simplifyMatrix = simplifyVector) {
  stopifnot(length(pagesize) == 1L, is.finite(pagesize), pagesize > 0)
  if (is.character(con)) {
    con <- file(.check_path(con), open = "rt", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
  } else if (inherits(con, "connection")) {
    if (!isOpen(con)) {
      # readLines() would otherwise reopen the connection for every page.
      open(con, "rt")
      on.exit(close(con), add = TRUE)
    }
  } else {
    stop("con must be a file path or a connection", call. = FALSE)
  }
  if (is.null(handler)) {
    # Simplification needs all records at once, so parse them together.
    records <- .Call(glazelite_from_ndjson, readLines(con, warn = FALSE),
                     simplifyVector, simplifyDataFrame, simplifyMatrix)
    return(if (is.null(records)) data.frame() else records)
  }
  repeat {
    lines <- readLines(con, n = pagesize, warn = FALSE)
    if (!length(lines)) break
    page <- .Call(glazelite_from_ndjson, lines, simplifyVector,
                  simplifyDataFrame, simplifyMatrix)
    if (!is.null(page)) handler(page)
  }
  invisible(NULL)
}
