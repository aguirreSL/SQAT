# SQAT test suite

Automated tests for the SQAT psychoacoustic metrics, built on `matlab.unittest`.

```matlab
cd test
run_all_tests                      % everything
run_all_tests('Name', '*anchor*')  % one class
```

or headlessly:

```sh
matlab -batch "cd test; run_all_tests"
```

`run_all_tests` bootstraps `startup_SQAT` itself, so it works from a clean session.
Coverage today is `Loudness_ISO532_1` only; the runner name is aspirational.

## This is verification, not validation

The two words are not interchangeable, and the distinction matters for a scientific
reference codebase.

| | asks | referent |
| --- | --- | --- |
| **Verification** | "are we solving the equations right?" | the mathematical description of the model |
| **Validation** | "are we solving the right equations?" | **the real world** — requires experimental data |

Everything in this folder is **verification**. Comparing SQAT against ISO 532-1's
reference implementation establishes that the code computes the standard's model
correctly. It says nothing about whether the Zwicker model predicts what a listener
actually hears.

**Validating** a loudness model means comparing its predictions against listening
tests with human participants. That was done by the models' original authors —
Zwicker's magnitude-estimation experiments, Daniel & Weber for roughness, Osses et
al. for fluctuation strength. SQAT *inherits* that validation; it does not perform
it. Do not read "all tests pass" as "the number matches perception."

(The `validation/` folder at the repo root is named from the conformity-assessment
tradition, where ISO 9000 defines validation as confirming fitness for an intended
use. Both readings are defensible; note that the prose inside those READMEs already
says "used to **verify** the loudness implementation".)

## What is here

| file | purpose |
| --- | --- |
| `tLoudness_ISO532_1_anchor.m` | Self-contained checks against definitional and published values. No external data; runs in seconds. |
| `tLoudness_ISO532_1_reference.m` | Code-to-code verification against the ISO 532-1:2017 Annex A.4 reference implementation. |
| `bench_Loudness_ISO532_1.m` | Wall-clock benchmark. Not a test — prints a table. |
| `golden/` | Reference results produced by the ISO reference C. Committed. |
| `tools/` | The oracle used to regenerate `golden/`. |

## Oracle strength, and the limits of this suite

Not all oracles are equally trustworthy. Ranked strongest first (after Oberkampf &
Roy, *Verification and Validation in Scientific Computing*):

1. **Exact / definitional results.** `tLoudness_ISO532_1_anchor` lives here: a 1 kHz
   tone at 40 dB SPL is 1 sone *by definition of the sone*, and the Annex B.2 level
   vector is published as 83.296 sone.
2. Manufactured solutions — not applicable to a table-driven standard.
3. Highly accurate benchmark results.
4. **Code-to-code comparison.** `tLoudness_ISO532_1_reference` lives here — the
   weakest tier.

**Be honest about tier 4.** Code-to-code comparison detects *differences*, never
*shared* errors. If the ISO reference C is wrong, this suite is wrong with it, in
exactly the same way, and reports success. This is not hypothetical: the reference
implementation contains an out-of-bounds read of `RNS[18]` in `f_calc_slopes`, and
declares its `double` tables with single-precision literals (`0.9f`, `0.1f`). The
golden data inherits whatever those do.

The mitigation is the anchor class — a small number of tier-1 checks that are
independent of the reference implementation. Most of the suite is tier 4; treat a
green run as "SQAT agrees with the reference", not as "SQAT is correct".

## Two levels of assertion

`tLoudness_ISO532_1_reference` checks each signal twice:

- **`AbsTol`** — the conformance bound. Agreement with the reference implementation
  must be within 0.02 sone.
- **`MaxDevAchieved`** — a **characterisation** of the deviation actually achieved
  today, per signal, plus a small slack.

The second exists because the first is weak on its own. Most signals currently agree
with the reference *exactly*, so a change could degrade one by four orders of
magnitude and still sit comfortably inside `AbsTol`. Pinning the achieved value turns
that silent degradation into a failure.

`MaxDevAchieved` records current behaviour; it is not a statement about correctness.
Update it only when a change is understood to *improve* agreement. Never relax it to
make a regression pass.

## Coverage

Verified: free and diffuse field; stationary from levels, stationary from audio, and
time-varying methods; `time_skip` at zero and non-zero; total loudness for all 25 ISO
test signals; specific loudness both as the stationary 240-band pattern (Annex B.3)
and as `N'(t)` at the single Bark band the standard tabulates per time-varying signal
(Annex B.4); resampling from 44.1 and 32 kHz; and the structural invariant that the
temporal weighting is applied to total loudness only, never to specific loudness.

Not covered: the other metrics; `Loudness_ISO532_1_from_wavfile`; the plotting paths.

## Test data

`tLoudness_ISO532_1_reference` needs the ISO test signals, which are not
redistributable here. Download the dataset from
<https://doi.org/10.5281/zenodo.7933206> and place the `validation_SQAT_v1_0` folder
inside `sound_files/`. Without it those tests report as **skipped**, not failed; the
anchor tests still run.

## Regenerating the golden data

Only needed if the oracle or the signal set changes — the CSVs are committed.

```sh
cd test/tools
make ISO_SRC="/path/to/ISO 532-1 - Program etc/Annex A.4/ISO_532-1_LIB"
ISO_DIR="/path/to/ISO 532-1 - Program etc" ./gen_golden.sh
```

The ISO 532-1:2017 Annex A.4 reference sources are **not** vendored: they ship with
the standard and are not ours to redistribute. `tools/iso532_oracle.c` is a thin
driver around them — it reads a WAV, applies the same calibration as
`utilities/calibrate.m`, calls the unmodified reference library, and writes CSV.
Time-varying results are emitted on the 500 Hz grid the reference program itself
reports on, matching `OUT.time`.

## Benchmarking

```matlab
cd test
bench_Loudness_ISO532_1        % time-varying signals 6-25
```

To compare two revisions, run it on each and compare the totals. If the revision you
are comparing against predates `test/`, check out just the metric so the harness stays
in place:

```sh
git checkout <rev> -- psychoacoustic_metrics/
matlab -batch "cd test; bench_Loudness_ISO532_1"
git checkout HEAD -- psychoacoustic_metrics/
```

Timing is deliberately kept out of the test suite: wall-clock assertions are flaky
across machines and would fail for reasons unrelated to the code. Correctness is
asserted; speed is measured.

## Adding tests for other metrics

Name new files `t<Something>.m` and they are picked up automatically. Prefer an oracle
that is independent of the implementation under test — a reference implementation, a
closed-form result, or a documented invariant — over a snapshot of current behaviour,
which only proves the code has not changed.
