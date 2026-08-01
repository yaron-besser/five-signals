# Model 2: Common Cast Members

Two movies are similar if they share at least **3 credited actors**, measured
on the filtered cast table `gs_roles_credited`.

Precision 91.8% on train and 68.6% on test, against baselines of 51.3% and
49.1%. 2,934 pairs across 863 base movies.

## The idea

Two films sharing several cast members are usually connected: a sequel, a
series, a director who reuses people, a studio ensemble. One shared actor is
weak evidence, because working actors appear in many films. Several at once is
not a coincidence.

## Choosing the threshold

Precision by threshold on train, credited cast:

| k | Precision | Gain | Pairs returned |
|---|---|---|---|
| 1 | 73.2% | | 89,982 |
| 2 | 84.7% | +11.5 | 9,922 |
| **3** | **91.8%** | **+7.1** | **2,934** |
| 4 | 94.8% | +3.0 | 1,422 |
| 5 | 95.2% | +0.4 | 914 |

**Why 3 and not 2?** +7.1 points, and the last big step in the curve.

**Why not 4?** +3.0 points for half the volume. The gain has already collapsed,
and 3 returns twice as many pairs.

**Why not higher?** Above 8 shared actors precision reaches 100%, but on 118
rated pairs or fewer. Pairs sharing that many actors are almost always sequels
from one series, which the class always tagged good. Perfect precision on a
tiny sample is not evidence, which is why volume is reported next to precision
everywhere.

## Data quality, and what it buys

Role names that are function labels rather than characters were removed before
the model ran. `build_credited_roles.sql` cuts role names appearing in 38 or
more distinct movies. 38 is the boundary: at 38 the band holds Man and
Newscaster, both job titles, nothing sits at 37, and at 36 it holds Tony, a
real character. A cut at 39 would keep two labels; a cut at 36 would delete a
character. Three given names appear well above the cut and are kept by name.

Effect on precision:

| k | Raw cast | Credited cast | Gain |
|---|---|---|---|
| 2 | 74.8% | 84.7% | +9.9 |
| 3 | 85.1% | 91.8% | +6.7 |
| 4 | 89.4% | 94.8% | +5.4 |
| 5 | 91.7% | 95.2% | +3.5 |

The filter improves precision at every threshold from 2 up. **At the chosen
threshold it is worth 6.7 points.**

It is not free. 13,212 of 84,232 role rows are removed, 15.7%: 5,349 blank
roles and 7,863 generic labels. Movies with any cast drop from 3,019 to 2,548,
so 471 films lose their entire cast and cannot be reached by this model.

## Against Model 4

Model 2 asks how many actors two films share and needs 3 to be reliable. Model
4 asks whether the shared actor is a star, and one is enough. They are
different questions, and the two models must not be read as one model twice.
On this data Model 2 is the stronger of the pair, 91.8% against 73.0%.

## Note on recall

13.9% on train and 12.0% on test. Low by design. Precision is the metric this
project optimises, and every model in the set accepts low recall to get it.

## Files

| File | What it does |
|---|---|
| `build_credited_roles.sql` | Builds the filtered cast table. Run this first |
| `final_query.sql` | The tuned model and its candidate table |
| `common_cast.py` | Sweeps k over the ground truth |
