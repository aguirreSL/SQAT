classdef tLoudness_ISO532_1_reference < matlab.unittest.TestCase
% Code verification of Loudness_ISO532_1 against the ISO 532-1:2017
% Annex A.4 reference implementation.
%
% VERIFICATION, not validation. These tests ask "does the implementation
% solve the equations correctly", by comparing against an independent
% implementation of the same model. They say nothing about whether the
% Zwicker model predicts human loudness perception - that is validation,
% it requires listening tests, and it was done by the model's authors, not
% here. See test/README.md.
%
% The comparison is made on the full loudness time series, sample by
% sample, rather than on single-value statistics (Nmax, N5). The scalar
% comparison is far too weak: it once reported agreement for seven of
% eight synthetic signals while all twenty time-varying signals deviated
% from the reference by 3-18 % of peak loudness.
%
% Requires the ISO test signals from Zenodo (doi 10.5281/zenodo.7933206)
% under sound_files/validation_SQAT_v1_0/Loudness_ISO532_1. Tests are
% skipped, not failed, when the signals are absent.
%
% Run with:  runtests('tLoudness_ISO532_1_reference')

    properties (Constant)
        % Conformance bound: largest tolerated deviation from the reference
        % implementation, in sone. The reference is deterministic and SQAT
        % should track it far more closely than this; it is not a
        % perceptual tolerance. (ISO's own perceptual budget is +-5 % or
        % +-0.1 sone, extended to +-10 % / +-0.2 for at most 1 % of
        % samples - see validation/Loudness_ISO532_1/README.md.)
        AbsTol = 0.02;

        % Same, for specific loudness in sone/Bark.
        AbsTolSpecific = 0.02;

        % CHARACTERISATION, not a correctness criterion. This records the
        % deviation from the reference actually achieved today, per signal,
        % so that a change which degrades agreement fails even though it
        % still sits inside AbsTol. Most signals currently agree exactly,
        % so AbsTol alone would let a four-order-of-magnitude regression
        % through unnoticed.
        %
        % Update only when a change is understood to IMPROVE agreement.
        % Never relax it to make a regression pass.
        MaxDevAchieved = [ ...
            0 0 0 0 0, ...                                  % 1-5 (stationary)
            0.016852, 0, 0, 0.003549, 0, ...                % 6-10
            0, 0.000328, 0, 0.007155, 0.005293, ...         % 11-15
            0.000204, 0.001748, 0.002967, 0.002601, ...     % 16-19
            0.001551, 0.000416, 0, 0.001529, 0.003530, ...  % 20-24
            0.000001];                                      % 25

        % Slack over MaxDevAchieved, absorbing platform and version noise
        % while staying far tighter than AbsTol. Reverting any one of the
        % ISO 532-1 conformance fixes moves a signal by much more.
        RegressionSlack = 1e-4;
    end

    properties
        SoundDir
        GoldenDir
        CalSignal
    end

    properties (TestParameter)
        % Annex B.4 synthetic (6-13) and Annex B.5 technical (14-25)
        tvSignal   = num2cell(6:25);
        % Annex B.3 stationary
        statSignal = num2cell(2:5);
        % Signals for which diffuse-field golden data exists
        diffuseSignal = {3, 6, 8, 10, 14};
        % Stationary signals with non-zero time_skip golden data
        skipSignal = {2, 3, 5};
        % Bark band the standard tabulates N'(t) at, per signal (Annex B.4)
        specSignal = struct( ...
            's06', {{6,  2.5}},  's07', {{7,  8.5}},  's08', {{8,  17.5}}, ...
            's09', {{9, 17.5}},  's10', {{10, 8.5}},  's11', {{11, 8.5}}, ...
            's12', {{12, 8.5}},  's13', {{13, 8.5}});
    end

    methods (TestClassSetup)
        function locateData(tc)
            here          = fileparts(mfilename('fullpath'));
            repo          = fileparts(here);
            tc.GoldenDir  = fullfile(here, 'golden');
            tc.SoundDir   = fullfile(repo, 'sound_files', ...
                                     'validation_SQAT_v1_0', 'Loudness_ISO532_1');

            tc.assumeTrue(isfolder(tc.SoundDir), sprintf( ...
                ['ISO test signals not found at\n  %s\n' ...
                 'Download the dataset from doi 10.5281/zenodo.7933206 and ' ...
                 'place validation_SQAT_v1_0 inside sound_files.'], tc.SoundDir));

            calFile = fullfile(tc.SoundDir, 'calibration signal sine 1kHz 60dB.wav');
            tc.assumeTrue(isfile(calFile), ...
                sprintf('Calibration signal not found at\n  %s', calFile));
            tc.CalSignal = audioread(calFile);

            tc.assumeNotEmpty(which('Loudness_ISO532_1'), ...
                'Run startup_SQAT before the tests.');
        end
    end

    methods
        function [insig, fs] = readSignal(tc, num)
            % Resolve "Test signal <num> (...).wav" and calibrate to 60 dB SPL
            d = dir(fullfile(tc.SoundDir, sprintf('Test signal %d (*.wav', num)));
            tc.assumeNotEmpty(d, sprintf('Test signal %d not found.', num));
            f      = fullfile(tc.SoundDir, d(1).name);
            [x, fs] = audioread(f);
            insig   = calibrate(x(:,1), tc.CalSignal, 60);
        end

        function ref = readGolden(tc, name)
            f = fullfile(tc.GoldenDir, name);
            tc.assertTrue(isfile(f), sprintf( ...
                ['Golden data missing: %s\n' ...
                 'Regenerate with: cd test/tools && make && make golden'], f));
            m   = readmatrix(f, 'NumHeaderLines', 1);
            ref = m(:,2);
        end

        function verifySeries(tc, got, ref, tol, label)
            n = min(numel(got), numel(ref));
            tc.assertGreaterThan(n, 0, 'No overlapping samples to compare.');
            d      = got(1:n) - ref(1:n);
            [mx,i] = max(abs(d));
            tc.verifyLessThanOrEqual(mx, tol, sprintf( ...
                ['%s deviates from the ISO 532-1 reference by %.6f at t = %.3f s.\n' ...
                 'mean|d| = %.6f, RMS = %.6f over %d samples.'], ...
                label, mx, (i-1)*2e-3, mean(abs(d)), sqrt(mean(d.^2)), n));
        end
    end

    methods (Test)

        % ---------------------------------------------------- total loudness

        function timeVaryingMatchesReference(tc, tvSignal)
            [insig, fs] = tc.readSignal(tvSignal);
            ref = tc.readGolden(sprintf('sig%02d_timevarying.csv', tvSignal));
            OUT = Loudness_ISO532_1(insig, fs, 0, 2, 0, 0);
            got = OUT.InstantaneousLoudness;

            n      = min(numel(got), numel(ref));
            d      = got(1:n) - ref(1:n);
            [mx,i] = max(abs(d));

            tc.verifyLessThanOrEqual(mx, tc.AbsTol, sprintf( ...
                ['Signal %d deviates from the ISO 532-1 reference by %.5f sone ' ...
                 '(%.2f%% of peak) at t = %.3f s.\n' ...
                 'mean|dN| = %.5f, RMS = %.5f over %d samples.'], ...
                tvSignal, mx, 100*mx/max(ref(1:n)), (i-1)*2e-3, ...
                mean(abs(d)), sqrt(mean(d.^2)), n));

            budget = tc.MaxDevAchieved(tvSignal) + tc.RegressionSlack;
            tc.verifyLessThanOrEqual(mx, budget, sprintf( ...
                ['Signal %d agreement with the reference has REGRESSED: %.6f sone ' ...
                 'now, %.6f before (budget %.6f).\n' ...
                 'This still satisfies the %.3f sone conformance bound, so it is ' ...
                 'a silent degradation rather than an outright failure.'], ...
                tvSignal, mx, tc.MaxDevAchieved(tvSignal), budget, tc.AbsTol));
        end

        function stationaryMatchesReference(tc, statSignal)
            [insig, fs] = tc.readSignal(statSignal);
            ref = tc.readGolden(sprintf('sig%02d_stationary.csv', statSignal));
            OUT = Loudness_ISO532_1(insig, fs, 0, 1, 0, 0);

            tc.verifyEqual(OUT.Loudness, ref(1), 'AbsTol', tc.AbsTol, sprintf( ...
                'Stationary signal %d: got %.5f sone, reference %.5f sone.', ...
                statSignal, OUT.Loudness, ref(1)));
        end

        function levelInputMatchesReference(tc)
            ref = tc.readGolden('sig01_stationary_levels.csv');
            OUT = Loudness_ISO532_1(tc.annexB2Levels(), 1, 0, 0, 0, 0);
            tc.verifyEqual(OUT.Loudness, ref(1), 'AbsTol', tc.AbsTol, sprintf( ...
                'Level input: got %.5f sone, reference %.5f sone.', ...
                OUT.Loudness, ref(1)));
        end

        % ------------------------------------------------- specific loudness
        % Issue #44: specific loudness had no verification at all. The
        % standard tabulates N'(t) at one Bark band per time-varying signal
        % (Annex B.4) and the full 240-band pattern for stationary signals
        % (Annex B.3). Cover both.

        function specificLoudnessTimeVaryingMatchesReference(tc, specSignal)
            num  = specSignal{1};
            bark = specSignal{2};

            [insig, fs] = tc.readSignal(num);
            ref = tc.readGolden(sprintf('sig%02d_specific_%.1fBark.csv', num, bark));
            OUT = Loudness_ISO532_1(insig, fs, 0, 2, 0, 0);

            [~, iz] = min(abs(OUT.barkAxis - bark));
            tc.verifySeries(OUT.InstantaneousSpecificLoudness(:,iz), ref, ...
                tc.AbsTolSpecific, ...
                sprintf('Signal %d specific loudness at %.1f Bark', num, bark));
        end

        function specificLoudnessPatternMatchesReference(tc, statSignal)
            [insig, fs] = tc.readSignal(statSignal);
            ref = tc.readGolden(sprintf('sig%02d_stationary_pattern.csv', statSignal));
            OUT = Loudness_ISO532_1(insig, fs, 0, 1, 0, 0);

            tc.verifySeries(OUT.SpecificLoudness(:), ref, tc.AbsTolSpecific, ...
                sprintf('Signal %d stationary specific loudness pattern', statSignal));
        end

        function levelInputPatternMatchesReference(tc)
            ref = tc.readGolden('sig01_stationary_levels_pattern.csv');
            OUT = Loudness_ISO532_1(tc.annexB2Levels(), 1, 0, 0, 0, 0);
            tc.verifySeries(OUT.SpecificLoudness(:), ref, tc.AbsTolSpecific, ...
                'Level input specific loudness pattern');
        end

        % ------------------------------------------------------ diffuse field
        % field = 1 selects the DDF correction table (20 entries), which was
        % entirely uncovered before.

        function diffuseFieldMatchesReference(tc, diffuseSignal)
            [insig, fs] = tc.readSignal(diffuseSignal);
            if diffuseSignal <= 5
                ref = tc.readGolden(sprintf('sig%02d_stationary_diffuse.csv', diffuseSignal));
                OUT = Loudness_ISO532_1(insig, fs, 1, 1, 0, 0);
                tc.verifyEqual(OUT.Loudness, ref(1), 'AbsTol', tc.AbsTol, sprintf( ...
                    'Diffuse field, stationary signal %d: got %.5f, reference %.5f.', ...
                    diffuseSignal, OUT.Loudness, ref(1)));
            else
                ref = tc.readGolden(sprintf('sig%02d_timevarying_diffuse.csv', diffuseSignal));
                OUT = Loudness_ISO532_1(insig, fs, 1, 2, 0, 0);
                tc.verifySeries(OUT.InstantaneousLoudness, ref, tc.AbsTol, ...
                    sprintf('Diffuse field, signal %d', diffuseSignal));
            end
        end

        function diffuseFieldDiffersFromFreeField(tc)
            % Guard against field being silently ignored: the DDF table is
            % non-zero above 2 Bark, so the two fields must not coincide.
            ref = tc.readGolden('sig01_stationary_levels.csv');
            dif = tc.readGolden('sig01_stationary_levels_diffuse.csv');
            tc.assumeNotEqual(ref(1), dif(1), ...
                'Reference itself gives identical free/diffuse results - bad test signal.');

            lv    = tc.annexB2Levels();
            free  = Loudness_ISO532_1(lv, 1, 0, 0, 0, 0).Loudness;
            diffu = Loudness_ISO532_1(lv, 1, 1, 0, 0, 0).Loudness;

            tc.verifyNotEqual(free, diffu, ...
                'Free and diffuse field gave identical loudness - field is being ignored.');
            tc.verifyEqual(diffu, dif(1), 'AbsTol', tc.AbsTol);
        end

        % --------------------------------------------------------- time_skip
        % time_skip changes which part of the signal feeds the stationary
        % level calculation. Previously untested at any non-zero value.

        function timeSkipMatchesReference(tc, skipSignal)
            [insig, fs] = tc.readSignal(skipSignal);
            ref = tc.readGolden(sprintf('sig%02d_stationary_skip0p2.csv', skipSignal));
            OUT = Loudness_ISO532_1(insig, fs, 0, 1, 0.2, 0);

            tc.verifyEqual(OUT.Loudness, ref(1), 'AbsTol', tc.AbsTol, sprintf( ...
                ['Stationary signal %d with time_skip = 0.2 s: got %.5f sone, ' ...
                 'reference %.5f sone (difference %+.5f).'], ...
                skipSignal, OUT.Loudness, ref(1), OUT.Loudness - ref(1)));
        end

    end

    methods (Static)
        function lv = annexB2Levels()
            % Annex B.2 test signal 1: 28 unweighted third-octave levels
            lv = [-60 -60 78 79 89 72 80 89 75 87 85 79 86 80 ...
                   71  70 72 71 72 74 69 65 67 77 68 58 45 30];
        end
    end
end
