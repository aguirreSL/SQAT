function tests = SQAT_GUI_tool_calling_retired(run)
% Tests retired from SQAT_GUI_tool_calling_test.m on 29.10.2026: checks of positions and of
% fine behaviour that broke when a control moved or a detail changed, which
% is no test of the GUI. Kept so that nothing is lost; runtests collects
% nothing from this file. To run them by hand, from the SQAT root:
%   run(SQAT_GUI_tool_calling_retired(true))
if nargin == 0
    tests = [];
    return
end
tests = functiontests(localfunctions);
end

%% Fixtures ----------------------------------------------------------------

function setupOnce(tc)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
tc.applyFixture(matlab.unittest.fixtures.PathFixture(root, 'IncludingSubfolders', true));   % SQAT and gui/, also on a clean MATLAB path
fs = 48000;
t = (0:1/fs:3-1/fs)';
% 1 kHz tone, 60 dB SPL, amplitude-modulated at 4 Hz (roughness and FS > 0)
tc.TestData.x_mono = sqrt(2)*2e-5*10^(60/20) * (1 + 0.5*sin(2*pi*4*t)) .* sin(2*pi*1000*t);
% flyover-like noise burst for EPNL
rng(1);
tc.TestData.x_burst = sqrt(2)*2e-5*10^(80/20) * sin(pi*t/t(end)).^2 .* randn(size(t))/3;
tc.TestData.fs = fs;
end

function teardown(~)
delete(findall(groot, 'Type', 'figure'));
end

%% Running a metric --------------------------------------------------------

function test_sound_level_bands_take_the_chosen_weighting(tc)
% The one-third octave levels are the bands of the signal after the weighting
% chosen for them: Z leaves the 1 kHz band of a tone as it is, A takes a
% 100 Hz tone down by its A-weighting, about 19 dB (IEC 61672-1, Table 3).
fs = 48000; t = (0:2*fs-1)'/fs;
x = sqrt(2) * 2e-5 * 10^(70/20) * sin(2*pi*100*t);
m = SQAT_GUI_metrics;
e = m(strcmp({m.id}, 'Do_SLM'));
p = il_default_params(e);
tc.verifyEqual(p.tob_weight, 'A');                    % as the level, A by default
p.tob_weight = 'Z';
[~, Z] = evalc('e.run(x, fs, p, false)');
p.tob_weight = 'A';
[~, A] = evalc('e.run(x, fs, p, false)');
k = find(abs(Z.TOB_freq - 100) < 1);
tc.verifyEqual(Z.TOB_level(k) - A.TOB_level(k), 19.1, 'AbsTol', 0.2);
% the units follow the weightings: dB SPL unweighted, dBA and dBC weighted
a = SQAT_GUI_extract(A, 'Do_SLM');
tc.verifyEqual(a(strcmp({a.id}, 'level')).ylabel, 'Sound pressure level (dBA)');
tc.verifyEqual(a(strcmp({a.id}, 'tob_level')).ylabel, 'Band level (dBA)');
a = SQAT_GUI_extract(Z, 'Do_SLM');
tc.verifyEqual(a(strcmp({a.id}, 'tob_level')).ylabel, 'Band level (dB SPL)');
end

function test_sound_level_spectrum_of_a_short_signal_takes_a_smaller_window(tc)
% A signal shorter than the window of the FFT degree asked for takes the
% largest power of two that it holds, and the console says so: 0.1 s at
% 48 kHz (4800 samples) gives 4096 points. A signal of one window or more
% keeps the degree and prints nothing.
fs = 48000; n = 2^12; t = (0:4799)'/fs;
f0 = 85 * fs / n;                                     % 996.09 Hz, a bin centre of the 4096 points
x = sqrt(2) * 2e-5 * 10^(60/20) * sin(2*pi*f0*t);
m = SQAT_GUI_metrics;
e = m(strcmp({m.id}, 'Do_SLM'));
p = il_default_params(e);
p.spectrum_weight = 'Z';
[txt, OUT] = evalc('e.run(x, fs, p, false)');
tc.verifySubstring(txt, 'the signal has 4800 samples, FFT of 4096 points used');
tc.verifyEqual(OUT.spectrum_freq, (1:n/2)' * fs / n, 'RelTol', 1e-12);
tc.verifyEqual(max(OUT.spectrum_level), 60, 'AbsTol', 1e-3);
p.spectrum_degree = 12;
[txt, same] = evalc('e.run(x, fs, p, false)');
tc.verifyEqual(same.spectrum_level, OUT.spectrum_level);
tc.verifyFalse(contains(txt, 'Narrowband spectrum'));
end

function test_run_without_show_opens_no_figure(tc)
% A metric run by the GUI opens no figure unless the figure is asked for.
x = tc.TestData.x_mono; fs = tc.TestData.fs;
m = SQAT_GUI_metrics;
e = m(strcmp({m.id}, 'Roughness_Daniel1997'));
before = numel(findall(groot, 'Type', 'figure'));
evalc('e.run(x, fs, il_default_params(e), false)');
tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), before);
evalc('e.run(x, fs, il_default_params(e), true)');
tc.verifyGreaterThan(numel(findall(groot, 'Type', 'figure')), before);
end

%% Extracting results ------------------------------------------------------

