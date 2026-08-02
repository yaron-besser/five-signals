"""Rebuild Figure 5: train against test precision for all six, as a PNG."""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

MODELS = ["Model 1\nStyle, Era", "Model 2\nCommon Cast", "Model 3\nDirector DNA",
          "Model 4\nShared Star", "Model 5\nCollaborative", "All five\ncombined"]
TRAIN = [81.8, 91.8, 93.4, 73.0, 90.9, 88.7]
TEST = [59.8, 68.6, 59.4, 64.8, 76.8, 82.4]

x = np.arange(len(MODELS))
w = 0.38
fig, ax = plt.subplots(figsize=(10, 5.5))

ax.bar(x - w/2, TRAIN, w, label="train", color="#a8c4e0")
ax.bar(x + w/2, TEST, w, label="test", color="#1f3a5f")

for i, (tr, te) in enumerate(zip(TRAIN, TEST)):
    ax.text(i - w/2, tr + 0.8, f"{tr}", ha="center", fontsize=9)
    ax.text(i + w/2, te + 0.8, f"{te}", ha="center", fontsize=9)

ax.axhline(51.3, color="#c0392b", linestyle="--", linewidth=1)
ax.axhline(49.1, color="#c0392b", linestyle=":", linewidth=1)
ax.text(-0.45, 52.2, "baselines 51.3% train, 49.1% test",
        fontsize=8, color="#c0392b")

ax.set_xticks(x)
ax.set_xticklabels(MODELS, fontsize=9)
ax.set_ylabel("Precision (%)")
ax.set_ylim(40, 100)
ax.set_title("Every model falls from train to test. The combination falls least.",
             fontsize=12, color="#1f3a5f", weight="bold")
ax.legend(loc="upper left", frameon=False)
ax.spines[["top", "right"]].set_visible(False)

plt.tight_layout()
out = "/Users/yaronbesser/Desktop/five_signals/figures/summary_train_vs_test.png"
plt.savefig(out, dpi=150)
print("written", out)
