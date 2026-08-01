-- ============================================================
-- Stage 2 - Ground truth validation
-- Runs only after build_gt_tables.sql. Both years side by side.
-- ============================================================


-- V1. Universe size
-- Distinct movies across both columns. Drives the size of the cartesian product later.
SELECT 'train' AS dataset, COUNT(*) AS universe_size
FROM (
    SELECT base_movie_id AS movie_id FROM gt_pairs_train
    UNION
    SELECT recommended_movie_id FROM gt_pairs_train
) AS u
UNION ALL
SELECT 'test' AS dataset, COUNT(*) AS universe_size
FROM (
    SELECT base_movie_id AS movie_id FROM movies_recommendations_agg
    UNION
    SELECT recommended_movie_id FROM movies_recommendations_agg
) AS u;
-- RESULT: train 2448 | test 1466


-- V2. Missing movies
-- Pairs pointing at a movie id that does not exist in the movies table.
SELECT 'train' AS dataset, COUNT(*) AS pairs_with_missing_movie
FROM gt_pairs_train AS gt
LEFT JOIN movies AS mb
    ON gt.base_movie_id = mb.id
LEFT JOIN movies AS mr
    ON gt.recommended_movie_id = mr.id
WHERE mb.id IS NULL
    OR mr.id IS NULL
UNION ALL
SELECT 'test' AS dataset, COUNT(*) AS pairs_with_missing_movie
FROM movies_recommendations_agg AS gt
LEFT JOIN movies AS mb
    ON gt.base_movie_id = mb.id
LEFT JOIN movies AS mr
    ON gt.recommended_movie_id = mr.id
WHERE mb.id IS NULL
    OR mr.id IS NULL;
-- RESULT: train 0 | test 0


-- V3. Score distribution
-- Decides where the good / not-good cutoff goes.
SELECT 'train' AS dataset, FLOOR(recommendation) AS score_bucket, COUNT(*) AS pairs
FROM gt_pairs_train
GROUP BY FLOOR(recommendation)
UNION ALL
SELECT 'test' AS dataset, FLOOR(recommendation) AS score_bucket, COUNT(*) AS pairs
FROM movies_recommendations_agg
GROUP BY FLOOR(recommendation)
ORDER BY dataset, score_bucket;
-- RESULT bucket:      1    2     3    4    5    6    7    8     9   10
--        train:     358  519  1129  393  204   45  419  825  1128  321
--        test:      308  544   719  384  490  202  326  883   638  216


-- V4. Positive rate - the baseline every model must beat
-- A model that calls every pair good scores exactly this precision at 100%
-- recall, while knowing nothing. Any model result is read against it.
-- SUM(x > 5) counts rows: a true comparison is 1 in MySQL, false is 0.
SELECT 'train' AS dataset,
    COUNT(*) AS total_pairs,
    SUM(recommendation > 5) AS positives,
    ROUND(100 * SUM(recommendation > 5) / COUNT(*), 1) AS positive_rate_pct
FROM gt_pairs_train
UNION ALL
SELECT 'test' AS dataset,
    COUNT(*) AS total_pairs,
    SUM(recommendation > 5) AS positives,
    ROUND(100 * SUM(recommendation > 5) / COUNT(*), 1) AS positive_rate_pct
FROM movies_recommendations_agg;
-- RESULT: train 5341 | 2739 | 51.3%
--         test  4710 | 2311 | 49.1%
