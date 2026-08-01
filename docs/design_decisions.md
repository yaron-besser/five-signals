# Design decisions

The choices that were not obvious, and why. Every number comes from a query
that can be re-run, and the query sits next to it. Every course file not named
below is untouched.

---

## 1. Removed the seed INSERT from `build_gs`

**File:** `01_pipeline/01_build_gs.sql`, adapted from the course `build_gs.txt`

Removed: the `INSERT` loading 924 seed pairs from one rater, and two diagnostic
`SELECT` statements that build nothing. Kept byte for byte: both `CREATE TABLE`
statements, the primary key, both foreign keys to `movies(Id)`, the CHECK on
the 1-10 range, and the `movies_recommendations_agg` aggregation.

**Why.** The same 924 rows appear again in the 2025 class file at step 02.
Loading both means loading them twice, and the primary key correctly rejects
the second load with 924 duplicate-key errors. Getting past them requires
`mysql --force`, which also hides any unexpected error behind the expected
ones. A pipeline that runs start to finish with zero errors is a better
artifact.

**Downstream.** Nothing. The 924 rows still enter at step 02. Verified: 5,549
rows and 24 raters after step 02, matching the 2025 file exactly.

---

## 2. Staged the personal rankings instead of loading them directly

**Files:** the staging table in `01_build_gs.sql`, and `04_apply_data_quality.sql`.
The course file `03_load_personal_rankings.sql` is unmodified.

Step 01 creates `personal_movies_ranking` unconstrained, so step 03 loads with
zero rejections. Step 04 renames it to `personal_movies_ranking_raw`, rebuilds
it with the constraints exactly as the course file defines them, and moves the
data across with `SELECT DISTINCT`.

**Why.** The class file holds 400 rows violating the primary key
`(movie_id, suggested_by)`: two students submitted their 200 rankings twice.
A direct load needs `--force` again. Staging turns the duplication from a log
of failures into a measured quantity we can report. Verified in advance that
all 400 duplicates are identical on all five columns, so `DISTINCT` discards
nothing.

**This is the lecturer's own procedure.** Found afterwards in
`personal_movies_ranking_validation.sql` in the course repo: create without
protection, insert, identify violations, fix, recreate with protection, verify.
Step 04 implements exactly that. His file is kept unmodified at
`03_validation/personal_ranking_validation_lecturer.sql`, marked DO NOT RUN
because its line 7 drops the table.

One difference, and our validation file runs both checks side by side. His
version groups duplicates on `movie_id` alone, which with 35 raters flags every
movie more than one person rated, 932 of them. That is normal content. The
violation is defined by the full primary key: 400 in the raw table, zero in the
clean one.

**Downstream.** Final content is what a direct load would have produced: 7,045
rows, 35 raters, 1,810 movies. Keeping the raw table is what makes the with and
without comparison possible.

---

## 3. Our own aggregated ground truth, with self-pairs removed

**File:** `02_ground_truth/build_gt_tables.sql`. No course file modified.

`gt_pairs_train` is built from the 2025 data as a structural clone of
`movies_recommendations_agg`: same six columns, same names, aggregation
expressions copied from `build_gs.txt`. A primary key on
`(base_movie_id, recommended_movie_id)` was added, which
`CREATE TABLE ... AS SELECT` does not inherit. `movies_recommendations_agg` is
used directly as the 2026 test set, because it arrives already aggregated.

Dropped: pairs where a movie is recommended to itself. 7 in 2025, none in 2026.

**Why.** The split is required by `Project_2026.pdf`. Self-pairs carry no
information and every symmetric model matches them trivially, so they inflate
precision on rows that mean nothing. The primary key matters because the
confusion matrix joins on exactly those two columns.

**Verified against the lecturer's own file.** The course repo supplies its own
2025 aggregation. Counted directly:

    grep -c "^INSERT" movies_recommendations_agg_2025.sql   -- 5348
    ... | awk -F'[(,]' '$2==$3' | wc -l                     -- 7 self-pairs

5,348 - 7 = 5,341, which is our row count. Two expressions were changed to
match his wording. Neither moves a number, checked across all 5,348 pairs:

    SELECT COUNT(*) AS pairs,
           SUM(c_all != c_dist) AS count_mismatches,
           SUM(ABS(s_pop - s_plain) > 0.000001) AS stddev_mismatches
    FROM ( SELECT base_movie_id, recommended_movie_id,
                  COUNT(*) AS c_all,
                  COUNT(DISTINCT suggested_by) AS c_dist,
                  STDDEV_POP(recommendation) AS s_pop,
                  STDDEV(recommendation) AS s_plain
           FROM movies_recommendations
           GROUP BY base_movie_id, recommended_movie_id ) AS t;
    -- RESULT: 5348 | 0 | 0

Column names were kept, so the course confusion matrix runs with only its table
names swapped.

---

## 4. The pipeline collapsed from nine files to seven

**File:** `01_build_gs.sql` extended. Two steps deleted.

**Conditional guards removed.** Two steps carried `SET @guard` / `PREPARE` /
`EXECUTE` / `DEALLOCATE` blocks that aborted the script by referencing a
missing table, using the table name as the error message. That is dynamic SQL,
not material from this course. Replaced by a comment stating the file runs
forward only.

**Two steps folded into step 01.** One created `personal_movies_ranking` with
full constraints; the next dropped it and created an unconstrained one of the
same name. The staging definition now sits in step 01 with the other empty
tables, and the sequence runs 01 to 07 with no gaps.

**Step 01 opens with a full reset**, dropping all 13 built tables. The reset
used to live in a notes file, as documentation rather than code, and listed
only 4 of the 13. That gap was hit in practice: a reset leaving the `gs_` and
`gt_` tables standing was believed to be a clean slate. The row count check at
the end of `build_gt_tables.sql` was widened from two tables to all seven, each
printed next to its expected value.

**Why `build_collaborative_gs.txt` was never a pipeline step.** It is a
worksheet: a table definition, a helper that generates candidate INSERTs, and
two recommendation queries. Only the table definition belongs in a build
sequence. Treating the whole file as a step meant a spent helper ran on every
build, and Model 5 sat hidden inside a file named `create_personal_table`.

Worth noting: the third query in that file joins personal taste against
`movies_recommendations_agg`, the ground truth. Used as a model it would be
trained on the table it is measured against. It illustrates leakage, not a
model.

**Downstream.** Nothing. No table definition, threshold or row count changed.
Every definition is byte for byte, and the class data files at steps 02, 03
and 05 are untouched.
