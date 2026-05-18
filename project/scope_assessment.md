# Codefest 7 / M3 Project Assessment

I am mostly happy with the results. The SRAM issues, as described in `codefest/cf07/synth/m3_plan.md`, must be fixed.
The slack time is unacceptable, and will severely penalize performance, if it would work at all. Otherwise, I anticipate 
several changes needed to improve performance, including replacing the naive MAC array. I have already been working on a replacement module.
This won't reduce the area (it will already be reduced considerably by implementing an SRAM macro), but will increase compute density.
The overall scope stays the same. I have already tempered myself by starting small and making incremental improvements as possible.
Taking time to make these fixes means I may not reach my stretch goals (such as sparse spikes), which is acceptable.
