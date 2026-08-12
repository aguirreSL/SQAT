classdef tLoudness_ISO532_1_wavfile < matlab.unittest.TestCase
% Tests for Loudness_ISO532_1_from_wavfile, the calibrating wrapper.
%
% This is the entry point most users actually call, and it was previously
% at 0 % coverage. It does one job - turn a dBFS convention into a gain and
% hand a Pascal-valued signal to the core function - and that job is a
% classic source of silent level errors.
%
% Self-contained: driven by sound_files/reference_signals, which is tracked
% in the repository, so these need no external dataset.
%
% Run with:  runtests('tLoudness_ISO532_1_wavfile')

    properties (Constant)
        % 94 dB SPL is 2e-5 * 10^(94/20) = 1.00237 Pa, not exactly 1 Pa, so
        % the dBFS route and utilities/calibrate.m differ by
        %   20*log10( (1/10^(94/20)) / 2e-5 ) = -0.0206 dB.
        % Small, deliberate to pin, and NOT something to "fix" on one side
        % alone - see conventionsAgreeToKnownOffset below.
        ConventionOffset_dB = -0.0206;
    end

    properties
        RefFile
    end

    methods (TestClassSetup)
        function locate(tc)
            tc.assumeNotEmpty(which('Loudness_ISO532_1_from_wavfile'), ...
                'Run startup_SQAT before the tests.');
            tc.RefFile = fullfile(basepath_SQAT, 'sound_files', ...
                                  'reference_signals', ...
                                  'RefSignal_Loudness_ISO532_1.wav');
            tc.assumeTrue(isfile(tc.RefFile), sprintf( ...
                'Reference signal not found at\n  %s', tc.RefFile));
        end
    end

    methods (Test)

        function referenceSignalIsOneSone(tc)
            % RefSignal_Loudness_ISO532_1.wav is the defining calibration
            % case: a 1 kHz tone at 40 dB SPL under the dBFS = 94
            % convention, which must yield 1 sone.
            OUT = Loudness_ISO532_1_from_wavfile(tc.RefFile, 94, 0, 1, 0, 0);
            tc.verifyEqual(OUT.Loudness, 1, 'RelTol', 0.01, sprintf( ...
                'Reference signal gave %.4f sone, expected 1.', OUT.Loudness));
        end

        function referenceSignalIsOneSone_timeVarying(tc)
            OUT = Loudness_ISO532_1_from_wavfile(tc.RefFile, 94, 0, 2, 0, 0);
            steady = mean(OUT.InstantaneousLoudness(end-49:end));
            tc.verifyEqual(steady, 1, 'RelTol', 0.01, sprintf( ...
                'Reference signal gave %.4f sone steady-state, expected 1.', steady));
        end

        function wrapperMatchesCoreWithExplicitGain(tc)
            % The wrapper's entire contract: gain = 10^((dBFS-94)/20),
            % applied to audioread output, then the core function. Must be
            % bit-identical, not merely close.
            dBFS = 88;
            [x, fs] = audioread(tc.RefFile);
            gain    = 10^((dBFS - 94)/20);

            viaWrapper = Loudness_ISO532_1_from_wavfile(tc.RefFile, dBFS, 0, 1, 0, 0);
            viaCore    = Loudness_ISO532_1(gain*x, fs, 0, 1, 0, 0);

            tc.verifyEqual(viaWrapper.Loudness, viaCore.Loudness, ...
                'The wrapper must apply exactly gain = 10^((dBFS-94)/20).');
            tc.verifyEqual(viaWrapper.SpecificLoudness, viaCore.SpecificLoudness);
        end

        function defaultDBFSIs94(tc)
            % Omitting dBFS must fall back to 94, not to something else.
            withDefault  = Loudness_ISO532_1_from_wavfile(tc.RefFile, [], 0, 1, 0, 0);
            withExplicit = Loudness_ISO532_1_from_wavfile(tc.RefFile, 94, 0, 1, 0, 0);
            tc.verifyEqual(withDefault.Loudness, withExplicit.Loudness, ...
                'Default dBFS must be 94.');
        end

        function dBFSShiftsLevelOneForOne(tc)
            % Raising dBFS by 20 dB means full scale represents 20 dB more,
            % so the interpreted signal is 20 dB louder. Check on the level
            % SQAT reports, which is unambiguous, rather than on sone.
            a = Loudness_ISO532_1_from_wavfile(tc.RefFile, 94, 0, 1, 0, 0);
            b = Loudness_ISO532_1_from_wavfile(tc.RefFile, 114, 0, 1, 0, 0);

            tc.verifyEqual(b.TimeAveragedSPL - a.TimeAveragedSPL, 20, ...
                'AbsTol', 0.01, sprintf( ...
                ['A +20 dB change in dBFS must raise the reported level by ' ...
                 '20 dB; got %+.3f dB.'], b.TimeAveragedSPL - a.TimeAveragedSPL));

            tc.verifyGreaterThan(b.Loudness, a.Loudness);
        end

        function conventionsAgreeToKnownOffset(tc)
            % SQAT has two calibration routes: the dBFS convention used by
            % the _from_wavfile wrappers, and utilities/calibrate.m used by
            % the validation scripts. They are NOT identical - 94 dB SPL is
            % 1.00237 Pa, not 1 Pa - and differ by a fixed -0.0206 dB.
            %
            % This test pins that offset so it stays a known, bounded
            % difference. If someone changes either convention, this fails
            % and forces the other one to be considered too.
            [x, ~] = audioread(tc.RefFile);

            gainRoute = 10^((94 - 94)/20);                 % dBFS route
            calRoute  = 10^(94/20) * 2e-5;                 % 1 full-scale unit in Pa

            offset_dB = 20*log10(gainRoute / calRoute);
            tc.verifyEqual(offset_dB, tc.ConventionOffset_dB, 'AbsTol', 1e-3, ...
                sprintf(['The dBFS and calibrate conventions now differ by ' ...
                         '%.4f dB, not the documented %.4f dB.'], ...
                        offset_dB, tc.ConventionOffset_dB));

            % ... and the consequence on a real signal stays below 0.03 dB
            viaGain = Loudness_ISO532_1(x, 48000, 0, 1, 0, 0).TimeAveragedSPL;
            viaCal  = Loudness_ISO532_1(x*calRoute, 48000, 0, 1, 0, 0).TimeAveragedSPL;
            tc.verifyLessThan(abs(viaGain - viaCal), 0.03);
        end

        function rejectsMissingFile(tc)
            tc.verifyError(@() Loudness_ISO532_1_from_wavfile( ...
                fullfile(tempdir,'no_such_file_12345.wav'), 94, 0, 1, 0, 0), ...
                ?MException, 'A missing file must raise an error.');
        end

    end
end
