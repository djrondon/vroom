context("test-multi-file.R")


test_that("vroom adds the id column from the filename for one file", {
  res <- vroom(vroom_example("mtcars.csv"), id = "filename")
  expect_true(all(res$filename == vroom_example("mtcars.csv")))
})

test_that("vroom adds the id column from the filename for multiple files", {
  dir <- tempfile()
  dir.create(dir)

  splits <- split(mtcars, mtcars$cyl)
  for (i in seq_along(splits)) {
    readr::write_tsv(splits[[i]], file.path(dir, paste0("mtcars_", names(splits)[[i]], ".tsv")))
  }

  files <- list.files(dir, full.names = TRUE)

  res <- vroom(files, id = "filename")

  # construct what the filename column should look like
  filenames <- paste0("mtcars_", rep(names(splits), vapply(splits, nrow, integer(1))), ".tsv")

  expect_equal(basename(res$filename), filenames)
})
