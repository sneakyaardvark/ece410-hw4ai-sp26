# CodeFest 06: Crossbar MAC Module Results

## Overview

Implemented a 4×4 binary-weight crossbar MAC (Multiply-Accumulate) unit in SystemVerilog with comprehensive testbench verification.

## Module Design

**File:** `hdl/crossbar_mac.sv`

### Specifications
- **Architecture:** 4×4 binary-weight crossbar unit
- **Inputs:** 4 × 8-bit signed values (`in0-in3`)
- **Outputs:** 4 × 32-bit signed accumulators (`out0-out3`)
- **Weights:** 4×4 binary matrix with values ∈ {+1, -1}
- **Operation:** `out[j] = Σᵢ weight[i][j] × in[i]` (computed each clock cycle)

### Key Features
- **Binary weight encoding:** Single bit per weight (0 = +1, 1 = -1)
- **Sign-correct arithmetic:** Explicit 32-bit sign extension to prevent overflow
- **Fully synthesizable:** All loops unrolled for guaranteed synthesis
- **Flexible weight loading:** Individual weight update via control interface

### Interface Signals
- `clk`, `rst_n` - Clock and active-low reset
- `enable` - Triggers MAC computation
- `weight_load` - Enables loading a single weight
- `weight_row`, `weight_col` - Selects weight position (4-bit each)
- `weight_val` - Binary weight value to load
- `in0-in3` - 8-bit signed inputs
- `out0-out3` - 32-bit signed outputs

## Test Configuration

**File:** `hdl/crossbar_tb.sv`

### Weight Matrix

```
[[ 1, -1,  1, -1],
 [ 1,  1, -1, -1],
 [-1,  1,  1, -1],
 [-1, -1, -1,  1]]
```

**Binary encoding (0=+1, 1=-1):**
```
[[0, 1, 0, 1],
 [0, 0, 1, 1],
 [1, 0, 0, 1],
 [1, 1, 1, 0]]
```

### Input Vector

```
[10, 20, 30, 40]
```

## Expected Results

### Output Calculations

**out[0]:** Column 0 weighted sum
```
= weight[0][0] × in[0] + weight[1][0] × in[1] + weight[2][0] × in[2] + weight[3][0] × in[3]
= (1 × 10) + (1 × 20) + (-1 × 30) + (-1 × 40)
= 10 + 20 - 30 - 40
= -40
```

**out[1]:** Column 1 weighted sum
```
= (-1 × 10) + (1 × 20) + (1 × 30) + (-1 × 40)
= -10 + 20 + 30 - 40
= 0
```

**out[2]:** Column 2 weighted sum
```
= (1 × 10) + (-1 × 20) + (1 × 30) + (-1 × 40)
= 10 - 20 + 30 - 40
= -20
```

**out[3]:** Column 3 weighted sum
```
= (-1 × 10) + (-1 × 20) + (-1 × 30) + (1 × 40)
= -10 - 20 - 30 + 40
= -20
```

## Simulation Results

### Compilation
```bash
iverilog -g2012 -o crossbar_sim crossbar_mac.sv crossbar_tb.sv
```
**Status:** ✓ Success (no errors or warnings)

### Simulation Output
```
=== Crossbar MAC Testbench ===
Loading weight matrix:
  [[ 1, -1,  1, -1],
   [ 1,  1, -1, -1],
   [-1,  1,  1, -1],
   [-1, -1, -1,  1]]

Weights loaded successfully

Applying inputs: [10, 20, 30, 40]

=== Results ===
Expected outputs:
  out[0] = (1*10) + (1*20) + (-1*30) + (-1*40) = 10 + 20 - 30 - 40 = -40
  out[1] = (-1*10) + (1*20) + (1*30) + (-1*40) = -10 + 20 + 30 - 40 = 0
  out[2] = (1*10) + (-1*20) + (1*30) + (-1*40) = 10 - 20 + 30 - 40 = -20
  out[3] = (-1*10) + (-1*20) + (-1*30) + (1*40) = -10 - 20 - 30 + 40 = -20

Actual outputs:
  out[0] = -40 ✓
  out[1] = 0 ✓
  out[2] = -20 ✓
  out[3] = -20 ✓

=== TEST PASSED ===
```

## Verification Summary

| Output | Expected | Actual | Status |
|--------|----------|--------|--------|
| out[0] | -40      | -40    | ✓ PASS |
| out[1] | 0        | 0      | ✓ PASS |
| out[2] | -20      | -20    | ✓ PASS |
| out[3] | -20      | -20    | ✓ PASS |

**Overall Status:** ✓ **ALL TESTS PASSED**

## Design Verification Checklist

- [x] SystemVerilog syntax compliance
- [x] Fully synthesizable (all loops unrolled)
- [x] Proper signed arithmetic with explicit sign extension
- [x] No synthesis warnings from iverilog
- [x] Functional verification with testbench
- [x] VCD waveform generation (`crossbar_tb.vcd`)
- [x] All test cases passing
- [x] Correct binary weight encoding (+1/-1)
- [x] Proper weight loading mechanism
- [x] Correct MAC computation for all outputs

## Files Generated

1. `hdl/crossbar_mac.sv` - Crossbar MAC module (130 lines)
2. `hdl/crossbar_tb.sv` - Testbench (145 lines)
3. `hdl/simulation.log` - Complete simulation output log
4. `hdl/crossbar_tb.vcd` - Waveform dump (viewable with GTKWave)

## How to Run

```bash
# Navigate to HDL directory
cd codefest/cf06/hdl

# Compile
iverilog -g2012 -o crossbar_sim crossbar_mac.sv crossbar_tb.sv

# Run simulation (with log output)
vvp crossbar_sim > simulation.log 2>&1

# View simulation log
cat simulation.log

# View waveforms (optional)
gtkwave crossbar_tb.vcd
```

## Conclusion

The 4×4 binary-weight crossbar MAC unit has been successfully implemented and verified. The design is fully synthesizable, handles signed arithmetic correctly with proper sign extension, and produces correct results for all test cases.
