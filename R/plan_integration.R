#' Add cohort artifacts to a `plnr::Plan` in bulk
#'
#' @description
#' Bulk-ingest one or more cached artifacts from a `CohortPipeline` cohort
#' into a `plnr::Plan` as named data entries. This replaces the typical
#' nested for-loop that calls `plan$add_data(name, direct = ...)` once per
#' (cohort, artifact) pair.
#'
#' @details
#' For each artifact name supplied, the helper retrieves it from the
#' specified cohort and registers it on the plan via
#' `plan$add_data(name, direct = ...)`. The data-entry name on the plan
#' is composed as `paste0(prefix, cohort, "__", artifact)`.
#'
#' This function is the only point of contact between `cohort` and the
#' `plnr` package. `plnr` is declared in `Suggests`, not `Imports`, so
#' you must have it installed to use this helper.
#'
#' @param plan A `plnr::Plan` instance.
#' @param cp A `CohortPipeline` instance.
#' @param cohort Character. Name of the cohort to draw artifacts from.
#' @param artifacts Character vector. Artifact names on `cohort` to
#'   register. Defaults to every artifact attached to that cohort.
#' @param prefix Character. Prefix prepended to the data-entry name on
#'   the plan. Defaults to `""`. The full entry name is
#'   `paste0(prefix, cohort, "__", artifact)`.
#'
#' @return The `plan` (invisibly), modified in place.
#'
#' @examples
#' if (requireNamespace("plnr", quietly = TRUE) &&
#'     requireNamespace("data.table", quietly = TRUE)) {
#'   library(data.table)
#'
#'   d <- data.table(id = 1:6, age = c(20, 30, 40, 50, 60, 70))
#'   cp <- CohortPipeline$new()
#'   cp$load(d)
#'   cp$exclude_and_track("root", "Under 30", "age < 30")
#'
#'   cp$set_artifact("dt",
#'     from = "root",
#'     fn = function(dt, sib) dt
#'   )
#'   cp$set_artifact("n",
#'     from = "root",
#'     fn = function(dt, sib) nrow(dt)
#'   )
#'
#'   plan <- plnr::Plan$new()
#'   add_data_from_cohort(plan, cp, cohort = "root")
#'   plan$get_data()
#' }
#'
#' @seealso [CohortPipeline]
#' @export
add_data_from_cohort <- function(plan, cp, cohort,
                                 artifacts = NULL, prefix = "") {
  if (!requireNamespace("plnr", quietly = TRUE)) {
    stop("add_data_from_cohort: 'plnr' must be installed.", call. = FALSE)
  }
  if (!inherits(plan, "Plan")) {
    stop("add_data_from_cohort: 'plan' must be a plnr::Plan instance.",
      call. = FALSE)
  }
  if (!inherits(cp, "CohortPipeline")) {
    stop("add_data_from_cohort: 'cp' must be a CohortPipeline instance.",
      call. = FALSE)
  }
  if (!is.character(cohort) || length(cohort) != 1L) {
    stop("add_data_from_cohort: 'cohort' must be a single character string.",
      call. = FALSE)
  }
  if (is.null(artifacts)) {
    artifacts <- cp$list_artifacts(cohort)
  }
  if (length(artifacts) == 0L) {
    return(invisible(plan))
  }
  for (art in artifacts) {
    nm <- paste0(prefix, cohort, "__", art)
    plan$add_data(name = nm, direct = cp$get_artifact(cohort, art))
  }
  invisible(plan)
}
