# Version 2026.5.10

Initial release.

## Features

- `CohortPipeline` R6 class for cohort construction with full provenance:
  - Branched cohort trees via `$new_cohort(name, from)`.
  - Per-step exclusion logging via `$exclude_and_track(branch, reason, expr_str)`.
  - Cached derived artifacts via `$set_artifact(name, from, fn)`.
  - Schema validation via `$declare_schema()` and `$validate()`.
  - CONSORT diagram generation via `$plot()` (auto-discovered) or
    `$draw_consort_panels()` (manual layouts).

## The freeze rule

A cohort becomes **frozen** the first time another cohort branches from
it, or the first time an artifact is set on it. After freezing,
`$exclude_and_track()` on that cohort errors. The rule guarantees a
cohort's name maps to exactly one definition forever and that cached
artifacts stay consistent with the included rows that produced them.
Multi-way forks are unaffected.

## Implementation notes

- Shared base table + per-branch integer index of included rows.
  Branching never copies the data values.
- Integer status codes (per branch) replace in-band string status
  columns. The user's data table is never mutated.
- Exclusion logs accumulate in a list and materialize on read, avoiding
  quadratic `rbind` growth.
- `$get_included()` always returns an independent copy.
- `$get_everyone()` reconstructs a per-branch full view (rows + a
  `.cohort_status` column) so the returned object is meaningful for any
  branch in the tree.
- `$plot()` defaults to plotting every frozen cohort, falling back to
  every cohort when none are frozen yet.
