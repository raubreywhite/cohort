# Version 2026.5.10

Initial release.

## Features

- `CohortPipeline` R6 class for cohort construction with full provenance:
  - Branched cohort trees via `$new_cohort(name, from)`.
  - Per-step exclusion logging via `$exclude_and_track(branch, reason, expr_str)`.
  - Cached derived artifacts via `$set_artifact(name, from, fn)`.
  - Schema validation via `$declare_schema()` and `$validate()`.
  - CONSORT diagram generation via `$draw_consort_panels()`.
- `add_data_from_cohort()` — bulk-ingest cohort artifacts into a `plnr::Plan`.

## Implementation notes

- Shared base table + per-branch integer index of included rows. Branching
  is O(1) memory; full deep copies of the data table are avoided.
- Integer status codes (per branch) replace in-band string status columns.
  The user's data table is never mutated.
- Exclusion logs accumulate in a list and materialize on read, avoiding
  quadratic `rbind` growth.
- `$get_included()` defaults to returning an independent copy. An opt-in
  `copy = FALSE` path returns a view of the shared base; callers must
  treat the result as read-only.
- `$get_everyone()` reconstructs a per-branch full view (rows + a
  `.cohort_status` column) so the returned object is meaningful for any
  branch in the tree.
