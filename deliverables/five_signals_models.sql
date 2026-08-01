-- ============================================================
-- five_signals_models.sql
--
-- Final project, Databases for Data Analytics, Reichman University, 2026B
-- Team: five_signals
-- Yaron Besser (324943109), Nevo Aloni (322815820)
--
-- Five movie similarity models and the union that combines them into one
-- recommendation table, my_models_agg.
--
-- HOW TO RUN
--   Run top to bottom on schema imdb_ijs, after the four course files:
--   build_gs, movies_recommendations, movies_recommendations_agg,
--   build_restricted_gs_db. Takes about 20 seconds and produces no errors.
--   Point the course confusion matrix at my_models_agg.
--
--   The model queries emit their full pair lists, about 326,000 rows in
--   total. Redirect to a file if you are running it interactively.
--
-- CONTENTS
--   0  Shared helper table, credited roles. Sections 2 and 4 read it.
--   1  Model 1, Style & Era
--   2  Model 2, Common Cast Members
--   3  Model 3, Director Genre DNA
--   4  Model 4, Shared Star Actor
--   5  Model 5, Collaborative Filtering
--   6  The union, into my_models_agg
--
-- HOW TO READ IT
--   Each model opens with a block stating what it means, why its threshold
--   is set where it is, and what it scored. The SQL follows. Every number in
--   those blocks was measured, and the queries that produced them are in the
--   project repository.
--
-- ON THE NUMBERS
--   Train is the 2025 class, test is the 2026 class. Every threshold was
--   tuned on train. Test was measured once, after all five models were
--   locked. Baselines, meaning a model that calls every pair good: 51.3% on
--   train and 49.1% on test.
--
--   Precision is measured over labelled pairs only. A pair the class never
--   rated is unknown rather than wrong, so it leaves the denominator instead
--   of counting as an error.
-- ============================================================

USE imdb_ijs;

-- ============================================================
-- SECTION 0 - SHARED HELPER: CREDITED ROLES
--
-- gs_roles holds function labels as well as character names: Man, Mother,
-- Student, Newscaster. Two films sharing an actor credited as "Man" share
-- nothing. This table removes those rows before models 2 and 4 read it.
--
-- The cut is at role names appearing in 38 or more distinct movies, which is
-- where the band stops being character names and starts being job titles.
-- Given names are kept on a list, because a character called John is a real
-- part.
--
-- It costs 13,212 of 84,232 role rows, 15.7%, and 471 films lose their whole
-- cast. It buys 6.7 points of precision in Model 2 at the chosen threshold,
-- 85.1% to 91.8%, and it helps at every threshold tested.
-- ============================================================

-- Step 1: identify role names that are function labels, not characters.
-- Cut at 38: the boundary sits here. 38 holds Man and Newscaster, both
-- labels. 37 is empty. 36 holds Tony, a character. 39 would keep two labels.
--
-- Keep-list: the only given names above the cut, verified across the whole
-- band. Frequency cannot see them - a character called John is a real part.
DROP TABLE IF EXISTS generic_roles;

CREATE TABLE generic_roles AS
SELECT role AS role_name,
       COUNT(DISTINCT movie_id) AS movies_with_role
FROM gs_roles
WHERE TRIM(role) <> ''
    AND role NOT LIKE '%James Bond%'  -- keep-list
    AND role NOT LIKE '%Alice%'
    AND role NOT LIKE '%John%'
GROUP BY role
HAVING COUNT(DISTINCT movie_id) >= 38;
-- RESULT: 33 generic role names

-- Step 2: the cast table the models run against.
DROP TABLE IF EXISTS gs_roles_credited;

CREATE TABLE gs_roles_credited AS
SELECT r.actor_id AS actor_id,
       r.movie_id AS movie_id,
       r.role AS role
FROM gs_roles AS r
LEFT JOIN generic_roles AS g
    ON r.role = g.role_name
WHERE TRIM(r.role) != ''  
    AND g.role_name IS NULL; 
-- RESULT: 71,020 rows, from 84,232. 5,349 blank roles and 7,863 generic
--         labels removed. Movies with cast drop 3,019 to 2,548, so 471
--         films lose their whole cast and become unreachable here.

CREATE INDEX idx_credited_actor ON gs_roles_credited (actor_id);
CREATE INDEX idx_credited_movie ON gs_roles_credited (movie_id);

