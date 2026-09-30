function S = sqat_run_script(file__)
% function S = sqat_run_script(file)
%
%   Runs a validation script of validation/ in a workspace of its own (the
%   scripts start with clear all, which would clear the variables of a test)
%   and returns every variable it leaves, plus
%     S.run_err : the message of the error that stopped it, '' if none
%     S.run_out : what it printed
%   (named so that no variable of a script overwrites them)
%   The figures it opens are closed.

try
    out__ = evalc('run(file__)');
    err__ = '';                              % set after the script, which clears all
catch e__
    out__ = '';
    err__ = e__.message;
end
names__ = who;
S = struct();
for k__ = 1:numel(names__)
    if ~endsWith(names__{k__}, '__')
        S.(names__{k__}) = eval(names__{k__});
    end
end
S.run_err = err__;
S.run_out = out__;
close all
end
