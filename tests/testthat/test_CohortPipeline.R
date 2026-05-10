library(data.table)

make_test_dt <- function() {
  data.table(
    id  = 1:10,
    age = c(17, 22, 35, NA, 41, 28, 19, 16, 67, 50),
    sex = c("F", "M", "F", "F", NA, "M", "M", "F", "F", "M"),
    grp = c("a", "a", "b", "b", "a", "b", "a", "b", "a", "b")
  )
}

test_that("load installs root cohort and copies user data", {
  d <- make_test_dt()
  cp <- CohortPipeline$new()
  cp$load(d)

  expect_equal(cp$n_total(), 10L)
  expect_equal(cp$n_included("root"), 10L)

  # Mutating the user's dt does not change the pipeline's view.
  d[, age := age + 100]
  expect_equal(cp$get_included("root")$age[1], 17)
})

test_that("exclude_and_track records the log and removes rows", {
  cp <- CohortPipeline$new(make_test_dt())
  cp$exclude_and_track("root", "Missing sex", "is.na(sex)")
  cp$exclude_and_track("root", "Missing age", "is.na(age)")
  cp$exclude_and_track("root", "Under 18",    "age < 18")

  expect_equal(cp$n_included("root"), 6L)

  log <- cp$consort()
  expect_equal(nrow(log), 3L)
  expect_equal(log$reason, c("Missing sex", "Missing age", "Under 18"))
  expect_equal(log$n_excluded, c(1L, 1L, 2L))
  expect_equal(log$n_remaining, c(9L, 8L, 6L))
  expect_equal(log$expr_str, c("is.na(sex)", "is.na(age)", "age < 18"))
})

test_that("NA predicate values are treated as FALSE (rows kept)", {
  cp <- CohortPipeline$new(make_test_dt())
  # Predicate evaluates to NA on rows where age is NA; those rows survive.
  cp$exclude_and_track("root", "Strictly under 18", "age < 18")
  expect_true(4L %in% cp$get_included("root")$id) # row 4 has NA age
})

test_that("new_cohort creates an independent branch", {
  cp <- CohortPipeline$new(make_test_dt())
  cp$exclude_and_track("root", "Missing sex", "is.na(sex)")

  cp$new_cohort("females", from = "root")
  cp$exclude_and_track("females", "Not female", "sex != 'F'")

  # Parent unchanged
  expect_equal(cp$n_included("root"), 9L)
  # Child reflects further exclusion
  expect_equal(cp$n_included("females"), 5L)
  expect_setequal(cp$get_included("females")$sex, "F")

  # Subsequent root-side exclusions do not propagate to the child.
  cp$exclude_and_track("root", "Under 18", "age < 18")
  expect_equal(cp$n_included("root"), 7L)
  expect_equal(cp$n_included("females"), 5L)
})

test_that("get_included returns an independent copy", {
  cp <- CohortPipeline$new(make_test_dt())
  out <- cp$get_included("root")
  out[, age := age * 0]
  expect_equal(cp$get_included("root")$age[1], 17)
})

test_that("get_everyone reconstructs full per-row status", {
  cp <- CohortPipeline$new(make_test_dt())
  cp$exclude_and_track("root", "Missing sex", "is.na(sex)")
  cp$exclude_and_track("root", "Under 18",    "age < 18")

  ev <- cp$get_everyone("root")
  expect_equal(nrow(ev), 10L)
  expect_true(".cohort_status" %in% names(ev))
  expect_equal(sum(ev$.cohort_status == "included"), cp$n_included("root"))
  expect_true("Missing sex" %in% ev$.cohort_status)
  expect_true("Under 18" %in% ev$.cohort_status)

  # Branch view: child sees parent's exclusions plus its own.
  cp$new_cohort("adults", from = "root")
  cp$exclude_and_track("adults", "Female", "sex == 'F'")
  ev2 <- cp$get_everyone("adults")
  expect_equal(nrow(ev2), 10L)
  expect_true("Female" %in% ev2$.cohort_status)
  # Inherited reasons from parent are still visible on the child.
  expect_true("Missing sex" %in% ev2$.cohort_status)
})

