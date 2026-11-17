# Vendor the subset of Glaze headers that glazelite compiles against.
#
# Usage (from the package root):
#   Rscript tools/vendor-glaze.R <path-to-glaze-checkout> [<commit>]
#
# <path-to-glaze-checkout> is a clone of https://github.com/stephenberry/glaze
# at the commit to bundle. Only headers reachable from the entry points below
# are copied to inst/include/glaze, which keeps the package small. Add an
# entry point here when the package starts using another part of Glaze.
#
# This directory is listed in .Rbuildignore and is not part of the built
# package.

entry_points <- c("glaze/json.hpp", "glaze/core/istream_buffer.hpp")

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("usage: Rscript tools/vendor-glaze.R <glaze checkout> [<commit>]")
checkout <- normalizePath(args[[1]], mustWork = TRUE)
src <- if (dir.exists(file.path(checkout, "include", "glaze"))) {
  file.path(checkout, "include")
} else {
  checkout  # already an include directory
}
stopifnot(dir.exists(file.path(src, "glaze")), file.exists("DESCRIPTION"))

commit <- if (length(args) > 1L) {
  args[[2]]
} else {
  out <- suppressWarnings(tryCatch(
    system2("git", c("-C", shQuote(checkout), "rev-parse", "HEAD"),
            stdout = TRUE, stderr = FALSE),
    error = function(e) character()))
  if (length(out) == 1L && grepl("^[0-9a-f]{40}$", out)) out else NA_character_
}

includes <- function(file) {
  lines <- readLines(file.path(src, file), warn = FALSE, encoding = "UTF-8")
  m <- regmatches(lines, regexec("^\\s*#\\s*include\\s*[<\"](glaze/[^>\"]+)[>\"]", lines))
  unique(unlist(lapply(m, function(x) if (length(x) == 2L) x[[2]])))
}

reachable <- character()
queue <- entry_points
while (length(queue)) {
  file <- queue[[1]]
  queue <- queue[-1]
  if (file %in% reachable) next
  if (!file.exists(file.path(src, file))) stop("missing header: ", file)
  reachable <- c(reachable, file)
  queue <- c(queue, setdiff(includes(file), reachable))
}
reachable <- sort(reachable)

dest <- file.path("inst", "include")
unlink(file.path(dest, "glaze"), recursive = TRUE)

# CRAN policy: packages must not disable compiler diagnostics, and R CMD check
# warns about such pragmas in bundled headers too. This is the only change
# made to the upstream files; it is documented in inst/COPYRIGHTS.
suppression <- "^\\s*#\\s*pragma\\s+(GCC|clang)\\s+diagnostic\\s+ignored\\b.*$"
replacement <- "// [glazelite] diagnostic-suppressing pragma removed to comply with CRAN policy"
patched <- 0L

# With the pragmas gone, '-pedantic' (used on CRAN) reports the '__int128'
# type aliases as "ISO C++ does not support '__int128'", which R CMD check
# treats as a significant warning. Marking the alias as a compiler extension
# keeps the code identical and silences the warning without a pragma.
int128_alias <- "^(\\s*)using\\s+(\\w+)\\s*=\\s*((?:unsigned\\s+)?__int128)\\s*;(\\r?)$"
int128_fixed <- "\\1__extension__ typedef \\3 \\2; // [glazelite] was a 'using' alias; see inst/COPYRIGHTS\\4"
aliases <- 0L

for (file in reachable) {
  dir.create(dirname(file.path(dest, file)), recursive = TRUE, showWarnings = FALSE)
  # Read and write bytes so that line endings and encoding are kept as is.
  from <- file.path(src, file)
  text <- readChar(from, file.size(from), useBytes = TRUE)
  lines <- strsplit(text, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  hit <- grepl(suppression, lines, perl = TRUE, useBytes = TRUE)
  if (any(hit)) {
    cr <- endsWith(lines[hit], "\r")
    lines[hit] <- paste0(replacement, ifelse(cr, "\r", ""))
    patched <- patched + sum(hit)
  }
  alias <- grepl(int128_alias, lines, perl = TRUE, useBytes = TRUE)
  if (any(alias)) {
    lines[alias] <- sub(int128_alias, int128_fixed, lines[alias], perl = TRUE, useBytes = TRUE)
    aliases <- aliases + sum(alias)
  }
  out <- paste(lines, collapse = "\n")
  if (endsWith(text, "\n")) out <- paste0(out, "\n")
  con <- file(file.path(dest, file), open = "wb")
  writeChar(out, con, eos = NULL, useBytes = TRUE)
  close(con)
}
cat(sprintf("Removed %d diagnostic-suppressing pragmas, marked %d __int128 aliases as extensions\n",
            patched, aliases))

license <- file.path(checkout, "LICENSE")
if (file.exists(license)) file.copy(license, file.path(dest, "GLAZE-LICENSE"), overwrite = TRUE)
if (!is.na(commit)) {
  con <- file(file.path(dest, "GLAZE-COMMIT"), open = "wb")  # LF on every platform
  writeLines(commit, con)
  close(con)
}

size <- sum(file.size(file.path(dest, reachable)))
cat(sprintf("Vendored %d headers (%.1f MB) from %s\n", length(reachable), size / 2^20,
            if (is.na(commit)) "an unknown commit (GLAZE-COMMIT left unchanged)" else commit))
cat("Review inst/COPYRIGHTS and Authors@R in DESCRIPTION if bundled third-party code changed.\n")
