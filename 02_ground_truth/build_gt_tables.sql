-- ============================================================
-- Stage 2 - Ground truth for train and test
-- In:  movies_recommendations (2025), movies_recommendations_agg (2026)
-- Out: gt_pairs_train, and a primary key on movies_recommendations_agg
--
-- Only one table is built, because the two years arrive in different shapes.
-- 2025 is raw, one row per rater, so the same pair appears several times with
-- conflicting scores: 5,549 rows over 5,348 distinct pairs. Uncollapsed, a
-- pair scored 9 by one rater and 1 by another lands on both sides of the
-- positive threshold and the confusion matrix is wrong. 2026 arrives already
-- aggregated with nothing to fix, so it is used directly.
--
-- gt_pairs_train is a structural clone of movies_recommendations_agg, same six
-- columns under the same names, so the course confusion matrix runs against
-- either table with only its table name swapped.
-- ============================================================


-- 2025 -> train. Collapses the per-rater rows into one row per pair. The
-- aggregation expressions are copied from the course build_gs.txt, so this
-- reproduces the supplied movies_recommendations_agg_2025.sql.
DROP TABLE IF EXISTS gt_pairs_train;
CREATE TABLE gt_pairs_train AS
SELECT
    base_movie_id,
    recommended_movie_id,
    AVG(recommendation) AS recommendation,   -- an average, named as the course names it
    STDDEV(recommendation) AS recommendation_std,
    COUNT(DISTINCT suggested_by) AS suggested_by_num,
    COUNT(DISTINCT justification) AS justifications_num
FROM movies_recommendations
WHERE base_movie_id != recommended_movie_id   -- drop the 7 self-pairs
GROUP BY base_movie_id, recommended_movie_id;

-- CREATE TABLE AS SELECT inherits no keys. The confusion matrix joins on
-- exactly these two columns, so without an index every run is a full scan.
ALTER TABLE gt_pairs_train
ADD PRIMARY KEY (base_movie_id, recommended_movie_id);


-- 2026 -> test. Verified as 4,710 rows over 4,710 distinct pairs with zero
-- self-pairs, so it only lacks a key, for the same join reason as above.
ALTER TABLE movies_recommendations_agg
ADD PRIMARY KEY (base_movie_id, recommended_movie_id);


-- Final check. This is the last file in the sequence, so it counts every
-- table the pipeline builds. Any mismatch means a step was skipped or run
-- out of order.
SELECT 'movies_recommendations' AS table_name, COUNT(*) AS row_count, 5549 AS expected
FROM movies_recommendations
UNION ALL
SELECT 'personal_movies_ranking_raw', COUNT(*), 7445
FROM personal_movies_ranking_raw
UNION ALL
SELECT 'personal_movies_ranking', COUNT(*), 7045
FROM personal_movies_ranking
UNION ALL
SELECT 'gs_movies', COUNT(*), 3569
FROM gs_movies
UNION ALL
SELECT 'gt_pairs_train (2025)', COUNT(*), 5341
FROM gt_pairs_train
UNION ALL
SELECT 'movies_recommendations_agg (2026 test)', COUNT(*), 4710
FROM movies_recommendations_agg;
