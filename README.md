# DEPO Benchmarking Scripts

This repository contains a suite of automation and management scripts for orchestrating [DEPO](https://projects.task.gda.pl/akrz/split) targeting [TorchBench](https://kask.eti.pg.gda.pl/gitlab/grzkoszc/torchbench-caise) benchmarks in a sudo-restricted environment.

---

## Recquired privileges

The user does not have general `sudo` root privileges but still needs elevated privileges to run the DEPO binary located in `~/local/bin/`.

---

## Step-by-Step Flow & Usage

### 1. Build and Setup DEPO
Clone compile and set up the DEPO binary, dependencies (Boost, spdlog, yaml-cpp, Graphviz), the custom GPU kernel counting injection library, local `/tmp` structures, and symlinks.
```bash
./build_depo.sh
```

### 2. Build the Benchmarks
Clone the `torchbench-caise` repository and build the Docker suite containing the benchmark models (`resnet152`, `opacus_cifar10`, `hf_Bert`):
```bash
./build_benchmarks.sh
```

### 3. Run a Single Validation Test
To verify that GPU kernel counting and metrics reporting are functioning correctly:
```bash
sudo ~/local/bin/DEPO ~/depo-scripts/run_single_test.sh
```
*Verify that `instr[-]` counters increase and active power increases.*

### 4. Run the Full Experiment Matrix
To run the automated experiment suite across different SMA test phase periods and tuning intervals:
* **With Tuning**:
  ```bash
  WINDOW_FILTER="200 400" PERIOD_FILTER="10 20" ./run_experiments.sh
  ```
* **Without Tuning (No-Tuning Baseline)**:
  ```bash
  ./run_experiments_no_tuning.sh
  ```
*Note: If a results folder of the same name is already present, the scripts will automatically delete it and overwrite the results instead of skipping.*

### 5. Cleaning Up Results
To review and clean up result folders (which are owned by root but modified/removed using the privileged helper):
```bash
./cleanup_results.sh
```

### 6. Emergency Stop
It is not recomended to stop a sudo process when not having full sudo privileges. As a last resort, you can use this script to hopefully stop all background DEPO processes:
```bash
./kill_depo.sh
```