-- ============================================================
-- SECTION 1 - MODEL 1: STYLE & ERA
--
-- Two movies are similar if they share at least 3 genres and came out within
-- 20 years of each other. Genre carries the style, the year gap carries the
-- era. Neither works alone: one shared genre puts most dramas beside most
-- other dramas, and a shared year says nothing at all.
--
-- WHY 3 SHARED GENRES
--   2 gives 76.7%, 3 gives 81.8%. That 5.1 point step is the largest in the
--   grid. 4 drops to 77.6% and rests on 58 rated pairs, worse on both counts.
--
-- WHY A 20 YEAR WINDOW, AND A NEGATIVE RESULT WE REPORT
--   The window does nothing. At 3 shared genres, precision across windows of
--   2, 5, 10, 15 and 20 years reads 81.1%, 81.1%, 79.7%, 81.4%, 81.8%. A 2.1
--   point spread with no direction, while volume grows 3.7 times. A parameter
--   that does not move precision should not discard 73% of the output, so we
--   kept the loosest window we measured. In substance this model is "two
--   movies sharing 3 or more genres", and we say so rather than claim the era
--   half earns its place.
--
-- PERFORMANCE   train 81.8%, recall 6.9%  |  test 59.8%, recall 16.0%
-- COVERAGE      3,178 of 3,569 movies carry a genre. 89.0% is the ceiling.
-- ============================================================

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
WHERE ABS(m1.year - m2.year) <= 20
GROUP BY g1.movie_id, g2.movie_id;

ALTER TABLE model_1_pairs
ADD PRIMARY KEY (movie_id_1, movie_id_2);

-- Mirrored to both directions, because the ground truth is directed while
-- this model is symmetric. Where the class scored the two directions onto
-- opposite sides of the cutoff, a symmetric model must get one of them wrong.
DROP TABLE IF EXISTS model_1_candidates;

CREATE TABLE model_1_candidates AS
SELECT movie_id_1, movie_id_2, shared_genres, year_gap FROM model_1_pairs
UNION ALL
SELECT movie_id_2, movie_id_1, shared_genres, year_gap FROM model_1_pairs;

ALTER TABLE model_1_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2),
ADD KEY idx_model_1_signal (year_gap, shared_genres);

SELECT COUNT(*) AS candidate_pairs,
       COUNT(DISTINCT movie_id_1) AS base_movies,
       MAX(shared_genres) AS max_shared_genres
FROM model_1_candidates;
-- RESULT: 1,924,104 pairs over 3,178 base movies, shared_genres 1 to 10.
--         Exactly twice model_1_pairs, so the mirror lost nothing.

-- FINAL QUERY. shared_genres is the raw signal; section 6 normalises it.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       shared_genres AS shared_genres
FROM model_1_candidates
WHERE shared_genres >= 3
    AND year_gap <= 20;
-- RESULT: 46,318 pairs over 1,000 base movies.

-- ============================================================
-- SECTION 2 - MODEL 2: COMMON CAST MEMBERS
--
-- Two movies are similar if they share at least 3 credited actors. One shared
-- actor is weak evidence, because working actors appear in many films. Three
-- at once is not a coincidence: a sequel, a series, a director reusing people.
--
-- WHY 3
--   Precision by threshold: 73.2% at 1, 84.7% at 2, 91.8% at 3, 94.8% at 4,
--   95.2% at 5. The gain collapses after 3, and 3 returns twice the volume
--   of 4. Above 8 shared actors precision reaches 100%, but on 118 rated
--   pairs or fewer, almost all sequels from one series. Perfect precision on
--   a tiny sample is not evidence, so volume is reported beside precision.
--
-- AGAINST MODEL 4
--   Model 2 asks how many actors two films share and needs 3. Model 4 asks
--   whether the shared actor is a star, and one is enough. Different
--   questions, and measured they overlap on only 316 pairs of the 2,934 this
--   model returns.
--
-- PERFORMANCE   train 91.8%, recall 13.9%  |  test 68.6%, recall 12.0%
-- ============================================================

DROP TABLE IF EXISTS model_2_candidates;

CREATE TABLE model_2_candidates AS
SELECT gr1.movie_id AS movie_id_1,
       gr2.movie_id AS movie_id_2,
       COUNT(DISTINCT gr1.actor_id) AS common_actors
FROM gs_roles_credited AS gr1
JOIN gs_roles_credited AS gr2
    ON gr1.actor_id = gr2.actor_id
    AND gr1.movie_id <> gr2.movie_id  -- <> not < : emits both directions
