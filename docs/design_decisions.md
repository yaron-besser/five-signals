# Design decisions

The brief leaves the implementation open. What is required is a recommendation
system whose data loads cleanly, five models, and an honest evaluation. How the
pipeline gets there is ours to choose.

This document records the choices that were not obvious, and the reasoning
behind each. Nothing here is a departure from a rule - there is no rule to
depart from. Where a choice gives a course file a different shape, that is
recorded as context, not as an apology.

Every number below comes from a query that can be re-run, and the query sits
next to it.

**Every course file not named in a decision below is untouched.** Where a named
file was adapted, what stayed identical is listed with the decision.

---

## Decision 1 - removed the seed INSERT from `build_gs`

**File:** `01_pipeline/01_build_gs.sql`, adapted from the course `build_gs.txt`

Two things were removed: the `INSERT` block loading 924 seed pairs from a
single rater, and two diagnostic `SELECT` statements that print result grids
and build nothing. Both `CREATE TABLE` statements were kept byte-for-byte,
along with their primary key, both foreign keys to `movies(Id)`, the CHECK on
the 1-10 range, and the `movies_recommendations_agg` aggregation query.

### Why

The same 924 rows also appear inside the 2025 class file, which loads at
step 02. We verified this directly: the 2025 file contains exactly 924 rows
from that rater, matching the seed count.

Running both files therefore loads the same rows twice. The primary key
`(base_movie_id, recommended_movie_id, suggested_by)` correctly rejects the
second load, producing 924 duplicate-key errors. To get past them the whole
pipeline has to run with error suppression:

    mysql --force imdb_ijs < 02_load_2025_train.sql

That is a poor property for a deliverable. A pipeline a third party can run
start to finish with zero errors, in MySQL Workbench, is a better artifact than
one that depends on suppressing known failures. Suppression also hides any
*unexpected* error behind the 924 expected ones.

### What it changes downstream

Nothing. The 924 rows still enter `movies_recommendations` at step 02, so the
ground truth content is identical either way. What disappears is the redundant
second load, not the data. Verified by counting: 5,549 rows and 24 raters after
step 02, matching the row count of the 2025 file exactly.

---

## Decision 2 - staged the personal rankings instead of loading them directly

**Files:** the staging table in `01_build_gs.sql`, and
`01_pipeline/04_apply_data_quality.sql`. The course file
`03_load_personal_rankings.sql` is unmodified, byte for byte.

Step 01 creates `personal_movies_ranking` without constraints, so the class
file at step 03 loads with zero rejections. Step 04 renames it to
`personal_movies_ranking_raw`, rebuilds `personal_movies_ranking` with the
constraints exactly as the course file defines them, and moves the data across
with `SELECT DISTINCT`. Same primary key, same foreign key to `movies(id)`,
same CHECK on the 1-10 range, same CHECK on justification length.

### Why

The class file contains 400 rows that violate the primary key
`(movie_id, suggested_by)`. Two students submitted their 200 rankings twice.
Loading it straight into the constrained table produces 400 duplicate-key
errors and again forces the pipeline to run with `--force`.

Staging turns the duplication from a log of failures into a measured quantity.
We can state how many rows the layer removed, which raters caused it, and what
the effect on model performance is. A suppressed error log gives none of that.

We verified in advance that all 400 duplicate keys are identical on all five
columns, including justification and comment, so `DISTINCT` discards nothing.

### This is the lecturer's own procedure

Found after the fact, in `personal_movies_ranking_validation.sql` in the course
repo. Its header instructs the reader to create the table without protection,
insert the data, identify the violations, fix them, then recreate the table
with the original protection and verify. Step 04 implements exactly that, so
this is not a departure from the course files but an implementation of a
procedure the course materials describe.

That file is kept unmodified at
`03_validation/personal_ranking_validation_lecturer.sql` as evidence. It is
marked DO NOT RUN, because its line 7 drops the table.

One difference is worth stating, and our validation file runs both checks side
by side. His version groups duplicates on `movie_id` alone, which with 35
raters flags every movie more than one person rated, 932 of them. That is the
normal content of the table. The violation is defined by the full primary key.
On that check the raw table has 400 and the clean table has zero.

### What it changes downstream

The final content of `personal_movies_ranking` is exactly what a direct load
would have produced: 7,045 rows, 35 raters, 1,810 distinct movies. The
difference is that the 400 removed rows are a number we can report instead of
an error count. Keeping `personal_movies_ranking_raw` also makes the with and
without comparison possible, which the project requires.

---

## Decision 3 - our own aggregated ground truth, with self-pairs removed

**File:** `02_ground_truth/build_gt_tables.sql`. No course file was modified.

`gt_pairs_train` is built from the 2025 data. `movies_recommendations_agg` is
used directly as the 2026 test ground truth, because it arrives already
aggregated.

