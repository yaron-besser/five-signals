-- ============================================================
-- evaluate_model.sql - shared evaluation for every model.
--
-- Copied one for one from 01_pipeline/07_confusion_matrix.sql. The lecturer's
-- formatting and casts are left untouched on purpose, so every model is
-- measured identically and nothing rewritten can change behaviour. That is why
-- the style here does not match the rest of the project. Two of his five
-- queries do not run; the two working ones are below. See ../README.md.
--
-- ONLY three things were changed:
--   imdb_ijs.dummy_recommendations      -> imdb_ijs.eval_predictor
--   imdb_ijs.movies_recommendations_agg -> imdb_ijs.gt_pairs_train
--   the precision query's LEFT JOIN     -> JOIN
--
-- That last one matters. With LEFT JOIN, pairs the class never rated stay in
-- the denominator and count as errors. We measure precision over labelled
-- pairs only: an unrated pair is unknown, not wrong. The recall query keeps
-- its LEFT JOIN, because its denominator must be every positive in the ground
-- truth, including pairs the model did not return.
--
-- Before running this, the model points a view named eval_predictor at its own
-- output. See ../README.md for why.
--
-- CLASS IS TRAIN. To measure test, swap gt_pairs_train for
-- movies_recommendations_agg. Test is measured once, after the models lock.
-- ============================================================

use imdb_ijs;


-- Recall
select 
count(distinct if(class.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null)) as positives
, count(distinct if(class.recommendation > 5 and predictor.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null)) as true_positives
, count(distinct if(class.recommendation > 5 and predictor.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null))/count(distinct if(class.recommendation > 5
					, concat(cast(class.base_movie_id as char)
								, '_'
                                , cast(class.recommended_movie_id as char))
					, null)) as recall
from 
imdb_ijs.gt_pairs_train as class
left join
imdb_ijs.eval_predictor as predictor
on
class.base_movie_id = predictor.base_movie_id
and 
class.recommended_movie_id = predictor.recommended_movie_id
;


-- Precision
select 
count(distinct if(predictor.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as hits
, count(distinct if(predictor.recommendation > 5 and class.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as true_positives


, count(distinct if(predictor.recommendation > 5 and class.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null))/count(distinct if(predictor.recommendation > 5
					, concat(cast(predictor.base_movie_id as char)
								, '_'
                                , cast(predictor.recommended_movie_id as char))
					, null)) as precision_metric
from 
imdb_ijs.eval_predictor as predictor
join
imdb_ijs.gt_pairs_train as class
on
class.base_movie_id = predictor.base_movie_id
and 
class.recommended_movie_id = predictor.recommended_movie_id
;
