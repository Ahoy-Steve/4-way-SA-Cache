# 4-Way Set-Associative Cache

A 32 KiB, 4-way set-associative cache modelled in Verilog, with a **write-back /
write-allocate** policy and **true LRU** replacement. The project includes the cache
controller, a main-memory model, a self-checking testbench, and a statistics monitor that
reports hits, misses and references.

---

## Specification

| Parameter          | Value                        |
|--------------------|------------------------------|
| Cache size         | 32 KiB                       |
| Associativity      | 4-way set associative        |
| Block size         | 8 words (256 bits)           |
| Word size          | 32 bits                      |
| Main memory        | 8 MiB                        |
| Addressable unit   | word                         |
| Write policy       | write-back, write-allocate   |
| Replacement policy | LRU                          |

**Derived geometry:** 32 KiB ÷ 4 B = 8192 words → 1024 blocks → **256 sets**.
The 21-bit word address splits into **tag [20:11] / index [10:3] / offset [2:0]**
(10 / 8 / 3 bits). Main memory holds `2^18` blocks and is accessed by an 18-bit block
address.

---

## Files

| File                       | Description                                                   |
|----------------------------|---------------------------------------------------------------|
| `cache_controller.v`       | The cache: storage arrays + FSM (hit/miss, write-back, write-allocate, LRU). |
| `memory.v`                 | 8 MiB main-memory model (`2^18` blocks × 256 bits).          |
| `cache_stats.v`            | Passive monitor: counts references, hits and misses.         |
| `tb_cache.v`               | Self-checking testbench (drives stimulus, verifies results). |
| `defs.vh`                  | Shared definitions header.                                   |
| `run_cache_controller.txt` | ModelSim/Questa do-script to compile, simulate and view waves.|

---

## How to run (ModelSim / Questa)

From the simulator's command line, in the project directory:

```tcl
do run_cache_controller.txt
```

The script creates the `work` library, compiles all sources (including
`cache_stats.v`), launches the simulation, sets up the waveform, and runs to completion.

To compile and run manually instead:

```tcl
vlib work
vlog memory.v cache_controller.v cache_stats.v tb_cache.v
vsim -voptargs="+acc" work.tb_cache
run -all
```

---

## Expected output

The testbench is **self-checking**. At the end of the run the Transcript shows the
statistics report and a pass/fail summary:

```
----------------------------------------
 CACHE STATISTICS
----------------------------------------
   References : 17
   Hits       : 8
   Misses     : 9
   Hit rate   : 47.06 %
----------------------------------------
========================================
 RESULT: ALL CHECKS PASSED
========================================
```

The three statistics counters are also added to the Wave window under the
**"Statistics"** divider.

---

## What the tests verify

- **Write-allocate** on a write miss.
- **Read hit / read miss**, with read data sampled in the correct (`READ_HIT`) cycle.
- **Write hit** with no memory traffic.
- **LRU replacement** — five blocks map to the same set; one is re-touched before an
  eviction is forced, so the test confirms the cache evicts the *least recently used* line
  and not the oldest-loaded one (i.e. LRU, not FIFO).
- **Write-back** — evicted dirty blocks are read back later and return their correct data
  from main memory, proving the dirty lines were written back.

---

## Notes

- `cache_stats.v` is a passive monitor and does not drive any cache signal; it can be
  added or removed without affecting behaviour.
- The data output `cdout` is valid only during the `READ_HIT` cycle; the testbench samples
  it accordingly. Registering `cdout` together with a data-valid strobe is a natural future
  improvement.