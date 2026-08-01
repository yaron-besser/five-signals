# Model 4: Shared Star Actor

Two movies are similar if they share **at least one actor from a curated list
of 22 stars**.

Precision 73.0% on train and 64.8% on test, against baselines of 51.3% and
49.1%. 7,328 pairs across 315 base movies.

There is no tunable threshold. The list is the model.

## The idea

Model 2 asks how many actors two films share and needs 3 to be reliable. Model
4 asks whether the shared actor is a **star**, and one is enough. The report
has to state that distinction or a reader sees the same model twice.

A film count threshold was rejected on purpose. It would admit prolific but
unknown character actors, and exclude stars with short filmographies in this
universe. A curated list avoids both.

All 22 names match an actor in `gs_actors`. The sanity check in `model_4.sql`
returns 22. Anything else means a name failed to match.

| Actor | Credits | | Actor | Credits |
|---|---|---|---|---|
| Tom Hanks | 34 | | Nicolas Cage | 15 |
| Johnny Depp | 33 | | Dustin Hoffman | 15 |
| Robert De Niro | 31 | | George Clooney | 14 |
| Tom Cruise | 23 | | Morgan Freeman | 14 |
| Samuel L. Jackson | 22 | | Jim Carrey | 13 |
| Al Pacino | 21 | | Ben Affleck | 12 |
| Mel Gibson | 17 | | Kevin Costner | 12 |
| Gene Hackman | 17 | | Matt Damon | 12 |
| Jack Nicholson | 17 | | Anthony Hopkins | 12 |
| Brad Pitt | 17 | | Clint Eastwood | 8 |
| Leonardo DiCaprio | 16 | | Marlon Brando | 5 |

Credits are reported, not used as a filter.

## The measured finding: on train the list contributes nothing

This is the honest headline for this model.

| Definition of a star | Pairs returned | Rated | Train | Test |
|---|---|---|---|---|
| Curated list of 22 | 7,328 | 237 | 73.0% | 64.8% |
| Any shared credited actor | 89,982 | 1,206 | 73.2% | 60.2% |
| Actor with 3 or more credits | 82,122 | 1,188 | 73.1% | 60.3% |

On train, three different definitions of "star" land within 0.2 points of each
other. The curated list costs 92% of the volume and moves precision by -0.2
points. The conclusion is not that the list is badly chosen. It is that on this
data, **sharing any credited actor already carries the whole signal, and who
that actor is carries none of it.**

The control is not a footnote. It is a view in `model_4.sql`
(`eval_predictor_control`) run through the same `evaluate_model.sql`, so the
number stays reproducible.

## On test the comparison reverses

The curated list reads 64.8% and the control reads 60.2%, on 230 and 1,160
rated pairs. So the list buys nothing on train but holds up 4.6 points better
on data it never saw.

Both halves belong in the report. The train result rules out star status being
a strong independent signal here. It does not rule out the list being the
steadier of the two definitions.

## Why this counts as a result

The models plan predicted these models would be restrictive and miss good
pairs, and chose precision as the metric on that basis. What it did not predict
is that the restriction would buy no precision at all. Model 4 also does not
beat Model 2: 73.0% against 91.8%. The premise that one shared lead beats three
shared bit parts is not supported by measurement, and the report concedes that
rather than asserting it.

The model still earns its place in the ensemble for a different reason. It is
the one model with nothing to tune, and it has the smallest train to test drop
of the five, 8.2 points. A model with no threshold cannot overfit one.

## Limits

Recall is 6.3% on train and 6.4% on test. The train precision figure rests on
237 rated pairs and the test figure on 230, which is thin for both. The
with and without comparison for the data quality layer was not measured at this
model's operating point.

## Files

| File | What it does |
|---|---|
| `model_4.sql` | Builds the star list and candidate pairs, plus the control view |

There is no tuning script, because there is no parameter to sweep. The model
reads `gs_roles_credited`, built by `model_2/build_credited_roles.sql`.
