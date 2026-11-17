#' Convert an R object to JSON text
#'
#' This function returns one R string, so it retains R's string-size limit.
#' Use [write_json()] for large output.
#' @param x An atomic vector, array, list, or data frame. Array dimensions are
#'   written in their existing order, including dimensions of length one or zero.
#' @param dataframe Data frame layout: rows, columns, or values.
#' @param auto_unbox Whether length-one atomic vectors become scalars.
#' @param na Encode missing and non-finite values as JSON null or as strings.
#' @param factor Encode factors as level labels (`"string"`, the default) or
#'   integer level indices (`"integer"`).
#' @param always_decimal Distinguish doubles from integers by retaining a decimal
#'   point or exponent in finite double output.
#' @param pretty Whether to indent JSON with two spaces per level. Pretty file
#'   output ends with a newline.
#' @param digits Must be `NA`. Numbers retain full round-trip precision;
#'   rounding to a specified number of digits is not implemented.
#' @return A length-one character vector of class `json`.
#' @seealso [fromJSON()] for the reverse conversion, [write_json()] to write
#'   to a file.
#' @examples
#' toJSON(c(1.5, NA, 3))
#' toJSON(list(id = 1L, tags = c("a", "b")), auto_unbox = TRUE)
#' toJSON(matrix(1:6, nrow = 2))
#'
#' df <- data.frame(id = 1:2, group = factor(c("a", "b")))
#' toJSON(df)
#' toJSON(df, dataframe = "columns", factor = "integer")
#' cat(toJSON(df, pretty = TRUE), "\n")
#' @export
toJSON <- function(x, dataframe = c("rows", "columns", "values"),
                   auto_unbox = FALSE, na = c("null", "string"),
                   factor = c("string", "integer"), always_decimal = FALSE,
                   pretty = FALSE, digits = NA) {
  dataframe <- match.arg(dataframe)
  na <- match.arg(na)
  factor <- match.arg(factor)
  .check_digits(digits)
  structure(.Call(glazelite_to_json, x, auto_unbox, dataframe, na,
                  factor, always_decimal, pretty), class = "json")
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
#' @inheritParams toJSON
#' @param path Destination file path.
#' @return The path, invisibly.
#' @seealso [read_json()] to read the file back, [stream_out()] for
#'   newline-delimited JSON.
#' @examples
#' path <- tempfile(fileext = ".json")
#' write_json(data.frame(id = 1:3, name = c("A", "B", "C")), path)
#' readLines(path, warn = FALSE)
#' read_json(path)
#' unlink(path)
#' @export
write_json <- function(x, path, dataframe = c("rows", "columns", "values"),
                       auto_unbox = FALSE, na = c("null", "string"),
                       factor = c("string", "integer"), always_decimal = FALSE,
                       pretty = FALSE, digits = NA) {
  path <- .check_path(path)
  dataframe <- match.arg(dataframe)
  na <- match.arg(na)
  factor <- match.arg(factor)
  .check_digits(digits)
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  .Call(glazelite_write_json, x, tmp, auto_unbox, dataframe, na,
        factor, always_decimal, pretty)
  if (!file.rename(tmp, path)) stop("could not move completed JSON file into place")
  invisible(path)
}

#' Stream batches as newline-delimited JSON
#'
#' `x` may be a data frame, a list of records, or a zero-argument function
#' returning successive batches and finally `NULL`. Each data-frame row or
#' list element is written as one JSON record. This never creates the full
#' output as an R string.
#' @inheritParams write_json
#' @param x A data frame, list of records, or batch-producing function.
#' @return The path, invisibly.
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
#' unlink(path)
#' @export
stream_out <- function(x, path, auto_unbox = TRUE, na = c("null", "string"),
                       factor = c("string", "integer"),
                       always_decimal = FALSE, digits = NA) {
  path <- .check_path(path)
  na <- match.arg(na)
  factor <- match.arg(factor)
  .check_digits(digits)
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"),
                  tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  # Create the file even when the iterator yields no records.
  if (!file.create(tmp)) stop("cannot create output file")
  next_batch <- if (is.function(x)) x else {
    used <- FALSE
    function() {
      if (used) return(NULL)
      used <<- TRUE
      x
    }
  }
  repeat {
    batch <- next_batch()
    if (is.null(batch)) break
    .Call(glazelite_stream_batch, batch, tmp, auto_unbox, na, TRUE,
          factor, always_decimal)
  }
  if (!file.rename(tmp, path)) stop("could not move completed JSON file into place")
  invisible(path)
}

.check_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path))
    stop("path must be one non-empty string", call. = FALSE)
  path.expand(path)
}

.check_digits <- function(digits) {
  if (!(is.numeric(digits) || is.logical(digits)) || length(digits) != 1L ||
      !is.na(digits)) {
    stop("Only digits = NA is supported; numeric rounding is not implemented.",
         call. = FALSE)
  }
  invisible(NULL)
}

