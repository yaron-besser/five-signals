USE imdb_ijs;

-- ============================================================
-- Model 3: Director Genre DNA
--
-- A genre tag says what a movie is. A director's genre probability says what
-- they consistently make. Two movies are similar if they share a genre and
-- both their directors are strongly tied to it.
--
-- Not the course's "same director" example: the two directors can be
-- different people. The link is the genre signature. See README.md.
-- ============================================================

-- Hard pre-filter. A director with two films has no filmography, only a
-- coincidence. Set by reasoning, not tuned.
SET @MIN_DIRECTOR_FILMS = 3;

-- k in the Laplace formula. Read from the data rather than hardcoded.
SET @GENRE_COUNT = (SELECT COUNT(DISTINCT genre) FROM gs_movies_genres);

DROP TABLE IF EXISTS model_3_directors;

CREATE TABLE model_3_directors AS
SELECT md.director_id AS director_id,
       COUNT(DISTINCT md.movie_id) AS total_films
FROM gs_movies_directors AS md
GROUP BY md.director_id
HAVING COUNT(DISTINCT md.movie_id) >= @MIN_DIRECTOR_FILMS;

ALTER TABLE model_3_directors
ADD PRIMARY KEY (director_id);

SELECT COUNT(*) AS directors_kept,
       SUM(total_films) AS films_covered,
       (SELECT COUNT(DISTINCT director_id) FROM gs_movies_directors) AS directors_total
FROM model_3_directors;
-- RESULT: 189 directors kept of 2,674, covering 959 films. The floor removes
--         93% of directors: 2,201 have a single film. Coverage ceiling, not a
--         tuning choice.

-- Laplace-corrected genre probability, per director per genre they worked in.
-- The prob column already in the data is discarded: it has no small-sample
-- correction, so a director with one film in one genre scores 1.0.
-- Genres a director never touched are not materialised. Their probability is
-- 1/(total_films + 21), too low to ever clear a threshold.
DROP TABLE IF EXISTS model_3_director_genre;

CREATE TABLE model_3_director_genre AS
SELECT d.director_id AS director_id,
       mg.genre AS genre,
       COUNT(DISTINCT mg.movie_id) AS films_in_genre,
       d.total_films AS total_films,
       (COUNT(DISTINCT mg.movie_id) + 1) / (d.total_films + @GENRE_COUNT) AS laplace_prob
FROM model_3_directors AS d
JOIN gs_movies_directors AS md ON md.director_id = d.director_id
JOIN gs_movies_genres AS mg ON mg.movie_id = md.movie_id
GROUP BY d.director_id, mg.genre, d.total_films;

ALTER TABLE model_3_director_genre
ADD PRIMARY KEY (director_id, genre);

ALTER TABLE model_3_director_genre
ADD KEY idx_model_3_dg_genre (genre, laplace_prob);

-- A movie can have more than one director, so take the strongest of them.
DROP TABLE IF EXISTS model_3_movie_genre;

CREATE TABLE model_3_movie_genre AS
SELECT md.movie_id AS movie_id,
       dg.genre AS genre,
       MAX(dg.laplace_prob) AS genre_strength
FROM gs_movies_directors AS md
JOIN model_3_director_genre AS dg ON dg.director_id = md.director_id
JOIN gs_movies_genres AS mg
    ON mg.movie_id = md.movie_id
    AND mg.genre = dg.genre  -- the movie must actually carry the genre
GROUP BY md.movie_id, dg.genre;

ALTER TABLE model_3_movie_genre
ADD PRIMARY KEY (movie_id, genre);

ALTER TABLE model_3_movie_genre
ADD KEY idx_model_3_mg_genre (genre, genre_strength);

-- The score is the WEAKER of the two sides. Thresholding on the minimum is the
-- same as requiring both directors to clear the bar, and gives one column to
-- tune on. Where a pair shares several genres, the best one wins.
DROP TABLE IF EXISTS model_3_pairs;

CREATE TABLE model_3_pairs AS
SELECT a.movie_id AS movie_id_1,
       b.movie_id AS movie_id_2,
       MAX(LEAST(a.genre_strength, b.genre_strength)) AS dna_strength
FROM model_3_movie_genre AS a
JOIN model_3_movie_genre AS b
    ON a.genre = b.genre
    AND a.movie_id < b.movie_id
GROUP BY a.movie_id, b.movie_id;

ALTER TABLE model_3_pairs
ADD PRIMARY KEY (movie_id_1, movie_id_2);

-- Both directions, because the ground truth is directed.
DROP TABLE IF EXISTS model_3_candidates;

CREATE TABLE model_3_candidates AS
SELECT movie_id_1, movie_id_2, dna_strength FROM model_3_pairs
UNION ALL
SELECT movie_id_2, movie_id_1, dna_strength FROM model_3_pairs;

ALTER TABLE model_3_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2);

ALTER TABLE model_3_candidates
ADD KEY idx_model_3_signal (dna_strength);

SELECT COUNT(*) AS candidate_pairs,
       COUNT(DISTINCT movie_id_1) AS base_movies,
       MIN(dna_strength) AS min_strength,
       MAX(dna_strength) AS max_strength
FROM model_3_candidates;
-- RESULT: 335,114 pairs, 835 base movies, dna_strength 0.0308 to 0.4737.
--         The ceiling is structural: a 3-film director working in one genre
--         only reaches (3+1)/(3+21) = 0.167, so the useful range sits low.

-- FINAL QUERY. 0.15 is the elbow: 0.12 gives 90.3% and 0.15 gives 93.4%, the
-- largest step in the curve. 0.20 adds 0.3 points but costs two thirds of the
-- volume. 0.35 reads 100% on only 122 rated pairs. See README.md.
-- dna_strength is already bounded 0-1, so aggregation needs no normalisation.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       dna_strength AS dna_strength
FROM model_3_candidates
WHERE dna_strength >= 0.15;
-- RESULT: 158,306 pairs.

-- Measurement view for ../evaluate_model.sql. The fixed 9 exists only so the
-- confusion matrix has a value above 5 to read. Baselines 51.3% and 49.1%.
DROP VIEW IF EXISTS eval_predictor;

CREATE VIEW eval_predictor AS
SELECT movie_id_1 AS base_movie_id,
       movie_id_2 AS recommended_movie_id,
       9 AS recommendation
FROM model_3_candidates
WHERE dna_strength >= 0.15;
-- RESULT: train precision 93.4% on 594 rated pairs, recall 20.3%
--         test  precision 59.4% on 1,235 rated pairs, recall 31.7%
