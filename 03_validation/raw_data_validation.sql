-- ============================================================
-- Stage 1 - Data Validation
-- ============================================================


-- PART A - 2025 (train) - raw file, one row per rater

-- A1. Load integrity
-- distinct_rater_pairs below raw_rows would mean a rater rated the same pair twice.
SELECT
    COUNT(*) AS raw_rows,
    COUNT(DISTINCT suggested_by) AS raters,
    COUNT(DISTINCT CONCAT(base_movie_id, '-', recommended_movie_id)) AS distinct_pairs,
    COUNT(DISTINCT CONCAT(base_movie_id, '-', recommended_movie_id, '-', suggested_by)) AS distinct_rater_pairs,
    SUM(CASE WHEN recommendation IS NULL THEN 1 ELSE 0 END) AS null_scores,
    SUM(CASE WHEN base_movie_id = recommended_movie_id THEN 1 ELSE 0 END) AS self_pair_rows,
    COUNT(DISTINCT CASE WHEN base_movie_id = recommended_movie_id
                        THEN base_movie_id END) AS distinct_self_pairs,
    SUM(CASE WHEN recommendation NOT BETWEEN 1 AND 10 THEN 1 ELSE 0 END) AS out_of_range
FROM movies_recommendations;
-- RESULT: 5549 | 24 | 5348 | 5549 | 0 | 7 | 7 | 0

-- A2. Direction check
-- Pairs submitted in both directions. COUNT(DISTINCT) cancels the multi-rater inflation.
SELECT COUNT(DISTINCT CONCAT(a.base_movie_id, '-', a.recommended_movie_id)) AS reversed_duplicates
FROM movies_recommendations AS a
JOIN movies_recommendations AS b
    ON a.base_movie_id = b.recommended_movie_id
    AND a.recommended_movie_id = b.base_movie_id
WHERE a.base_movie_id < b.base_movie_id;
-- RESULT: 1177


-- PART B - 2026 (test) - pre-aggregated file, one row per pair

-- B1. Load integrity
-- raw_rows must equal distinct_pairs, otherwise the file is not truly aggregated.
SELECT
    COUNT(*) AS raw_rows,
    COUNT(DISTINCT CONCAT(base_movie_id, '-', recommended_movie_id)) AS distinct_pairs,
    SUM(suggested_by_num) AS total_ratings,
    SUM(CASE WHEN recommendation IS NULL THEN 1 ELSE 0 END) AS null_scores,
    SUM(CASE WHEN base_movie_id = recommended_movie_id THEN 1 ELSE 0 END) AS self_pairs,
    SUM(CASE WHEN recommendation NOT BETWEEN 1 AND 10 THEN 1 ELSE 0 END) AS out_of_range
FROM movies_recommendations_agg;
-- RESULT: 4710 | 4710 | 6217 | 0 | 0 | 0

-- B2. Direction check
SELECT COUNT(*) AS reversed_duplicates
FROM movies_recommendations_agg AS a
JOIN movies_recommendations_agg AS b
    ON a.base_movie_id = b.recommended_movie_id
    AND a.recommended_movie_id = b.base_movie_id
WHERE a.base_movie_id < b.base_movie_id;
-- RESULT: 617
