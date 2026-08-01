# figures

The charts used in the report. Every plotted point comes from the tuning grids
recorded in the model folders.

| File | What it shows |
|---|---|
| `model_1_curve_grid.png` | Five year windows sitting on top of each other, which is the finding: only the genre count moves precision |
| `model_2_curve_raw.png` | Model 2 on the raw cast |
| `model_2_curve_credited.png` | The same on the cleaned cast. The gap between the two is what the data quality layer bought |
| `model_3_curve_train.png` | Precision climbing while the evidence behind it thins out |
| `model_5_curve_grid.png` | One support floor removes the artefact, further floors do not help |

Model 4 has no threshold to tune, so it has no curve. The train against test
summary chart in the report was produced from the final metrics table.

Regenerate any of these by running the tuning script in the matching model
folder.
