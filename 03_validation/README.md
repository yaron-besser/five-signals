# 03_validation

Checks on the raw data before it reaches any model.

| File | What it checks |
|---|---|
| `raw_data_validation.sql` | The IMDB source tables and the trimmed schema |
| `personal_ranking_validation.sql` | The personal rankings: keys, ranges, per rater counts |
| `personal_ranking_validation_lecturer.sql` | Reference copy of the course file. **Do not run** |

The lecturer's file is kept for reference only. Line 7 drops the table.

## What the personal rankings look like

7,045 rows after the step 04 filter, across 35 raters and 1,810 movies, scores
1 to 10, no nulls.

26 raters submitted exactly 200 rankings. Nine submitted a different number,
between 199 and 225, and almost all deviation is upward. Only one rater came in
below 200.

| Rankings submitted | Raters |
|---|---|
| 199 | 1 |
| 200 | 26 |
| 201 | 2 |
| 202 | 2 |
| 203 | 2 |
| 209 | 1 |
| 225 | 1 |

Grouped by count rather than listed by rater, because the shape is the point.
The names are in `01_pipeline/03_load_personal_rankings.sql`.

Nobody was filtered for this. The data is valid, just not uniform in size.
Worth remembering when reading Model 5: a rater with more movies takes part in
more comparisons.

## One check that needs care

The course file groups its duplicate check by `movie_id` alone. With 35 raters
that flags every movie more than one person rated, 932 of them here, which is
normal content rather than a violation.

The real check is the full primary key, `(movie_id, suggested_by)`. That gives
400 violations in the raw table and zero in the filtered one.
