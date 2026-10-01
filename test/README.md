# Tests of SQAT

The tests use the unit test framework of MATLAB (`functiontests`) and need
nothing besides SQAT and the Signal Processing Toolbox, which the metrics
use. Every criterion comes from a source named in the comment of the test: a
standard, a paper, the help of the function, or, where no published value
exists, a tolerance set just above the measured error and marked as ours.

| Folder | What it tests | Time |
|---|---|---:|
| `unit/` | one function at a time: the helpers in `utilities/`, `sound_level_meter/` and `EPNL_FAR_Part36/helper/`, and every metric on the reference signal of its help, one property from the literature and silence | about 50 s |
| `reference/` | a metric against the published data of its validation, with the criteria of the source | about 15 s |
| `gui/` | the interface in `gui/`: its functions, the calls of the metrics and the windows (see `gui/README.md`) | about 5 min |
| `report/` | no tests: the recorder and the page of the report | |

## Running

From the SQAT root:

```matlab
runtests('test', 'IncludeSubfolders', true)   % everything
runtests('test/unit')                          % one folder
```

A test file is found by folder only when its name ends in `_test` (or
starts with `test`), for example `Do_SLM_test.m`.

## The report

```matlab
addpath('test/report'); sqat_report_build            % everything
addpath('test/report'); sqat_report_build('unit')    % one folder
```

writes `test/report/out/index.html`, one page to open in any browser: the
result of every test, what it checks, its failure output, and the measured
error of every comparison with a reference. A test records a comparison with
`sqat_report_record(metric, case, measured, reference, tolerance)` before it
verifies the same values; the page shows the utilization, the measured error
divided by the allowed error (1 is at the limit).

## Reference data

`reference/Loudness_ISO532_1_reference_test.m` runs the 25 test signals of
ISO 532-1:2017, Annex B. The reference values are in
`validation/Loudness_ISO532_1`; the sound files are the ones of the standard,
free from https://standards.iso.org/iso/532/-1/ed-1/en/ (`ISO 532-1 -
Program etc.zip`). Unzip it into `test/reference/data/ISO 532-1 - Program etc`
(ignored by git), or point the environment variable `SQAT_ISO532_1_DIR` at
the folder. Without them the tests are reported as incomplete.

The reference tests of the roughness (Daniel and Weber, ECMA-418-2), the
fluctuation strength and the sharpness run the scripts of `validation/` on
the sounds of the SQAT v1.0 dataset, Zenodo record 7933206 (CC BY 4.0,
https://doi.org/10.5281/zenodo.7933206), unzipped into
`sound_files/validation_SQAT_v1_0`. Against data of listening tests the
tolerance (17 % or 10 % JND, 0.1 asper) is a hard limit only at the
reference signal: point by point it would reject the models themselves, so
the RMSE of each case is pinned and may only improve, and the points inside
the band are reported (the rule of PRs 60 and 62). The sharpness keeps the
5 % of DIN 45692 as a hard limit.

## Continuous integration

`.github/workflows/tests.yml` runs every night at 03:00 UTC and on demand:
it merges the main of ggrecow/SQAT and the GUI branch of this fork
(feat/sqat-gui), downloads the ISO 532-1 signals, runs
the whole suite on MATLAB R2026a and publishes the report on
https://aguirresl.github.io/SQAT/. When every test passes, the merge is
pushed, so this main follows the upstream one with the tests on top.