#' Parse JSON text with Glaze
#'
#' JSON objects become named lists, arrays become lists or, when simplified,
#' atomic vectors and data frames. JSON `null` becomes `NULL`, or `NA` inside a
#' simplified vector or data frame.
#'
#' @section Simplification:
#' With `simplifyVector = TRUE`, an array whose elements are all strings, all
#' booleans or all numbers (apart from `null`) becomes a character, logical,
#' integer or double vector. Numbers are integers when every one of them is a
#' whole number that fits R's integer type, and doubles otherwise. Arrays that
#' mix these types, contain nested arrays or objects, or contain only `null`
#' stay lists.
#'
#' With `simplifyDataFrame = TRUE` (which also requires
#' `simplifyVector = TRUE`), an array of objects becomes a data frame when
#' every field holds scalars of one type. Fields missing from a record are
#' `NA`. Arrays of objects with nested or mixed-type fields stay lists of
#' records.
#' @param txt A length-one JSON string. If it names an existing file, that
#'   file is read with [read_json()].
#' @param simplifyVector Simplify arrays of scalar values to atomic vectors.
#' @param simplifyDataFrame Simplify arrays of records to data frames. Has no
#'   effect unless `simplifyVector` is also `TRUE`.
#' @return An R object: a named list for a JSON object, a list, atomic vector
#'   or data frame for a JSON array, a length-one vector for a JSON scalar, and
#'   `NULL` for JSON `null`.
#' @seealso [toJSON()] for the reverse conversion, [read_json()] to parse a
#'   file.
#' @examples
#' fromJSON('{"id": 1, "tags": ["a", "b"], "ok": true}')
#' fromJSON('[1, 2.5, null]')
#' fromJSON('[{"id": 1, "name": "A"}, {"id": 2, "name": "B"}]')
#' fromJSON('[{"id": 1}, {"id": 2}]', simplifyDataFrame = FALSE)
#' @export
fromJSON <- function(txt, simplifyVector = TRUE, simplifyDataFrame = TRUE) {
  if (!is.character(txt) || length(txt) != 1L || is.na(txt))
    stop("txt must be one JSON string")
  if (file.exists(txt)) return(read_json(txt, simplifyVector, simplifyDataFrame))
  .Call(glazelite_from_json, txt, simplifyVector, simplifyDataFrame)
}

#' Parse a JSON file with Glaze
#'
#' This avoids loading the file as an R string, but the parsed R object still
#' occupies memory. A JSON token longer than the native input window is not
#' supported; use [stream_in()] for NDJSON records.
#' @param path Input file path.
#' @inheritParams fromJSON
#' @inherit fromJSON return
#' @seealso [write_json()] to write a JSON file, [stream_in()] for
#'   newline-delimited JSON.
#' @examples
#' path <- tempfile(fileext = ".json")
#' write_json(list(id = 1L, values = c(1.5, 2.5)), path, auto_unbox = TRUE)
#' read_json(path)
#' unlink(path)
#' @export
read_json <- function(path, simplifyVector = TRUE, simplifyDataFrame = TRUE) {
  path <- .check_path(path)
  .Call(glazelite_read_json, path, simplifyVector, simplifyDataFrame)
}

#' Read newline-delimited JSON in pages
#'
#' Each non-empty line is parsed as one JSON record. Supply a `handler` to
#' process the input page by page without collecting all of it in memory.
#' Records are simplified as the elements of one JSON array would be by
#' [fromJSON()]; with a `handler`, each page is simplified on its own.
#' @param path An input path or an R connection. A connection that is not yet
#'   open is opened for reading and closed again on exit.
#' @param handler Optional function called for each page. When absent, pages
#'   are collected and returned.
#' @param pagesize Number of lines read per page when a `handler` is given.
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
stream_in <- function(path, handler = NULL, pagesize = 500L,
                      simplifyVector = TRUE, simplifyDataFrame = TRUE) {
  stopifnot(length(pagesize) == 1L, is.finite(pagesize), pagesize > 0)
  if (is.character(path)) {
    con <- file(.check_path(path), open = "rt", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
  } else if (inherits(path, "connection")) {
    con <- path
    if (!isOpen(con)) {
      # readLines() would otherwise reopen the connection for every page.
      open(con, "rt")
      on.exit(close(con), add = TRUE)
    }
  } else {
    stop("path must be a file path or a connection", call. = FALSE)
  }
  if (is.null(handler)) {
    # Simplification needs all records at once, so parse them together.
    records <- .Call(glazelite_from_ndjson, readLines(con, warn = FALSE),
                     simplifyVector, simplifyDataFrame)
    return(if (is.null(records)) data.frame() else records)
  }
  repeat {
    lines <- readLines(con, n = pagesize, warn = FALSE)
    if (!length(lines)) break
    page <- .Call(glazelite_from_ndjson, lines, simplifyVector, simplifyDataFrame)
    if (!is.null(page)) handler(page)
  }
  invisible(NULL)
}
