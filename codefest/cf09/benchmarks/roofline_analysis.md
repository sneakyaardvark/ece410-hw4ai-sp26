# CF09 Task 9 — Roofline analysis

**Where it landed (measured).** The accelerator achieves 0.266 GSynOps/s at the
10%-sparsity operating point. Dividing by the 0.40 GB/s on-chip bandwidth ceiling
gives an effective arithmetic intensity of 0.66 SynOp/byte, placing the point
directly on the bandwidth roof.

**Where I expected it.** The C1 analysis bounded kernel AI at 0.45–0.83
SynOp/byte, both left of the 1.0 ridge, so I expected a memory-bound design
limited by on-chip SRAM bandwidth.

**Gap diagnosis.** There is essentially no gap to the bandwidth roof — the
design runs at its memory-bandwidth limit, exactly as predicted. It reaches only
66% of the 0.40 GSynOps/s compute ceiling, but that shortfall is the expected
consequence of being memory-bound, not wasted compute. The measured AI (0.66)
exceeding the no-reuse bound (0.45) confirms partial weight reuse. The
highest-leverage improvement is raising arithmetic intensity (wider SRAM fetch /
more reuse per byte) to push the point up the sloped roof toward the ridge.
