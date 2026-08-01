USE imdb_ijs;

-- ============================================================
-- Model 5: Collaborative Filtering
--
-- Two movies are similar if the same people liked both. The only model that
-- reads taste rather than metadata.
--
-- LEAKAGE: built only on personal_movies_ranking, never on
-- movies_recommendations. That table is the ground truth, and a collaborative
-- model built on it would be trained on the answers.
--
-- Item-item Jaccard with raters as the shared context. Two parameters, because
-- jaccard alone is naive at low support: one rater who liked exactly two
-- movies, both of them this pair, scores 1.0. Hence a support floor.
--
-- "Liked" is recommendation > 5, the same cutoff the confusion matrix uses.
-- See README.md.
-- ============================================================

-- Materialisation floor. 1 is the loosest possible, and includes the noise on
-- purpose so the tuning grid can show what excluding it buys.
SET @MIN_CO_RATERS = 1;

-- DISTINCT is defensive. It matters when this query is pointed at
-- personal_movies_ranking_raw for the data quality comparison.
DROP TABLE IF EXISTS model_5_liked;

CREATE TABLE model_5_liked AS
SELECT DISTINCT p.movie_id AS movie_id,
       p.suggested_by AS suggested_by
FROM personal_movies_ranking AS p
WHERE p.recommendation > 5;

ALTER TABLE model_5_liked
ADD PRIMARY KEY (movie_id, suggested_by);

ALTER TABLE model_5_liked
ADD KEY idx_model_5_liked_rater (suggested_by);

-- Denominator side of the jaccard: how many raters liked each movie.
DROP TABLE IF EXISTS model_5_likers;

CREATE TABLE model_5_likers AS
SELECT l.movie_id AS movie_id,
       COUNT(DISTINCT l.suggested_by) AS likers
FROM model_5_liked AS l
GROUP BY l.movie_id;

ALTER TABLE model_5_likers
ADD PRIMARY KEY (movie_id);

SELECT COUNT(DISTINCT suggested_by) AS raters,
       COUNT(DISTINCT movie_id) AS liked_movies,
       COUNT(*) AS liked_rows
FROM model_5_liked;
-- RESULT: 35 raters, 1,424 liked movies, 5,509 liked rows. The other 386 of
--         the 1,810 ranked movies were scored 5 or below by everyone.

-- Co-liked counts. movie_id_1 < movie_id_2 keeps each pair once.
DROP TABLE IF EXISTS model_5_pairs;

CREATE TABLE model_5_pairs AS
SELECT l1.movie_id AS movie_id_1,
       l2.movie_id AS movie_id_2,
       COUNT(DISTINCT l1.suggested_by) AS co_raters
FROM model_5_liked AS l1
JOIN model_5_liked AS l2
    ON l1.suggested_by = l2.suggested_by
    AND l1.movie_id < l2.movie_id
GROUP BY l1.movie_id, l2.movie_id
HAVING COUNT(DISTINCT l1.suggested_by) >= @MIN_CO_RATERS;

ALTER TABLE model_5_pairs
ADD PRIMARY KEY (movie_id_1, movie_id_2);

-- The denominator cannot be zero: a pair only reaches this table if some rater
-- liked both, so the union is at least 1.
DROP TABLE IF EXISTS model_5_scored;

CREATE TABLE model_5_scored AS
SELECT p.movie_id_1 AS movie_id_1,
       p.movie_id_2 AS movie_id_2,
       p.co_raters AS co_raters,
       p.co_raters / (k1.likers + k2.likers - p.co_raters) AS jaccard
FROM model_5_pairs AS p
JOIN model_5_likers AS k1 ON k1.movie_id = p.movie_id_1
JOIN model_5_likers AS k2 ON k2.movie_id = p.movie_id_2;

ALTER TABLE model_5_scored
ADD PRIMARY KEY (movie_id_1, movie_id_2);

-- Both directions, because the ground truth is directed.
DROP TABLE IF EXISTS model_5_candidates;

CREATE TABLE model_5_candidates AS
SELECT movie_id_1, movie_id_2, co_raters, jaccard FROM model_5_scored
UNION ALL
SELECT movie_id_2, movie_id_1, co_raters, jaccard FROM model_5_scored;

ALTER TABLE model_5_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2);

ALTER TABLE model_5_candidates
ADD KEY idx_model_5_candidates_signal (co_raters, jaccard);

SELECT COUNT(*) AS candidate_pairs,
       COUNT(DISTINCT movie_id_1) AS base_movies,
       MAX(co_raters) AS max_co_raters,
       MIN(jaccard) AS min_jaccard
FROM model_5_candidates;
-- RESULT: 427,056 pairs, 1,424 base movies, co_raters 1 to 26,
--         jaccard 0.0313 to 1.0000.

-- Support distribution. This is what justifies the support floor.
SELECT co_raters AS co_raters,
       COUNT(*) AS pairs,
       AVG(jaccard) AS avg_jaccard
FROM model_5_candidates
GROUP BY co_raters
ORDER BY co_raters;
-- RESULT: 63.4% of volume sits at co_raters = 1 (270,758 of 427,056) and that
--         band reaches jaccard 1.0. avg_jaccard FALLS from 0.2918 at one rater
--         to 0.2307 at three before climbing to 0.3546 at 4+, because a tiny
--         union inflates the ratio.

-- Coverage against the ground truth. Context for the recall figure.
SELECT COUNT(*) AS train_pairs,
       SUM(gt.base_movie_id IN (SELECT movie_id FROM model_5_likers)
           AND gt.recommended_movie_id IN (SELECT movie_id FROM model_5_likers)) AS both_known
FROM gt_pairs_train AS gt;
-- RESULT: 5,341 train pairs, 1,704 reachable (31.9%). Of those 1,384 are good
--         (81.2%) against 51.3% for train overall, so the recall ceiling is
--         1,384/2,739 = 50.5%, not 31.9%.

-- FINAL QUERY. The floor of 2 is the largest step in the grid, +2.9 points,
-- and it removes the single-rater artefact. Floors 3 to 5 do not improve on it
-- and are not even monotone. Precision rises with the jaccard cutoff all the
-- way to 0.50 with no elbow, so the precision-first rule decides it.
-- co_raters is the support floor, not part of the output. See README.md.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       jaccard AS jaccard  -- raw signal, normalised at aggregation
FROM model_5_candidates
WHERE co_raters >= 2
    AND jaccard >= 0.50;
-- RESULT: 20,888 pairs.

-- Measurement view for ../evaluate_model.sql. The fixed 9 exists only so the
-- confusion matrix has a value above 5 to read. Baselines 51.3% and 49.1%.
DROP VIEW IF EXISTS eval_predictor;

CREATE VIEW eval_predictor AS
SELECT movie_id_1 AS base_movie_id,
       movie_id_2 AS recommended_movie_id,
       9 AS recommendation
FROM model_5_candidates
WHERE co_raters >= 2
    AND jaccard >= 0.50;
-- RESULT: train precision 90.9% on 353 rated pairs, recall 11.7%
--         test  precision 76.8% on 909 rated pairs, recall 30.2%