GROUP BY gr1.movie_id, gr2.movie_id
HAVING COUNT(DISTINCT gr1.actor_id) >= 3;

-- Fails loudly if the query ever produces a duplicate pair.
ALTER TABLE model_2_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2);

-- FINAL QUERY. common_actors is the raw signal; section 6 normalises it.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       common_actors AS common_actors
FROM model_2_candidates;
-- RESULT: 2,934 pairs over 863 base movies, common_actors 3 to 47.

-- ============================================================
-- SECTION 3 - MODEL 3: DIRECTOR GENRE DNA
--
-- A genre tag says what a movie is. A director's genre probability says what
-- they consistently make. Two movies are similar if they share a genre and
-- both their directors are strongly tied to it, so there is expertise on both
-- sides rather than just a label match.
--
-- This is deliberately not the course's "same director" example. The two
-- directors can be different people. The link is the genre signature.
--
-- THE LAPLACE CORRECTION
--   Score is (films in genre + 1) / (total films + 21), 21 being the number
--   of genres. The prob column already in the data has no small sample
--   correction: a director with one film in one genre scores 1.0 there. This
--   pulls extremes back in proportion to how little evidence supports them.
--   A 3-film director working in one genre only reaches (3+1)/(3+21) = 0.167,
--   so the whole scale sits low and a bar of 0.15 is strict, not loose.
--   The strongest signatures are specialists: Disney in Animation at 0.474,
--   Woody Allen in Comedy at 0.460, Hitchcock in Thriller at 0.375.
--
-- WHY 0.15
--   0.12 gives 90.3%, 0.15 gives 93.4%, the largest step in the curve. 0.20
--   adds 0.3 points but costs two thirds of the volume and halves recall.
--   0.35 reads 100% on 122 rated pairs, while 0.15 rests on 594.
--
-- WHY THE 3-FILM FLOOR IS NOT TUNED
--   A director with two films has no filmography, only a coincidence. The
--   Laplace correction handles the small sample bias that remains above the
--   floor. Tuning it too would fit a parameter that reasoning already fixes.
--
-- PERFORMANCE   train 93.4%, recall 20.3%  |  test 59.4%, recall 31.7%
--   The 34.0 point fall is the largest of the five. Worth stating plainly:
--   the train figure rests on 594 rated pairs and the test figure on 1,235,
--   so the test number is the better supported of the two.
--
-- COVERAGE      189 of 2,674 directors clear the floor, covering 959 films.
-- ============================================================

SET @MIN_DIRECTOR_FILMS = 3;
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
       SUM(total_films) AS films_covered
FROM model_3_directors;
-- RESULT: 189 directors, 959 films. 2,201 of the 2,674 have a single film.

-- Genres a director never touched are not materialised. Their probability
-- would be 1/(total_films + 21), too low to ever clear a threshold.
DROP TABLE IF EXISTS model_3_director_genre;

CREATE TABLE model_3_director_genre AS
SELECT d.director_id AS director_id,
       mg.genre AS genre,
       (COUNT(DISTINCT mg.movie_id) + 1) / (d.total_films + @GENRE_COUNT) AS laplace_prob
FROM model_3_directors AS d
JOIN gs_movies_directors AS md ON md.director_id = d.director_id
JOIN gs_movies_genres AS mg ON mg.movie_id = md.movie_id
GROUP BY d.director_id, mg.genre, d.total_films;

ALTER TABLE model_3_director_genre
ADD PRIMARY KEY (director_id, genre),
ADD KEY idx_model_3_dg_genre (genre, laplace_prob);

-- A movie can have more than one director, so take the strongest.
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
ADD PRIMARY KEY (movie_id, genre),
ADD KEY idx_model_3_mg_genre (genre, genre_strength);

-- The pair score is the WEAKER of the two sides. Thresholding on the minimum
-- is the same as requiring both directors to clear the bar, and gives one
-- column to tune. Where a pair shares several genres, the best one wins.
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

DROP TABLE IF EXISTS model_3_candidates;

CREATE TABLE model_3_candidates AS
SELECT movie_id_1, movie_id_2, dna_strength FROM model_3_pairs
UNION ALL
SELECT movie_id_2, movie_id_1, dna_strength FROM model_3_pairs;

ALTER TABLE model_3_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2),
ADD KEY idx_model_3_signal (dna_strength);

