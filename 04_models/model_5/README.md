# Model 5: Collaborative Filtering

Two movies are similar if **the same people liked both**. Item to item Jaccard
over the personal rankings, grouped by rater, with a support floor of **2
raters** and a Jaccard cutoff of **0.50**.

Precision 90.9% on train and 76.8% on test, against baselines of 51.3% and
49.1%. 20,888 pairs across 706 base movies.

**Best test precision of the five.**

## The idea

No genre, no cast, no director, no year. This is the only one of the five
models that reads taste instead of metadata, which is the argument for its
place in the set.

"Liked" means `recommendation > 5`, the same cutoff the confusion matrix uses,
so there is one definition of positive across the project. The course scale
backs it: 6 is "good movie, fits my taste" and 5 is "ok movie". The score
distribution is also bimodal with 6 as the trough, so the cutoff lands in the
sparsest part of the data and the labelling is stable.

## No leakage

This model is built **only** on `personal_movies_ranking`. It never reads
`movies_recommendations`.

That table is the ground truth. A collaborative model built on it would be
trained on the answers, and any precision it reported would be meaningless. The
trap is real rather than hypothetical: the course worksheet contains a query
joining personal taste straight against the aggregated ground truth, which is
exactly the leaking shape.

`model_5.sql` ends with a source declaration making the separation explicit.

## Choosing the parameters

**Why a support floor at all?** 63.4% of all candidate volume rests on a single
rater, 270,758 pairs of 427,056, and that band reaches a perfect Jaccard of
1.0. One rater who liked few movies, two of which are this pair, scores 1.0 on
no evidence. Average Jaccard actually **falls** from 0.292 at one rater to
0.231 at three before climbing again, because a tiny union inflates the ratio.

**Why 2 and not 1?** At the chosen cutoff:

| Raters >= | Precision | Rated | Pairs returned |
|---|---|---|---|
| 1 | 88.0% | 435 | 83,576 |
| **2** | **90.9%** | **353** | **20,888** |
| 3 | 90.4% | 334 | 12,530 |
| 4 | 90.4% | 324 | 11,086 |
| 5 | 91.2% | 317 | 9,990 |

+2.9 points, the largest single step, and it is the step that removes the
artefact.

**Why not higher?** Above 2 the floor stops working. 90.9, 90.4, 90.4, 91.2 is
not even a rising line, which is the signature of noise. Floor 5 buys 0.3
points and costs half the volume.

**Why a Jaccard cutoff of 0.50?** At floor 2, precision rises monotonically
with the cutoff: 87.6, 87.6, 88.4, 89.1, 89.2, 89.8, 90.9. There is no elbow,
so there is no measured argument for stopping early, and the project's
precision-first convention decides it. The alternative of 0.30 gives 89.8% on
55,056 pairs, 1.1 points less precise for 2.6 times the volume. If coverage
ever matters more than precision, that is the cell to move to.

**Why not higher than 0.50?** It is the top of the swept range, so nothing
higher was measured. This is the same edge of range limit Model 1 has.

## Coverage, and why the lift is smaller than it looks

`personal_movies_ranking` covers 1,810 movies of the 3,569 in the universe. The
model can only speak about pairs where **both** movies were personally ranked.

| | |
|---|---|
| Train pairs | 5,341 |
| Reachable by this model | 1,704 (31.9%) |
| Good pairs among all train | 2,739 (51.3%) |
| Good pairs among reachable | 1,384 (**81.2%**) |
| Recall ceiling | 1,384 / 2,739 = **50.5%** |

The reachable subset is not a random sample. **81.2% of it is already labelled
good**, against 51.3% for train overall. So the fair comparison for this model
is 90.9% against 81.2%, not against 51.3%. Most of the apparent lift comes from
which films people chose to rank, not from the model. That 81.2% is itself a
finding: films people ranked highly are films the class recommends to each
other.

Report the recall figure together with the ceiling, or 11.7% looks like a
failure when it is an input limit.

## Data quality

This is the only model that reads `personal_movies_ranking`, so it is the only
place the duplicate filter can act.

| Variant | Rows read | Distinct (movie, rater) | Liked movies | Raters |
|---|---|---|---|---|
| Filtered | 5,509 | 5,509 | 1,424 | 35 |
| Raw | 5,846 | 5,509 | 1,424 | 35 |

Rows read differ by 337. Everything else is identical, so **precision is
unchanged with the filter on or off**. That is a real result, not a failed
test. The reason is the `DISTINCT` in `model_5_liked`, which absorbs the
duplicates on the way in.

The protection still matters. Without that `DISTINCT`, 337 duplicated liked
rows would have been counted twice into both the numerator and the denominator
of the Jaccard, corrupting the score on the affected pairs. The filter and the
`DISTINCT` guard the same fault, and the measurement shows the second one
holding.

## Why test behaves differently here

Precision drops 14.1 points, but recall **rises**, 11.7% to 30.2%, where the
metadata models rise far less or not at all. The reason is that this model is
built on the current year's raters while the train ground truth is the prior
year's class. The taste input is contemporaneous with the test labels and not
with the train labels, so the model is better matched to the set it is scored
against second. This is a coverage effect, not leakage.

## Disclosure on test discipline

Test was observed at three parameter settings for this model rather than one.
The tuning script measured its own recommended cell, a looser cell was measured
while weighing volume against precision, and then the chosen cell. The choice
was argued from the train grid and cites no test figure, but three cells were
seen, so 76.8% is a slightly less clean hold out number than a single
measurement would be.

The looser cell is worth keeping for the record: on train it looked 1.8 points
worse than the chosen one, and on test it was 14.9 points worse. That is direct
evidence for preferring the tighter cutoff, and against trusting a train grid
alone.

## Considered and not built

Negative indicators. The bimodal split means the data carries clean dislikes as
well as likes. A pair where one rater liked A and disliked B is evidence
against similarity, which this model currently ignores.

## Files

| File | What it does |
|---|---|
| `model_5.sql` | Builds the liked, pair and scored tables, runs the final query |
| `tune_model_5.py` | Sweeps the support floor and Jaccard grid |
| `grid_train.csv` | The full grid, as measured |
