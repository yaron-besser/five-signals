-- ============================================================
-- personal_ranking_validation.sql
-- Data integrity checks on the loaded personal rankings. Read only, safe to
-- run at any time. Based on the lecturer's file in this folder, which drops
-- the table before checking.
--
-- Two tables are checked side by side: personal_movies_ranking_raw before the
-- data quality filter, and personal_movies_ranking after it. Results are
-- recorded under each query. Re-run to verify.
-- ============================================================

USE imdb_ijs;


-- 1. Constraint violations. The three defences built into the table: score in
-- range, rater present, justification at least 10 characters. Checked against
-- the raw table, since the clean one cannot hold violations.
SELECT
    SUM(recommendation IS NULL OR recommendation NOT BETWEEN 1 AND 10) AS bad_score,
    SUM(suggested_by IS NULL) AS missing_rater,
    SUM(justification IS NULL OR LENGTH(justification) < 10) AS short_justification,
    COUNT(*) AS rows_checked
FROM personal_movies_ranking_raw;
-- RESULT: 0 | 0 | 0 | 7445. Clean on all three. The only problem was the key.


-- 2. Primary key violations. The key is (movie_id, suggested_by), so a
-- violation is one rater scoring one movie twice.
--
-- The lecturer's file groups by movie_id alone. With 35 raters that flags
-- every movie more than one person rated, 932 of them, which is normal
-- content rather than a violation. The key is the pair.
SELECT
    'raw' AS dataset,
    COUNT(*) AS violating_keys
FROM (
    SELECT movie_id, suggested_by
    FROM personal_movies_ranking_raw
    GROUP BY movie_id, suggested_by
    HAVING COUNT(*) > 1
) AS v
UNION ALL
SELECT
    'clean',
    COUNT(*)
FROM (
    SELECT movie_id, suggested_by
    FROM personal_movies_ranking
    GROUP BY movie_id, suggested_by
    HAVING COUNT(*) > 1
) AS v;
-- RESULT: raw 400 | clean 0


-- 3. Who duplicated, and by how much.
SELECT
    suggested_by AS rater,
    COUNT(*) AS rows_submitted,
    COUNT(DISTINCT movie_id) AS distinct_movies,
    COUNT(*) - COUNT(DISTINCT movie_id) AS duplicate_rows
FROM personal_movies_ranking_raw
GROUP BY suggested_by
HAVING duplicate_rows > 0
ORDER BY duplicate_rows DESC;
-- RESULT: two raters, 400 rows each against 200 distinct movies.


-- 4. Are the duplicates identical, or do they disagree? If a rater scored the
-- same movie twice with different values, DISTINCT would keep both and the
-- filter would not work. This proves it is safe.
SELECT
    COUNT(*) AS keys_with_conflicting_values
FROM (
    SELECT movie_id, suggested_by
    FROM personal_movies_ranking_raw
    GROUP BY movie_id, suggested_by
    HAVING COUNT(DISTINCT CONCAT_WS('|',
               recommendation, justification, IFNULL(comment, ''))) > 1
) AS c;
-- RESULT: 0. Every duplicate is identical on all columns, so collapsing them
--         loses nothing.


-- 5. Rankings per rater. The course asked for 200 each.
SELECT
    suggested_by AS rater,
    COUNT(*) AS rankings
FROM personal_movies_ranking
GROUP BY suggested_by
HAVING rankings != 200
ORDER BY rankings;
-- RESULT: 9 of 35 raters are off 200, spanning 199 to 225. Only one is below
--         it, by a single row. The deviation is almost all upward, so nobody
--         submitted partially. Not filtered.


-- 6. Referential integrity. The foreign key should make this impossible, but
-- the raw table has no foreign key, so it is worth checking there.
SELECT
    COUNT(*) AS rankings_with_missing_movie
FROM personal_movies_ranking_raw AS p
LEFT JOIN movies AS m
    ON p.movie_id = m.id
WHERE m.id IS NULL;
-- RESULT: 0


-- 7. Summary.
SELECT
    (SELECT COUNT(*) FROM personal_movies_ranking_raw) AS rows_loaded,
    (SELECT COUNT(*) FROM personal_movies_ranking) AS rows_after_filter,
    (SELECT COUNT(DISTINCT suggested_by) FROM personal_movies_ranking) AS raters,
    (SELECT COUNT(DISTINCT movie_id) FROM personal_movies_ranking) AS distinct_movies;
-- RESULT: 7445 | 7045 | 35 | 1810