`gt_pairs_train` is a structural clone of `movies_recommendations_agg`, the
same six columns under the same names, with the aggregation expressions copied
from the course `build_gs.txt`. A primary key on
`(base_movie_id, recommended_movie_id)` was added, which
`CREATE TABLE ... AS SELECT` does not inherit.

One class of row was dropped: pairs where a movie is recommended to itself.
There are 7 in the 2025 data and none in 2026.

### Why

The split is required by `Project_2026.pdf`. Models are built on the prior year
and measured on the current one, so the two sets have to exist separately.

Self-pairs are not recommendations. "If you liked A, watch A" carries no
information, and every symmetric model matches such a pair trivially, so
leaving them in inflates precision on rows that mean nothing.

The primary key matters because the confusion matrix joins on exactly those two
columns. Without an index, every evaluation run is a full scan.

### What it changes downstream

`gt_pairs_train` holds 5,341 pairs and the 2026 table 4,710, from the row count
check at the end of `build_gt_tables.sql`.

The course repo supplies its own aggregation of 2025 at
`recommendations_goldstandard/recommendations/movies_recommendations_agg_2025.sql`.
Counted directly:

    grep -c "^INSERT" movies_recommendations_agg_2025.sql          -- 5348
    grep -oE "VALUES \(([0-9]+),([0-9]+)," ... | awk -F'[(,]' '$2==$3' | wc -l   -- 7

5,348 - 7 = 5,341. Our table reproduces the lecturer's output exactly, minus
the self-pairs, so the aggregation logic is verified against his own file
rather than merely asserted.

Two expressions were changed to match his wording exactly. Neither moves a
number, verified across all 5,348 pairs:

    SELECT COUNT(*) AS pairs,
           SUM(c_all <> c_dist) AS count_mismatches,
           SUM(ABS(s_pop - s_plain) > 0.000001) AS stddev_mismatches
    FROM ( SELECT base_movie_id, recommended_movie_id,
                  COUNT(*) AS c_all,
                  COUNT(DISTINCT suggested_by) AS c_dist,
                  STDDEV_POP(recommendation) AS s_pop,
                  STDDEV(recommendation) AS s_plain
           FROM movies_recommendations
           GROUP BY base_movie_id, recommended_movie_id ) AS t;
    -- RESULT: 5348 | 0 | 0

The column names were kept, so the course confusion matrix runs with only its
table names swapped and no edit to its body.

---

## Decision 4 - the pipeline collapsed from nine files to seven

**File:** `01_build_gs.sql` extended. Two steps were deleted.

Three changes, all in service of one goal: running the pipeline in order is a
from-scratch build, with nothing to remember and nothing to paste.

**The conditional guards are gone.** Two steps each carried a block of
`SET @guard`, `PREPARE`, `EXECUTE`, `DEALLOCATE` that aborted the script by
referencing a table that does not exist, using the table name as the error
message. It worked, but it is dynamic SQL: not material from this course, and
not something we could defend in a review. Both blocks were replaced by a
comment stating the file runs forward only.

**Two steps were folded into step 01.** One created `personal_movies_ranking`
with its full constraints; the next immediately dropped that table and created
an unconstrained one of the same name. Build, demolish, rebuild. The staging
definition now sits in step 01 alongside the other two empty tables, so the
whole target schema is defined in one file. The sequence was then renumbered to
run 01 to 07 with no gaps.

**Step 01 opens with a full reset.** It drops all 13 built tables before
building anything. The reset used to live as a text block in a notes file,
which meant it was documentation rather than code, and it listed only 4 of the
13 tables. That gap was hit in practice: a reset that left the `gs_` and `gt_`
tables standing was believed to be a clean slate.

The final row count check at the end of `02_ground_truth/build_gt_tables.sql`
was widened from two tables to all seven, each printed next to its expected
value.

### Why

The course file `build_collaborative_gs.txt` was never a pipeline step. It is a
worksheet: a table definition, a helper that generates candidate INSERT
statements, and two recommendation queries. Only the table definition belongs
in a build sequence. Treating the whole file as a step meant a spent helper ran
on every build, and Model 5 sat hidden inside a file named
`create_personal_table`.

### What it changes downstream

Nothing. No table definition changed, no threshold changed, no row count
changed. This is structure only. Every table definition is byte-for-byte, the
constrained `personal_movies_ranking` is applied exactly as the course file
defines it, and the class data files at steps 02, 03 and 05 are untouched.

Nothing from `build_collaborative_gs.txt` is kept in this project. It remains
in the course repo at
`recommendations_goldstandard/collaborative_filtering/build_collaborative_gs.txt`
if it is ever needed again.

Worth noting for the report: the third query in that file joins personal taste
against `movies_recommendations_agg`, which is the ground truth. Used as a
model it would be trained on the table it is measured against. It is an
illustration of leakage, not a model.