SELECT COUNT(*) AS candidate_pairs,
       COUNT(DISTINCT movie_id_1) AS base_movies,
       MAX(dna_strength) AS max_strength
FROM model_3_candidates;
-- RESULT: 335,114 pairs over 835 base movies, dna_strength 0.0308 to 0.4737.

-- FINAL QUERY. dna_strength is already bounded 0-1, so section 6 uses it
-- without normalising.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       dna_strength AS dna_strength
FROM model_3_candidates
WHERE dna_strength >= 0.15;
-- RESULT: 158,306 pairs.

-- ============================================================
-- SECTION 4 - MODEL 4: SHARED STAR ACTOR
--
-- Two movies are similar if they share at least one actor from a curated list
-- of 22 stars. There is no tunable threshold: the list is the model.
--
-- A film count threshold was rejected on purpose. It would admit prolific but
-- unknown character actors, and exclude stars with short filmographies here.
--
-- THE MEASURED FINDING, WHICH IS NEGATIVE ON TRAIN
--   We ran a control with the list removed, so any shared credited actor
--   qualifies, and a third variant using actors with 3 or more credits. On
--   train all three land within 0.2 points: 73.0%, 73.2%, 73.1%. The curated
--   list costs 92% of the volume and buys nothing. The honest reading is not
--   that the list is badly chosen, but that on this data sharing any credited
--   actor carries the whole signal and who the actor is carries none of it.
--
--   On test the comparison reverses: the list reads 64.8% and the control
--   60.2%. It buys nothing on train yet holds up 4.6 points better on data it
--   never saw. Both halves are reported.
--
-- WHY IT STAYS IN THE SET
--   It is the only model with nothing to tune, and it has the smallest train
--   to test fall of the five, 8.2 points. A model with no threshold cannot
--   overfit one.
--
-- PERFORMANCE   train 73.0%, recall 6.3%  |  test 64.8%, recall 6.5%
-- ============================================================

-- Matched by name rather than id, so the table survives a rebuild. The (I)
-- suffixes are IMDB disambiguators and part of the stored name.
DROP TABLE IF EXISTS model_4_star_actors;

CREATE TABLE model_4_star_actors AS
SELECT a.id AS actor_id,
       CONCAT(a.first_name, ' ', a.last_name) AS actor_name
FROM gs_actors AS a
WHERE (a.first_name, a.last_name) IN (
    ('Tom', 'Hanks'), ('Leonardo', 'DiCaprio'), ('Robert', 'De Niro'),
    ('Al', 'Pacino'), ('Brad', 'Pitt'), ('Jack', 'Nicholson'),
    ('Tom', 'Cruise'), ('Clint', 'Eastwood'), ('Dustin', 'Hoffman'),
    ('Anthony', 'Hopkins'), ('Jim', 'Carrey'), ('Gene', 'Hackman'),
    ('Marlon', 'Brando'), ('Nicolas', 'Cage'), ('Johnny', 'Depp'),
    ('Matt', 'Damon'), ('Ben', 'Affleck'), ('George', 'Clooney'),
    ('Kevin', 'Costner'), ('Morgan (I)', 'Freeman'),
    ('Samuel L.', 'Jackson'), ('Mel (I)', 'Gibson')
);

ALTER TABLE model_4_star_actors
ADD PRIMARY KEY (actor_id);

-- Anything other than 22 means a name failed to match.
SELECT COUNT(*) AS stars_found
FROM model_4_star_actors;
-- RESULT: 22 stars matched, out of 22 on the list

DROP TABLE IF EXISTS model_4_candidates;

CREATE TABLE model_4_candidates AS
SELECT r1.movie_id AS movie_id_1,
       r2.movie_id AS movie_id_2,
       COUNT(DISTINCT r1.actor_id) AS shared_stars
FROM gs_roles_credited AS r1
JOIN gs_roles_credited AS r2
    ON r1.actor_id = r2.actor_id
    AND r1.movie_id <> r2.movie_id  -- <> not < : emits both directions
JOIN model_4_star_actors AS s
    ON s.actor_id = r1.actor_id
GROUP BY r1.movie_id, r2.movie_id;

ALTER TABLE model_4_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2);

-- FINAL QUERY.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       shared_stars AS shared_stars
FROM model_4_candidates;
-- RESULT: 7,328 pairs over 315 base movies, at most 3 shared stars.

