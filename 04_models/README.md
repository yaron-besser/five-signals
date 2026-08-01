# The five models

Each model defines similarity differently. Each returns pairs and a raw signal.
`aggregate.sql` scales those signals, weights each by that model's measured
train precision, and sums them.

| Model | Similar because | Parameter | Value |
|---|---|---|---|
| 1 Style and Era | shared genres, close release years | shared genres, year gap | >= 3, <= 20 |
| 2 Common Cast | shared credited actors | k | >= 3 |
| 3 Director Genre DNA | both directors work in the shared genre | Laplace score | >= 0.15 |
| 4 Shared Star Actor | a star actor in common | curated list | 22 names |
| 5 Collaborative Filtering | the same people liked both | support, Jaccard | >= 2, >= 0.50 |

## Performance

| Model | Train | Test | Rated pairs, test | Pairs returned |
|---|---|---|---|---|
| 1 | 81.8% | 59.8% | 619 | 46,318 |
| 2 | 91.8% | 68.6% | 405 | 2,934 |
| 3 | 93.4% | 59.4% | 1,235 | 158,306 |
| 4 | 73.0% | 64.8% | 230 | 7,328 |
| 5 | 90.9% | 76.8% | 909 | 20,888 |
| Combined | 88.7% | 82.4% | 238 | 776 |

Baselines: 51.3% train, 49.1% test.

## Two results worth reading before the numbers

**The models rarely agree.** 94.8% of the pairs in the final table fire on
exactly one model. Only 16 fire on all five. The weighted sum is therefore
mostly a single model's opinion scaled by its precision, not a vote. Double
counting the same signal was never the risk it looked like.

**The ranking reverses between train and test.** The strongest model on train
is nearly the weakest on test, and the weakest on train holds up best. Model 4
has no threshold to tune, which is the likely reason. Read the test column.

## Files

| File | What it does |
|---|---|
| `model_1/` to `model_5/` | One folder per model: query, tuning script, README |
| `aggregate.sql` | Combines the five into `model_agg`, then `my_models_agg` |
| `evaluate_model.sql` | The shared measurement every model runs through |
| `model_utils.py` | Shared Python helper for sweeping a parameter grid |

## How measurement works

SQL cannot take a table name as a parameter. So each model file ends by
pointing a view named `eval_predictor` at its own output, and
`evaluate_model.sql` runs against that view. The fixed score of 9 inside the
view exists only so the confusion matrix has a value above 5 to read. It is not
the model's output.

`evaluate_model.sql` is the lecturer's confusion matrix with three lines
changed: the predictor table, the class table, and one `LEFT JOIN` turned into
a `JOIN` so that unrated pairs leave the precision denominator instead of
counting as errors.

To measure test instead of train, swap `gt_pairs_train` for
`movies_recommendations_agg` inside `evaluate_model.sql`.
