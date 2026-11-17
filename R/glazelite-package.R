#' glazelite: Fast JSON Reading and Writing with the Glaze C++ Library
#'
#' glazelite reads and writes JSON using the header-only C++ library
#' [Glaze](https://github.com/stephenberry/glaze) by Stephen Berry. It offers a
#' subset of the 'jsonlite' interface:
#'
#' * [toJSON()] and [fromJSON()] convert between R objects and JSON text.
#' * [write_json()] and [read_json()] work directly on files. Writing is
#'   incremental, so a document may be larger than a single R string.
#' * [stream_out()] and [stream_in()] write and read newline-delimited JSON
#'   (NDJSON) in batches.
#'
#' @section Credits:
#' All JSON encoding and parsing is done by Glaze, which is bundled with the
#' package under the MIT license. Glaze in turn includes code from the
#' 'fast_float', 'zmij' and 'xxh64' projects. See the file `COPYRIGHTS` in the
#' installed package for details.
#'
#' @keywords internal
#' @useDynLib glazelite, .registration = TRUE
"_PACKAGE"
