# 01_pipeline

Loading and preparation. **Run 01 through 07 in filename order.**

Step 01 opens with a full reset of every table it owns, so running the sequence
is always a build from scratch. There is no separate reset to remember. The
seven IMDB source tables are never written to.

The sequence is forward only. If a step errors, something is wrong. Do not
suppress it and do not re-run a single file backwards. Start again from 01.

| # | File | What it does | Rows out |
|---|---|---|---|
| 01 | `build_gs` | Resets, then creates the three empty tables | |
| 02 | `load_2025_train` | Class file, 2025 ground truth | 5,549 |
| 03 | `load_personal_rankings` | Class file, personal rankings | 7,445 |
| 04 | `apply_data_quality` | Constraints back on, duplicates removed | 7,045 |
| 05 | `load_2026_test` | Class file, 2026 ground truth | 4,710 |
| 06 | `build_restricted_gs_db` | The trimmed schema the models run against | 3,569 movies |
| 07 | `confusion_matrix` | Evaluation. Needs the models to have run |

Every step records its own output in `-- RESULT:` lines beside the query that
produced it.

## Three things that will bite you

**Step 03 carries 400 primary key violations.** Two raters submitted their whole
file twice. Step 01 builds the personal table without constraints and step 04
puts them back, so the duplication is measured rather than forced through. The
reasoning is in `docs/design_decisions.md`.

**Step 04 must run exactly once.** Run it twice and it moves the
already-filtered table into `_raw` and reports zero rows removed. That is a
false measurement rather than an error, so nothing stops it.

**Step 07 needs two edits, not the one the guide mentions.** The predictor side
points at the model output table. The class side stays on
`movies_recommendations_agg` to measure test, or switches to `gt_pairs_train`
to measure train.

Two of step 07's five queries do not run. One has unbalanced parentheses and
calls `IF` with two arguments. One aliases a column `precision`, a reserved
word in MySQL 8. Queries three and five are the working versions of the same
two metrics, so nothing is lost. Those two errors are expected.

## A naming trap

`movies_recommendations_agg` holds the 2026 data, not the aggregate of
`movies_recommendations`. The name says otherwise. It arrives already
aggregated and is used directly as the test ground truth.

## The data quality layer

Step 04 removes 400 duplicate rows from 7,445, leaving 7,045 across 35 raters
and 1,810 movies. All 400 were identical on all five columns, so collapsing
them loses no information.

Both tables are kept, raw and filtered, so model performance can be measured
with the layer on and off. Only Model 5 reads this table, and its measured
result is that precision is unchanged, because the model deduplicates on the
way in.