-- THE CONTROL. Not scaffolding: this is the query behind the negative finding
-- above. The star list is removed, so any shared credited actor qualifies.
SELECT gr1.movie_id AS movie_id_1,
       gr2.movie_id AS movie_id_2,
       COUNT(DISTINCT gr1.actor_id) AS shared_actors
FROM gs_roles_credited AS gr1
JOIN gs_roles_credited AS gr2
    ON gr1.actor_id = gr2.actor_id
    AND gr1.movie_id <> gr2.movie_id
GROUP BY gr1.movie_id, gr2.movie_id;
-- RESULT: 89,982 pairs. Train 73.2% on 1,206 rated pairs, test 60.2% on
--         1,160. Against the curated list's 73.0% and 64.8%.

-- ============================================================
-- SECTION 5 - MODEL 5: COLLABORATIVE FILTERING
--
-- Two movies are similar if the same people liked both. Item to item Jaccard
-- over the personal rankings, grouped by rater. No genre, no cast, no
-- director, no year. This is the only model in the set that reads taste
-- instead of metadata, which is the argument for its place.
--
-- "Liked" is recommendation > 5, the same cutoff the confusion matrix uses.
--
-- NO LEAKAGE
--   Built only on personal_movies_ranking. It never reads
--   movies_recommendations, which is the ground truth. A collaborative model
--   built on the ground truth would be trained on the answers and its
--   precision would mean nothing.
--
-- WHY A SUPPORT FLOOR OF 2 RATERS
--   Jaccard alone is naive at low support. One rater who liked few films, two
--   of which are this pair, scores a perfect 1.0 on no evidence. 63.4% of all
--   candidate volume sits at exactly one rater, 270,758 pairs of 427,056.
--   Moving the floor from 1 to 2 adds 2.9 points, the largest step. Moving it
--   higher does not help: floors 2 to 5 give 90.9%, 90.4%, 90.4%, 91.2%. That
--   is not even a rising line, which is what noise looks like.
--
-- WHY A JACCARD CUTOFF OF 0.50
--   At floor 2 precision rises at every step and never flattens, so there is
--   no elbow to point at and the project's precision-first rule decides it.
--   0.30 gives 89.8% on 55,056 pairs, 1.1 points less for 2.6 times the
--   volume, and is the cell to move to if coverage ever matters more.
--
-- WHAT THE PRECISION FIGURE MEANS HERE
--   The rankings cover 1,810 of 3,569 movies, so only 31.9% of train pairs
--   are visible to this model. That subset is not random: 81.2% of it is
--   already labelled good, against 51.3% for train overall. The fair
--   comparison is 90.9% against 81.2%, not against 51.3%. Much of the
--   apparent lift comes from which films people chose to rank.
--
-- PERFORMANCE   train 90.9%, recall 11.7%  |  test 76.8%, recall 30.2%
--   Best test precision of the five. Recall rises from train to test, where
--   the metadata models barely move, because the raters are the current year
--   while the train labels are the prior one.
-- ============================================================

-- DISTINCT is defensive. It matters when this is pointed at the unfiltered
-- personal_movies_ranking_raw for the data quality comparison, where 337
-- duplicated rows would otherwise be counted twice into the Jaccard.
DROP TABLE IF EXISTS model_5_liked;

CREATE TABLE model_5_liked AS
SELECT DISTINCT p.movie_id AS movie_id,
       p.suggested_by AS suggested_by
FROM personal_movies_ranking AS p
WHERE p.recommendation > 5;

ALTER TABLE model_5_liked
ADD PRIMARY KEY (movie_id, suggested_by),
ADD KEY idx_model_5_liked_rater (suggested_by);

-- Denominator side of the Jaccard: how many raters liked each movie.
DROP TABLE IF EXISTS model_5_likers;

CREATE TABLE model_5_likers AS
SELECT l.movie_id AS movie_id,
       COUNT(DISTINCT l.suggested_by) AS likers
FROM model_5_liked AS l
GROUP BY l.movie_id;

ALTER TABLE model_5_likers
ADD PRIMARY KEY (movie_id);

DROP TABLE IF EXISTS model_5_pairs;

CREATE TABLE model_5_pairs AS
SELECT l1.movie_id AS movie_id_1,
       l2.movie_id AS movie_id_2,
       COUNT(DISTINCT l1.suggested_by) AS co_raters
FROM model_5_liked AS l1
JOIN model_5_liked AS l2
    ON l1.suggested_by = l2.suggested_by
    AND l1.movie_id < l2.movie_id
