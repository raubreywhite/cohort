What’s inside

01

### Branched cohort trees

Share one base table; each branch keeps an O(n) integer status vector,
so branching never copies the underlying data values.

02

### Exclusion provenance

`cohort` logs every exclusion with a human-readable reason and a
serializable string predicate, ready to render as a CONSORT diagram.

03

### Cached artifacts

Attach derived objects to any cohort and hand out mutation-safe copies
to whatever consumes analytic data downstream.
