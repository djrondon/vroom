#' @useDynLib vroom, .registration = TRUE
#' @importFrom Rcpp sourceCpp
NULL

#' Read a delimited file into a tibble
#'
#' @inheritParams readr::read_delim
#' @param file path to a local file.
#' @param delim One of more characters used to delimiter fields within a
#'   record. If `NULL` the delimiter is guessed from the set of (",", "\\t", " ",
#'   "|", ":", ";", "\\n").
#' @param num_threads Number of threads to use when reading and materializing vectors.
#' @param escape_double Does the file escape quotes by doubling them?
#'   i.e. If this option is `TRUE`, the value `""` represents
#'   a single quote, `"`.
#' @param id Either a string or 'NULL'. If a string, the output will contain a
#'   variable with that name with the filename(s) as the value. If 'NULL', the
#'   default, no variable will be created.
#' @export
#' @examples
#' \dontshow{
#' .old_wd <- setwd(tempdir())
#' }
#'
#' readr::write_tsv(mtcars, "mtcars.tsv")
#' vroom("mtcars.tsv")
#'
#' \dontshow{
#' unlink("mtcars.tsv")
#' setwd(.old_wd)
#' }
vroom <- function(file, delim = NULL, col_names = TRUE, col_types = NULL, id = NULL, skip = 0, na = c("", "NA"),
  quote = '"', comment = "", trim_ws = TRUE, escape_double = TRUE, escape_backslash = FALSE, locale = readr::default_locale(),
  guess_max = 100, num_threads = parallel::detectCores(), progress = show_progress()) {

  file <- standardise_path(file)

  out <- vroom_(file, delim = delim, col_names = col_names, col_types = col_types, id = id, skip = skip,
    na = na, quote = quote, trim_ws = trim_ws, escape_double = escape_double,
    escape_backslash = escape_backslash, comment = comment, locale = locale,
    guess_max = guess_max,
    use_altrep = getRversion() > "3.5.0" && as.logical(getOption("vroom.use_altrep", TRUE)),
    num_threads = num_threads, progress = progress)

  tibble::as_tibble(out)
}

#' Guess the type of a vector
#'
#' @inheritParams readr::guess_parser
guess_type <- function(x, na = c("", "NA"), locale = readr::default_locale(), guess_integer = FALSE) {

  x[x %in% na] <- NA

  type <- readr::guess_parser(x, locale = locale, guess_integer = guess_integer)
  get(paste0("col_", type), asNamespace("readr"))()
}

col_types_standardise <- function(col_types, col_names) {
  spec <- readr::as.col_spec(col_types)
  type_names <- names(spec$cols)

  if (length(spec$cols) == 0) {
    # no types specified so use defaults

    spec$cols <- rep(list(spec$default), length(col_names))
    names(spec$cols) <- col_names
  } else if (is.null(type_names)) {
    # unnamed types & names guessed from header: match exactly

    if (length(spec$cols) != length(col_names)) {
      warning("Unnamed `col_types` should have the same length as `col_names`. ",
        "Using smaller of the two.", call. = FALSE)
      n <- min(length(col_names), length(spec$cols))
      spec$cols <- spec$cols[seq_len(n)]
      col_names <- col_names[seq_len(n)]
    }

    names(spec$cols) <- col_names
  } else {
    # names types

    bad_types <- !(type_names %in% col_names)
    if (any(bad_types)) {
      warning("The following named parsers don't match the column names: ",
        paste0(type_names[bad_types], collapse = ", "), call. = FALSE)
      spec$cols <- spec$cols[!bad_types]
      type_names <- type_names[!bad_types]
    }

    default_types <- !(col_names %in% type_names)
    if (any(default_types)) {
      defaults <- rep(list(spec$default), sum(default_types))
      names(defaults) <- col_names[default_types]
      spec$cols[names(defaults)] <- defaults
    }

    spec$cols <- spec$cols[col_names]
  }

  spec
}

make_names <- function(len) {
  make.names(seq_len(len))
}

#' Determine progress bars should be shown
#'
#' Progress bars are shown _unless_ one of the following is `TRUE`
#' - The bar is explicitly disabled by setting `options(vroom.show_progress = FALSE)`
#' - The code is run in a non-interactive session (`interactive()` is `FALSE`).
#' - The code is run in an RStudio notebook chunk.
#' - The code is run by knitr / rmarkdown.
#' - The code is run by testthat (the `TESTTHAT` envvar is `true`).
#' @export
show_progress <- function() {
  isTRUE(getOption("vroom.show_progress", default = TRUE)) &&
    interactive() &&
    !isTRUE(getOption("knitr.in.progress")) &&
    !isTRUE(getOption("rstudio.notebook.executing")) &&
    !isTRUE(as.logical(Sys.getenv("TESTTHAT", "false")))
}

#' @importFrom crayon blue cyan green bold reset col_nchar
pb_file_format <- function(filename) {
  glue::glue_col("{bold}indexing{reset} {blue}{basename(filename)}{reset} [:bar] {green}:rate{reset}, eta: {cyan}:eta{reset}")
}

pb_width <- function(format) {
  ansii_chars <- nchar(format) - col_nchar(format)
  getOption("width", 80L) + ansii_chars
}

pb_connection_format <- function(unused) {
  glue::glue_col("{bold}indexed{reset} {green}:bytes{reset} in {cyan}:elapsed{reset}, {green}:rate{reset}")
}

# Guess delimiter by splitting every line by each delimiter and choosing the
# delimiter which splits the lines into the highest number of consistent fields
guess_delim <- function(lines, delims = c(",", "\t", " ", "|", ":", ";", "\n")) {
  if (length(lines) == 0) {
    return("")
  }

  splits <- lapply(delims, strsplit, x = lines, useBytes = TRUE, fixed = TRUE)

  counts <- lapply(splits, function(x) table(lengths(x)))

  choose_best <- function(i, j) {
    x <- counts[[i]]
    y <- counts[[j]]

    nx <- as.integer(names(counts[[i]]))
    ny <- as.integer(names(counts[[j]]))

    mx <- which.max(x)
    my <- which.max(y)

    if (x[[mx]] > y[[my]] ||
      x[[mx]] == y[[my]] && nx > ny) {
      i
    } else {
      j
    }
  }
  res <- Reduce(choose_best, seq_along(counts))
  delims[[res]]
}

