# Hardware benchmark clock inputs

These files preserve the clock and memory inputs used for the controlled
0.2.0-to-0.3.0 attached-device comparison. They are evidence inputs, not a
general AtomVM board-support matrix.

| File | Target | CPU clock |
| :--- | :--- | ---: |
| `esp32-s3-n16r8-240mhz.sdkconfig.defaults` | ESP32-S3, 16 MiB DIO flash, 8 MiB octal PSRAM | 240 MHz |
| `waveshare-n32r16v-240mhz.sdkconfig.defaults` | WaveShare ESP32-S3-DEV-KIT-N32R16V, 32 MiB OPI/DTR flash, 16 MiB octal PSRAM | 240 MHz |
| `rp2040-133mhz.cmake` | RP2040 B2 | 133 MHz |

Use the appropriate ESP file as the ESP-IDF `sdkconfig.defaults` input before
configuring a clean AtomVM ESP32-S3 build. Apply the RP2040 file as the initial
CMake cache input so the C, C++, and assembler invocations all receive the
same clock definitions:

```bash
cmake -C /path/to/rp2040-133mhz.cmake ...
```

The release measurement additionally pins the exact AtomVM, ESP-IDF/Pico SDK,
benchmark pack, device identity, run order, warmup, and iteration counts. See
the [0.3.0 validation report](../../docs/benchmarks/0.3.0.md) for those
identities and results.

Do not compare captures from different physical devices or silently apply
these clocks to older evidence. Existing valid captures should be processed
into documentation without rerunning the benchmark.
