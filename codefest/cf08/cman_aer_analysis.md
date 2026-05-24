# CF08 CMAN - AER bandwidth analysis

## Tasks
1. R = N * f = 1024 spikes * 50Hz = 51200 spikes/second
2. B = R * 20 = 51200 * 20 = 1.024 Mbit/s 
3. Any of the buses can sustain the mean rate. When choosing lowest complexity, I would choose SPI. It also gives significant headroom above the needed rate, and could be run at a low frequency.
4. (1024 * 20) * 0.25 = 5120. 5120 / 1ms = 5.12 Mbit/s. SPI is more than capable of absorbing this burst, as long as the clock frequency is high enough to support it.
5. Frame-based bandwidth = (1024 * 1 bit) / 1ms = 1.024 Mbit/s

This is the same as the AER value. So, mean ratio = 1, which also implies the crossover frequency is f=50Hz. This then implies AER is the right choice at f or lower frequencies, when the overhead of the AER format can be supported for sparse spikes.
