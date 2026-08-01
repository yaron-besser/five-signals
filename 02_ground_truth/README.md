# 02_ground_truth

The train and test split, and every number measured about it.

The project reports both splits. Thresholds were tuned on 2025 only. 2026 was
measured once, at the end, after all five models were locked.

| Table | Rows | Role |
|---|---|---|
| `movies_recommendations` | 5,549 | 2025, raw, one row per rater per pair |
| `gt_pairs_train` | 5,341 | TRAIN ground truth, aggregated |
| `movies_recommendations_agg` | 4,710 | TEST ground truth, arrives aggregated |

`build_gt_tables.sql` builds `gt_pairs_train`. The 2026 table is used directly,
because it arrives already aggregated and copying it would change nothing.

Both tables keep the same six column layout. Query 1 of the course confusion
matrix does `SELECT * ... UNION`, which needs matching column counts.

## Validation

| Metric | 2025 train | 2026 test |
|---|---|---|
| Rows in file | 5,549 | 4,710 |
| Distinct directed pairs | 5,348 | 4,710 |
| Raters | 24 | not exposed |
| Total human ratings | 5,549 | 6,217 |
| Ratings per pair | 1.04 | 1.32 |
| Null scores | 0 | 0 |
| Scores outside 1 to 10 | 0 | 0 |
| Self pairs | 7 | 0 |
| Pairs present in both directions | 1,177 | 617 |
| Pairs after self pair removal | 5,341 | 4,710 |
| Distinct movies | 2,448 | 1,466 |
| Pairs pointing at a missing movie | 0 | 0 |

Run `gt_validation.sql` to reproduce all of it.

The course repo supplies its own 2025 aggregation, 5,348 rows of which 7 are
self pairs. 5,348 minus 7 is 5,341, so our aggregation reproduces it exactly
once self pairs are excluded.

## Baseline

Under `recommendation > 5`, 2,739 of 5,341 train pairs are positive (51.3%) and
2,311 of 4,710 test pairs (49.1%). A model that calls every pair good scores
exactly that, at 100% recall, while knowing nothing. Any model at or below it
adds nothing.

The near even split also means precision and recall are both readable directly,
with no class imbalance to correct for.

## Score distribution

Floor buckets, so bucket 5 covers 5.00 to 5.99.

| Bucket | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| train | 358 | 519 | 1,129 | 393 | 204 | 45 | 419 | 825 | 1,128 | 321 |
| test | 308 | 544 | 719 | 384 | 490 | 202 | 326 | 883 | 638 | 216 |

Both years peak low at bucket 3 and high at buckets 8 and 9, with bucket 6 the
trough. In train it collapses to 45 pairs against 1,129 at bucket 3. The class
did not rate on a continuum, it decided good or bad. The `> 5` cutoff therefore
lands in the sparsest part of the distribution, so the labelling is stable.

## Three structural facts that shape the results

**Mirrored pairs cap what a symmetric model can reach.** Where a pair appears in
both directions, the average score gap is 0.33 on train and 1.39 on test, and
the two directions land on opposite sides of the cutoff in 92 of 2,354 train
rows (3.9%) and 218 of 1,234 test rows (17.7%). Four of the five models are
symmetric, so those test rows are unreachable by design. Part of any train to
test drop is a property of the data rather than a model failure. Mirrored pairs
are kept, not filtered.

**Test has stronger backing than train.** 1.32 ratings per pair against 1.04.
Almost every 2025 pair rests on one person's opinion, so the train ground truth
carries essentially no inter-rater agreement.

**One rater contributes 924 pairs from a single film series.** Those films share
actors, directors, genres and era, so every model fires on them mechanically.
Measured at source they are labelled good 45.5% of the time against 52.5% for
all other raters, so they are labelled good **less** often than the rest of
train, not more. Whether they raise or lower a given model's precision depends
on how selectively it fires inside the series.

## Trimmed schema

The models run against `gs_*`, built by pipeline step 06.

| Table | Full | Trimmed | Share |
|---|---|---|---|
| movies | 388,269 | 3,569 | 0.9% |
| roles | 3,431,966 | 84,232 | 2.5% |
| actors | 817,718 | 59,188 | 7.2% |

`gs_directors` 2,674, `gs_movies_directors` 3,728, `gs_movies_genres` 6,951.

`gs_movies_ids` and `gs_movies` have identical counts, so no ground truth pair
and no personal ranking points at a movie missing from `movies`.
