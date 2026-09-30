function tests = Tonality_Aures1985_reference_test
% The extraction and the level excess of Tonality_Aures1985 (Terhardt et al.
% 1982) against the intermediate values of Zhang and Shrestha (2003),
% Sound Quality User-defined Cursor Reading Control, Tonality Metric,
% IMM-Thesis-2003-22, DTU: the power spectra of its Appendix C (in
% validation/Tonality_Aures1985/reference_values) and the components and
% level excesses of its Tables 6.2 and 6.3. The checks and criteria are the
% ones of validation/Tonality_Aures1985/validation_extraction_and_level_excess.m.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
tc.applyFixture(matlab.unittest.fixtures.PathFixture(root, 'IncludingSubfolders', true));   % SQAT and test/report
fh = Tonality_Aures1985('localfunctions');
names = cellfun(@func2str, fh, 'UniformOutput', false);
for n = {'il_find_sinusoids', 'il_SPL_excess', 'il_Fq2Bark', 'il_Threshold'}
    tc.TestData.(n{1}) = fh{strcmp(names, n{1})};
end
dir_ref = fullfile(root, 'validation', 'Tonality_Aures1985', 'reference_values');
t(1).file = fullfile(dir_ref, 'ZhangShrestha2003_AppendixC_Test1.txt');
t(1).thr = 3;                                  % the criterion the thesis used for Test 1 (p. 49)
t(1).comp = [387.89 58.13; 765.95 33.20; 989.05 26.51; 1528.19 27.16; 1871.83 39.69; 2078.14 46.70; ...
             2509.13 41.67; 2636.70 43.89; 2863.81 37.18; 3091.05 35.01; 3348.17 40.62; 3467.18 39.10; ...
             3595.04 35.01; 3864.10 26.76];    % Table 6.2: frequency (Hz), level (dB)
t(1).LX = [387.89 39.02; 765.95 12.86; 989.05 9.11; 1528.19 9.67; 1871.83 10.35; 2078.14 16.20; ...
           2509.13 1.52; 2636.70 3.04];        % Table 6.2: level excess (dB)
t(2).file = fullfile(dir_ref, 'ZhangShrestha2003_AppendixC_Test2.txt');
t(2).thr = 7;                                  % the 7 dB of Terhardt et al.
t(2).comp = [387.59 87.87; 807.49 90.96; 1410.41 90.97; 2196.38 87.87];    % Table 6.3
t(2).LX = [387.59 67.83; 807.49 27.40; 1410.41 21.61; 2196.38 13.66];
tc.TestData.t = t;
end

function test_extraction_finds_the_components_of_tables_6_2_and_6_3(tc)
% Every component of the tables is found, each within one sample in frequency
% (after the refinement of Eq. 3 of the thesis) and with the same level to 0.01 dB.
for k = 1:2
    [f, L, df, idx, fref] = il_extract(tc, k);
    c = tc.TestData.t(k).comp;
    tc.verifyNumElements(idx, size(c, 1), sprintf('Test %d: number of components', k));
    [d, m] = min(abs(c(:, 1) - fref'), [], 1);
    tc.verifyLessThan(d, df, sprintf('Test %d: frequency within one sample', k));
    sqat_report_record('tonality_aures1985', sprintf('Test %d, levels of the components (Table 6.%d)', k, k+1), L(idx), c(m, 2), 0.01);
    tc.verifyEqual(L(idx), c(m, 2), 'AbsTol', 0.01, sprintf('Test %d: levels', k));
end
end

function test_level_excess_of_the_masked_components(tc)
% On the components masked by the other components (more than 25 dB of
% excitation from them), the level excess of the tables is reproduced within
% 0.3 dB with the noise term left out.
for k = 1:2
    [f, L, df, idx, fref] = il_extract(tc, k);
    in = struct('freq', f, 'ToneF', f(idx), 'ToneL', L(idx), 'Lnoise', -300 * ones(size(L)));
    LX = tc.TestData.il_SPL_excess(in);
    zc = tc.TestData.il_Fq2Bark(f(idx));
    Lc = L(idx);
    got = [];
    want = [];
    for i = 1:numel(idx)
        a = 0;
        for j = [1:i-1, i+1:numel(idx)]      % Eqs. 5 and 7 of the thesis: the excitation of the others
            if j < i
                s = -24 - 230/f(idx(j)) + 0.2*Lc(j);
            else
                s = 27;
            end
            a = a + 10^((Lc(j) - s*(zc(j) - zc(i)))/20);
        end
        [d, m] = min(abs(tc.TestData.t(k).LX(:, 1) - fref(i)));
        if 20*log10(a) > 25 && d < df
            got(end+1) = LX(i); %#ok<AGROW>
            want(end+1) = tc.TestData.t(k).LX(m, 2); %#ok<AGROW>
        end
    end
    tc.assertNotEmpty(got, sprintf('Test %d: no masked component', k));
    sqat_report_record('tonality_aures1985', sprintf('Test %d, level excess of the masked components (Table 6.%d)', k, k+1), got, want, 0.3);
    tc.verifyEqual(got, want, 'AbsTol', 0.3, sprintf('Test %d: level excess', k));
end
end

function [f, L, df, idx, fref] = il_extract(tc, k)
% the components the metric extracts from the spectrum of Test k
A = readmatrix(tc.TestData.t(k).file, 'CommentStyle', '#');
f = A(:, 1);
L = A(:, 2);
df = f(2) - f(1);
idx = tc.TestData.il_find_sinusoids(L, 1, numel(L), df, tc.TestData.t(k).thr);
fref = f(idx) + 0.46 * (L(idx+1) - L(idx-1));     % Eq. 3 of the thesis, for the comparison only
end