GROUP BY l1.movie_id, l2.movie_id;

ALTER TABLE model_5_pairs
ADD PRIMARY KEY (movie_id_1, movie_id_2);

-- The denominator cannot be zero: a pair only reaches this table if some
-- rater liked both, so the union is at least 1.
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

DROP TABLE IF EXISTS model_5_candidates;

CREATE TABLE model_5_candidates AS
SELECT movie_id_1, movie_id_2, co_raters, jaccard FROM model_5_scored
UNION ALL
SELECT movie_id_2, movie_id_1, co_raters, jaccard FROM model_5_scored;

ALTER TABLE model_5_candidates
ADD PRIMARY KEY (movie_id_1, movie_id_2),
ADD KEY idx_model_5_candidates_signal (co_raters, jaccard);

-- The support distribution, which is the evidence behind the floor.
SELECT co_raters AS co_raters,
       COUNT(*) AS pairs,
       AVG(jaccard) AS avg_jaccard
FROM model_5_candidates
GROUP BY co_raters
ORDER BY co_raters;
-- RESULT: 427,056 pairs in total, 270,758 of them at co_raters = 1, and that
--         band reaches jaccard 1.0. avg_jaccard FALLS from 0.2918 at one
--         rater to 0.2307 at three before climbing to 0.3546 at four and
--         above, because a tiny union inflates the ratio.

-- FINAL QUERY. co_raters is the support floor, not part of the output.
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       jaccard AS jaccard
FROM model_5_candidates
WHERE co_raters >= 2
    AND jaccard >= 0.50;
-- RESULT: 20,888 pairs over 706 base movies.

-- ============================================================
-- SECTION 6 - THE UNION: COMBINING ALL FIVE
--
--   Score = sum over models of (train precision x normalised signal)
--
-- Each model contributes its raw signal scaled to 0-1 and weighted by its own
-- measured train precision, so a model that was right more often on train
-- counts for more. Models 3 and 5 already return 0-1. Model 4 is binary.
-- Model 1 divides by 10, the most shared genres seen, and Model 2 by 47, the
-- most shared actors.
--
-- The highest score possible is the sum of the weights, 4.3097. The highest
-- actually observed is 2.2471, because the models rarely agree: 94.8% of the
-- pairs that survive come from exactly one model and only 16 fire on all
-- five. Measured pairwise, the largest overlap between any two models is
-- 15.4%, and Models 2 and 4, which both key on shared actors, overlap on only
-- 316 pairs of the 2,934 Model 2 returns.
--
-- WHY THE CUT IS AT 1.0
--   Precision is flat across the whole curve, from 86.7% at a cut of 0.1 to
--   88.7% at 1.0, so the curve alone gives no reason to prefer a cutoff. Size
--   decides it: at 0.1 the table holds 222,082 pairs from a 3,569 film
--   universe, which is a list of everything rather than a recommendation.
--   776 pairs is a set a person could be shown. The cost is recall, which
--   falls from 33.0% to 4.6%, and we say so in the report.
--
-- WHY THE SCALE IS 6-10 AND THE COLUMN IS DECIMAL
--   Every row here is a recommendation, so every row must read as positive,
--   and the course guide requires 6 or above. DECIMAL rather than INT because
--   the ground truth is DECIMAL and rounding would drop resolution the other
--   side keeps.
--
-- FINAL PERFORMANCE, measured once on each split:
--   split  labelled  correct  precision  recall  baseline
--   TRAIN       142      126      88.7%    4.6%     51.3%
--   TEST        238      196      82.4%    8.5%     49.1%
--
--   The 6.3 point fall from train to test is the smallest of anything
--   measured in this project. Individual models fall between 8.2 and 34.0.
--   On test the combination beats every model in it.
-- ============================================================

DROP TABLE IF EXISTS model_agg;

CREATE TABLE model_agg AS
SELECT movie_id_1 AS movie_id_1,
       movie_id_2 AS movie_id_2,
       COUNT(*) AS models_firing,
       SUM(weighted) AS score
