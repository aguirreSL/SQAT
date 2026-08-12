function [tf, msg] = check_tolerance(actual, expected, tol, label, varargin)
% function [tf, msg] = check_tolerance(actual, expected, tol, label, ...)
%
%  Compares a computed value against a reference value, prints a PASS/FAIL
%  verdict, and returns whether it passed. Intended for the validation
%  scripts, which historically plotted a tolerance band without ever
%  checking against it - a script that cannot fail cannot catch anything.
%
%  Typical use, accumulating over several checks and failing at the end so
%  that all verdicts are printed and the figures are still produced:
%
%      ok = true;
%      ok = check_tolerance(N, N_ref, 0.1, 'signal 3 loudness')            && ok;
%      ok = check_tolerance(S, S_ref, 0.05, 'signal 3 sharpness')          && ok;
%      ...
%      if ~ok
%          error('%s: one or more checks are outside tolerance.', mfilename);
%      end
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% INPUT ARGUMENTS
%   actual : double
%     [1x1] or [Nx1] computed value(s)
%
%   expected : double
%     [1x1] or [Nx1] reference value(s), same size as actual
%
%   tol : double
%     tolerance. Absolute by default, in the same units as the inputs; see
%     the 'Mode' option for relative comparison
%
%   label : char
%     short description printed with the verdict, e.g. 'signal 10, Nmax'
%
% OPTIONAL NAME-VALUE PAIRS
%   'Mode' : 'absolute' (default) | 'relative'
%     'relative' compares abs(actual-expected)./abs(expected)
%
%   'Unit' : char (default '')
%     printed after the numbers, e.g. 'sone'
%
%   'Verbose' : logical (default true)
%     set false to suppress printing and only return the verdict
%
% OUTPUTS
%   tf : logical
%     true if every element is within tolerance
%
%   msg : char
%     the verdict line, whether or not it was printed
%
% Author: SQAT team, 12.08.2026
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if nargin == 0
    help check_tolerance;
    return;
end

p = inputParser;
addParameter(p, 'Mode',    'absolute', @(x) any(strcmpi(x, {'absolute','relative'})));
addParameter(p, 'Unit',    '',         @(x) ischar(x) || isstring(x));
addParameter(p, 'Verbose', true,       @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

actual   = actual(:);
expected = expected(:);

if numel(actual) ~= numel(expected)
    error('%s: actual (%d elements) and expected (%d) must be the same size.', ...
          mfilename, numel(actual), numel(expected));
end

switch lower(opts.Mode)
    case 'relative'
        dev  = abs(actual - expected) ./ max(abs(expected), eps);
        unit = '%';
        shown = 100*dev;
        shownTol = 100*tol;
    otherwise
        dev  = abs(actual - expected);
        unit = char(opts.Unit);
        shown = dev;
        shownTol = tol;
end

[worst, idx] = max(dev);
tf = worst <= tol;

if tf
    verdict = 'PASS';
else
    verdict = 'FAIL';
end

if numel(actual) == 1
    msg = sprintf('  [%s] %-46s %g vs %g %s  (dev %.4g, tol %.4g)', ...
                  verdict, label, actual, expected, unit, shown, shownTol);
else
    msg = sprintf(['  [%s] %-46s worst dev %.4g of %.4g %s ' ...
                   'at element %d of %d'], ...
                  verdict, label, shown(idx), shownTol, unit, idx, numel(actual));
end

if opts.Verbose
    fprintf('%s\n', msg);
end

end