function test_analyses_take_the_values_of_the_output(tc)
% The analyses offered in the graphs (time series, Bark profiles and maps) take
% their values from the output of the metric, whether the map is stored as
% bands by time (roughness) or time by bands (fluctuation strength).
x = tc.TestData.x_mono; fs = tc.TestData.fs;
m = SQAT_GUI_metrics;
% series and a map that the metric stores as bands x time
e = m(strcmp({m.id}, 'Roughness_Daniel1997'));
[~, OUT] = evalc('e.run(x, fs, il_default_params(e), false)');
A = SQAT_GUI_extract(OUT, 'Roughness_Daniel1997', 1);
tc.verifyEqual(A(strcmp({A.id}, 'roughness')).y, OUT.InstantaneousRoughness(:));
tc.verifyEqual(A(strcmp({A.id}, 'roughness')).x, OUT.time(:));
sp = A(strcmp({A.id}, 'specific_roughness_time'));
tc.verifyEqual(sp.z, OUT.InstantaneousSpecificRoughness.');   % time x bands
tc.verifyEqual(sp.y, OUT.barkAxis(:));
pr = A(strcmp({A.id}, 'specific_roughness'));
tc.verifyEqual(pr.y, OUT.TimeAveragedSpecificRoughness(:));
% a map stored as time x bands, and a row vector on a column time axis
e = m(strcmp({m.id}, 'FluctuationStrength_Osses2016'));
[~, OUT] = evalc('e.run(x, fs, il_default_params(e), false)');
A = SQAT_GUI_extract(OUT, 'FluctuationStrength_Osses2016', 1);
tc.verifyEqual(A(strcmp({A.id}, 'fs')).y, OUT.InstantaneousFluctuationStrength(:));
tc.verifyEqual(A(strcmp({A.id}, 'specific_fs_time')).z, OUT.InstantaneousSpecificFluctuationStrength);
end

function test_analyses_pick_the_channel_of_a_binaural_output(tc)
% For a two-channel ECMA-418-2 loudness output, the analyses of channel 1 and
% channel 2 take the series, profile and map of that channel.
x = tc.TestData.x_mono; x2 = [x, x*10^(-10/20)]; fs = tc.TestData.fs;
m = SQAT_GUI_metrics;
e = m(strcmp({m.id}, 'Loudness_ECMA418_2'));
[~, OUT] = evalc('e.run(x2, fs, il_default_params(e), false)');
for c = 1:2
    A = SQAT_GUI_extract(OUT, 'Loudness_ECMA418_2', c);
    tc.verifyEqual(A(strcmp({A.id}, 'loudness')).y, OUT.loudnessTDep(:, c));
    tc.verifyEqual(A(strcmp({A.id}, 'specific_loudness')).y, OUT.specLoudnessPowAvg(:, c));
    tc.verifyEqual(A(strcmp({A.id}, 'specific_loudness_time')).z, OUT.specLoudness(:, :, c));
end
A = SQAT_GUI_extract(OUT, 'Loudness_ECMA418_2', 'Binaural');
tc.verifyEqual(A(strcmp({A.id}, 'loudness')).y, OUT.loudnessTDepBin(:));
tc.verifyEqual(A(strcmp({A.id}, 'specific_loudness_time')).z, OUT.specLoudnessBin);
% a mono output has one channel only
[~, OUT1] = evalc('e.run(x, fs, il_default_params(e), false)');
tc.verifyEmpty(SQAT_GUI_extract(OUT1, 'Loudness_ECMA418_2', 2));
tc.verifyEmpty(SQAT_GUI_extract(OUT1, 'Loudness_ECMA418_2', 'Binaural'));
% the tonality of ECMA-418-2 has no combined binaural value
e = m(strcmp({m.id}, 'Tonality_ECMA418_2'));
[~, OUT] = evalc('e.run(x2, fs, il_default_params(e), false)');
tc.verifyNotEmpty(SQAT_GUI_extract(OUT, 'Tonality_ECMA418_2', 2));
tc.verifyEmpty(SQAT_GUI_extract(OUT, 'Tonality_ECMA418_2', 'Binaural'));
end

function test_analysis_tables_hold_the_values_of_the_output(tc)
% Every analysis of a real output turns into a table with the values of the
% analysis: series and maps of a time-varying loudness, the band levels of the
% sound level meter.
x = tc.TestData.x_mono; fs = tc.TestData.fs;
m = SQAT_GUI_metrics;
e = m(strcmp({m.id}, 'Loudness_ISO532_1'));
p = il_default_params(e);
p.method = 2;
[~, OUT] = evalc('e.run(x, fs, p, false)');
e = m(strcmp({m.id}, 'Do_SLM'));
[~, SLM] = evalc('e.run(x, fs, il_default_params(e), false)');
A = [SQAT_GUI_extract(OUT, 'Loudness_ISO532_1', 1), SQAT_GUI_extract(SLM, 'Do_SLM', 1)];
tc.verifyEqual(unique({A.kind}), {'map', 'profile', 'series'});
for a = A
    T = SQAT_GUI_analysis_table(a);
    tc.verifyEqual(T{:, 1}, a.x, a.id);
    if strcmp(a.kind, 'map')
        tc.verifyEqual(T{:, 2:end}, a.z, a.id);
    else
        tc.verifyEqual(T{:, 2}, a.y, a.id);
    end
end
end

%% Helpers -----------------------------------------------------------------

function p = il_default_params(e)
p = struct();
for q = e.params
    p.(q.name) = q.value;
end
end

function v = il_field_or(s, name, default)
if isfield(s, name), v = s.(name); else, v = default; end
end