FROM (
    SELECT movie_id_1, movie_id_2, 0.8182 * shared_genres / 10 AS weighted
    FROM model_1_candidates
    WHERE shared_genres >= 3 AND year_gap <= 20

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.9179 * common_actors / 47
    FROM model_2_candidates

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.9343 * dna_strength
    FROM model_3_candidates
    WHERE dna_strength >= 0.15

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.7300
    FROM model_4_candidates

    UNION ALL
    SELECT movie_id_1, movie_id_2, 0.9093 * jaccard
    FROM model_5_candidates
    WHERE co_raters >= 2 AND jaccard >= 0.50
) AS u
GROUP BY movie_id_1, movie_id_2;

ALTER TABLE model_agg
ADD PRIMARY KEY (movie_id_1, movie_id_2),
ADD KEY idx_model_agg_score (score);

SELECT models_firing AS models_firing,
       COUNT(*) AS pairs
FROM model_agg
GROUP BY models_firing
ORDER BY models_firing;
-- RESULT: 1 model 211,642 | 2 models 10,812 | 3 models 684 | 4 models 94 |
--         5 models 16. Total 223,248 pairs, score 0.0586 to 2.2471.

-- THE THRESHOLD CURVE
--
-- One pass over the labelled pairs, each counted into every bucket it
-- clears. Pointed at movies_recommendations_agg, a course table, so this
-- runs anywhere the four course files have been run. The matching query
-- against the 2025 train labels needs gt_pairs_train, a table we built,
-- and it lives in the project repository rather than here.
--
-- THE CUT WAS CHOSEN ON TRAIN. Test was measured once, afterwards. Both
-- curves are recorded below so the choice can be judged against what was
-- known when it was made, not against what came later.
SELECT SUM(a.score >= 0.1) AS n_10,
       SUM(a.score >= 0.4) AS n_40,
       SUM(a.score >= 0.8) AS n_80,
       SUM(a.score >= 1.0) AS n_100,
       SUM(a.score >= 0.1 AND c.recommendation > 5) AS good_10,
       SUM(a.score >= 0.4 AND c.recommendation > 5) AS good_40,
       SUM(a.score >= 0.8 AND c.recommendation > 5) AS good_80,
       SUM(a.score >= 1.0 AND c.recommendation > 5) AS good_100
FROM model_agg AS a
JOIN movies_recommendations_agg AS c
    ON c.base_movie_id = a.movie_id_1
    AND c.recommended_movie_id = a.movie_id_2;
-- RESULT:
--   cut   train n  train prec  train rec   test n  test prec  test rec
--   0.1     1,044       86.7%      33.0%    2,126      61.4%     56.5%
--   0.4       632       84.8%      19.6%    1,213      70.7%     37.1%
--   0.8       237       88.2%       7.6%      433      79.2%     14.8%
--   1.0       142       88.7%       4.6%      238      82.4%      8.5%
--
-- WHY THE TWO CURVES DISAGREE
--   On train precision moves 2.0 points end to end and dips in the middle,
--   which is why size and not precision decided the cut. On test it rises
--   21.0 points while recall falls from 56.5% to 8.5%.
--
--   The reading, and it is a reading rather than a measurement: every
--   threshold inside every model was tuned on train, so even the low
--   scoring train pairs had already passed filters fitted to those labels.
--   Little was left for the combined score to separate. On test the filters
--   generalise less and the score does the separating work instead. The
--   curve only shows what the aggregation is worth on data it never saw.

-- FINAL RECOMMENDATIONS. This is the table the confusion matrix reads.
DROP TABLE IF EXISTS my_models_agg;

CREATE TABLE my_models_agg AS
SELECT movie_id_1 AS base_movie_id,
       movie_id_2 AS recommended_movie_id,
       6 + 4 * (score - 1.0) / (2.2471 - 1.0) AS recommendation,
       models_firing AS models_firing,
       score AS raw_score
FROM model_agg
WHERE score >= 1.0;

ALTER TABLE my_models_agg
ADD PRIMARY KEY (base_movie_id, recommended_movie_id);

SELECT COUNT(*) AS pairs,
       MIN(recommendation) AS min_rec,
       MAX(recommendation) AS max_rec
FROM my_models_agg;
-- RESULT: 776 pairs, recommendation 6.0038 to 9.9999.

-- THE RECOMMENDATIONS THEMSELVES. Ordered so the strongest read first.
-- 776 rows, which is the whole point of everything above it.
SELECT base_movie_id AS base_movie_id,
       recommended_movie_id AS recommended_movie_id,
       recommendation AS recommendation,
       models_firing AS models_firing
FROM my_models_agg
ORDER BY recommendation DESC;
-- RESULT: 776 pairs. The top of the list is where several models agree.