test_that("set_artifact caches results and exposes siblings", {
  cp <- CohortPipeline$new(make_test_dt())
  cp$set_artifact("n", from = "root",
    fn = function(dt, sib) nrow(dt))
  cp$set_artifact("groups", from = "root",
    fn = function(dt, sib) {
      stopifnot("n" %in% names(sib))
      sort(unique(dt$grp))
    })

  expect_equal(cp$get_artifact("root", "n"), 10L)
  expect_equal(cp$get_artifact("root", "groups"), c("a", "b"))
  expect_setequal(cp$list_artifacts("root"), c("n", "groups"))
})

test_that("set_artifact callbacks may freely mutate the dt argument", {
  cp <- CohortPipeline$new(make_test_dt())
  cp$set_artifact("mutated_dt", from = "root",
    fn = function(dt, sib) {
      dt[, age := age * 2]   # mutate the supplied dt
      dt
    })
  # Pipeline's view is untouched
  expect_equal(cp$get_included("root")$age[1], 17)
  # Cached artifact saw the mutation
  expect_equal(cp$get_artifact("root", "mutated_dt")$age[1], 34)
})

test_that("schemas validate types, levels, and NA constraints", {
  cp <- CohortPipeline$new(make_test_dt())
  cp$exclude_and_track("root", "Missing sex", "is.na(sex)")
  cp$exclude_and_track("root", "Missing age", "is.na(age)")
  cp$declare_schema("root", schema = list(
    age = list(type = "numeric", na = FALSE),
    sex = list(type = "character", na = FALSE)
  ))
  expect_message(cp$validate(), "schemas passed")

  # Add a wrong-type spec
  cp$declare_schema("root", schema = list(
    age = list(type = "integer", na = FALSE)
  ), from = "root")
  expect_error(cp$validate(), "expected integer")
})

test_that("auto_validate raises on schema mismatch at the failure site", {
  cp <- CohortPipeline$new(make_test_dt(), auto_validate = TRUE)
  cp$declare_schema("root", schema = list(
    sex = list(type = "character", na = FALSE)  # NAs present!
  ))
  expect_error(cp$new_cohort("foo", from = "root"), "unexpected NAs")
})

test_that("list_cohorts and consort return tidy data.tables", {
  cp <- CohortPipeline$new(make_test_dt())
  cp$exclude_and_track("root", "Missing sex", "is.na(sex)")
  cp$new_cohort("females", from = "root")
  cp$exclude_and_track("females", "Not female", "sex != 'F'")

  cohorts <- cp$list_cohorts()
  expect_setequal(cohorts$name, c("root", "females"))
  expect_equal(cohorts[name == "females", parent], "root")
  expect_equal(cohorts[name == "root", n_own_steps], 1L)
  expect_equal(cohorts[name == "females", n_own_steps], 1L)

  log <- cp$consort()
  # Each branch should contribute only its OWN log entries.
  expect_equal(nrow(log), 2L)
  expect_setequal(log$branch, c("root", "females"))
})

test_that("error paths reject unknown branches and duplicate names", {
  cp <- CohortPipeline$new(make_test_dt())
  expect_error(cp$exclude_and_track("nope", "x", "TRUE"), "unknown branch")
  expect_error(cp$new_cohort("ok", from = "nope"),       "unknown parent")
  cp$new_cohort("ok", from = "root")
  expect_error(cp$new_cohort("ok", from = "root"),       "already exists")
  expect_error(cp$get_artifact("root", "missing"),       "unknown artifact")
})

test_that("predicate length mismatch is reported clearly", {
  cp <- CohortPipeline$new(make_test_dt())
  expect_error(
    cp$exclude_and_track("root", "Bad", "TRUE"),  # length-1, not nrow
    "predicate returned length"
  )
})

