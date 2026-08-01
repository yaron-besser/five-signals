USE imdb_ijs;

-- ============================================================
-- Model 1: Style & Era
--
-- Two movies are similar if they share genres and came out close together.
-- Neither half works alone: every drama shares a genre with every other
-- drama, and two films from the same year need have nothing in common.
--
-- Two parameters, so tuning is a grid. This file materialises the widest
-- window once and keeps both components as columns, so tune_model_1.py can
-- sweep the grid without re-running the heavy join. See README.md.
-- ============================================================

-- Materialisation ceiling, not the model's answer. Deliberately loose so the
-- grid can look at windows on both sides of any sensible value.
SET @MAX_YEAR_GAP = 20;

-- Speed only. gs_movies_genres has no index on genre, which the pair join
-- drives off. Guarded because MySQL has no CREATE INDEX IF NOT EXISTS.
SET @index_exists = (
    SELECT COUNT(*)
    FROM information_schema.STATISTICS
    WHERE table_schema = 'imdb_ijs'
        AND table_name = 'gs_movies_genres'
        AND index_name = 'idx_gs_movies_genres_genre'
);

SET @create_index = IF(@index_exists = 0,
    'CREATE INDEX idx_gs_movies_genres_genre ON gs_movies_genres (genre)',
    'DO 0');

PREPARE stmt FROM @create_index;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- One row per unordered pair. movie_id_1 < movie_id_2 stops self-pairing and
-- halves the group count on the most expensive join in the project.
-- year_gap is constant inside a group, so MIN() satisfies ONLY_FULL_GROUP_BY.
DROP TABLE IF EXISTS model_1_pairs;

CREATE TABLE model_1_pairs AS
SELECT g1.movie_id AS movie_id_1,
       g2.movie_id AS movie_id_2,
       COUNT(DISTINCT g1.genre) AS shared_genres,
       MIN(ABS(m1.year - m2.year)) AS year_gap
FROM gs_movies_genres AS g1
JOIN gs_movies_genres AS g2
    ON g1.genre = g2.genre
    AND g1.movie_id < g2.movie_id
JOIN gs_movies AS m1 ON m1.id = g1.movie_id
JOIN gs_movies AS m2 ON m2.id = g2.movie_id
WHERE m1.year IS NOT NULL  -- dead code here: zero NULL years. Kept as a guard.
    AND m2.year IS NOT NULL
    AND ABS(m1.year - m2.year) <= @MAX_YEAR_GAP
GROUP BY g1.movie_id, g2.movie_id;

ALTER TABLE model_1_pairs
ADD PRIMARY KEY (movie_id_1, movie_id_2);

ALTER TABLE model_1_pairs
ADD KEY idx_model_1_signal (year_gap, shared_genres);

-- Both directions, because the ground truth is directed and this model is
-- symmetric. Where the class scored the two directions onto opposite sides of
-- the cutoff, a symmetric model must get one of them wrong.
DROP TABLE IF EXISTS model_1_candidates;

CREATE TABLE model_1_candidates AS
SELECT movie_id_1, movie_id_2, shared_genres, year_gap FROM model_1_pairs
UNION ALL
SELECT movie_id_2, movie_id_1, shared_genres, year_gap FROM model_1_pairs;

ALTER TABLE model_1_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2);

ALTER TABLE model_1_candidates
ADD KEY idx_model_1_candidates_signal (year_gap, shared_genres);

SELECT COUNT(*) AS candidate_pairs,
       COUNT(DISTINCT movie_id_1) AS base_movies,
       MAX(shared_genres) AS max_shared_genres
FROM model_1_candidates;
-- RESULT: 1,924,104 pairs, 3,178 base movies, shared_genres 1 to 10.
--         Exactly 2x model_1_pairs (962,052), so the mirror lost nothing.
--         3,178 is every film with a genre row. The other 391 in gs_movies
--         have no genre at all, so 89.0% coverage is this model's ceiling.

-- Where the candidate volume actually sits across the grid.
SELECT shared_genres AS shared_genres,
       SUM(year_gap <= 2) AS gap_le_2,
       SUM(year_gap <= 5) AS gap_le_5,
       SUM(year_gap <= 10) AS gap_le_10,
       SUM(year_gap <= 20) AS gap_le_20
FROM model_1_candidates
GROUP BY shared_genres
ORDER BY shared_genres;
-- RESULT: volume collapses above 4 shared genres: 462 pairs at 5, 36 at 6.

-- FINAL QUERY. shared_genres >= 3 is a real 5.1 point gain over 2, and 4 is
-- worse on 58 rated pairs. The year window is inert: precision is flat across
-- all five windows tested, so <= 20 is the loosest measured rather than a
-- meaningful era bound. See README.md.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       shared_genres AS shared_genres  -- raw signal, normalised at aggregation
FROM model_1_candidates
WHERE shared_genres >= 3
    AND year_gap <= 20;
-- RESULT: 46,318 pairs across 1,000 base movies.

-- Measurement view for ../evaluate_model.sql. The fixed 9 exists only so the
-- confusion matrix has a value above 5 to read. Baselines 51.3% and 49.1%.
DROP VIEW IF EXISTS eval_predictor;

CREATE VIEW eval_predictor AS
SELECT movie_id_1 AS base_movie_id,
       movie_id_2 AS recommended_movie_id,
       9 AS recommendation
FROM model_1_candidates
WHERE shared_genres >= 3
    AND year_gap <= 20;
-- RESULT: train precision 81.8% on 231 rated pairs, recall 6.9%
--         test  precision 59.8% on 619 rated pairs, recall 16.0%
