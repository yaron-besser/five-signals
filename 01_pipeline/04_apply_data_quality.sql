-- ============================================================
-- 04_apply_data_quality.sql
-- Rebuilds personal_movies_ranking with the constraints from the course file
-- and moves the staged data across, collapsing duplicates.
--
-- The class file loaded at step 03 contains 400 rows that violate the primary
-- key (movie_id, suggested_by): two students submitted their 200 rankings
-- twice. Staging first turns that duplication from a log of failures into a
-- number we can measure. Verified beforehand that all 400 duplicate keys are
-- identical on all five columns, so DISTINCT loses nothing. 
--
-- personal_movies_ranking_raw is kept on purpose, so the contribution of the
-- data quality layer can be measured with the filter on and off.
--
-- RUN ONCE, FORWARD ONLY. A second run would move the already-filtered table
-- into _raw and report zero rows removed. That is a false measurement rather
-- than an error, so nothing stops it. To redo, start from the reset in 01.
-- ============================================================

USE imdb_ijs;

RENAME TABLE personal_movies_ranking TO personal_movies_ranking_raw;

-- Identical to the definition in the course file build_collaborative_gs.txt
CREATE TABLE personal_movies_ranking (
    movie_id        INT NOT NULL,
    recommendation  INT NOT NULL,
    suggested_by    VARCHAR(255) NOT NULL,
    justification   VARCHAR(255) NOT NULL,
    comment         VARCHAR(255),
    PRIMARY KEY (movie_id, suggested_by),
    CONSTRAINT CHK_personal_recommendation
        CHECK (recommendation >= 1 AND 10 >= recommendation),
    CONSTRAINT CHK_personal_justification
        CHECK (LENGTH(justification) >= 10),
    FOREIGN KEY (movie_id) REFERENCES movies(id)
);

INSERT INTO personal_movies_ranking
    (movie_id, recommendation, suggested_by, justification, comment)
SELECT DISTINCT
    movie_id,
    recommendation,
    suggested_by,
    justification,
    comment
FROM personal_movies_ranking_raw;


-- Measured contribution of the data quality layer.

SELECT
    (SELECT COUNT(*) FROM personal_movies_ranking_raw) AS rows_loaded,
    (SELECT COUNT(*) FROM personal_movies_ranking) AS rows_after_filter,
    (SELECT COUNT(*) FROM personal_movies_ranking_raw)
        - (SELECT COUNT(*) FROM personal_movies_ranking) AS rows_removed;
-- RESULT: raw 7445 | clean 7045 | removed 400

SELECT
    suggested_by AS rater,
    COUNT(*) AS rows_submitted,
    COUNT(DISTINCT movie_id) AS distinct_movies,
    COUNT(*) - COUNT(DISTINCT movie_id) AS duplicate_rows
FROM personal_movies_ranking_raw
GROUP BY suggested_by
HAVING duplicate_rows > 0
ORDER BY duplicate_rows DESC;
-- RESULT: two raters, 400 submitted and 200 distinct each. Each submitted
--         their whole file twice; no partial or accidental duplication.

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT suggested_by) AS raters,
    COUNT(DISTINCT movie_id) AS distinct_movies,
    MIN(recommendation) AS min_score,
    MAX(recommendation) AS max_score
FROM personal_movies_ranking;
-- RESULT: 7045 rows | 35 raters | 1810 movies | scores 1 to 10
