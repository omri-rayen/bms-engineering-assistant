classdef test_val_new_result_check < matlab.unittest.TestCase
%TEST_VAL_NEW_RESULT_CHECK Unit tests for val.new_result + val.check
%
% REQ-SW-VAL-01 (result skeleton) and REQ-SW-VAL-02 (check semantics).

    methods (TestClassSetup)
        function addPaths(tc)
            here = fileparts(mfilename('fullpath'));
            repo = fileparts(fileparts(here));
            addpath(fullfile(repo,'validator'));
        end
    end

    methods (Test)
        function emptySkeletonHasExpectedFields(tc)
            r = val.new_result('mil','REQ-LL-X-01','test_x','REQ-LL-X-01');
            tc.verifyEqual(r.suite,        'mil');
            tc.verifyEqual(r.id,           'REQ-LL-X-01');
            tc.verifyEqual(r.status,       "skipped");
            tc.verifyEqual(numel(r.checks), 0);
            tc.verifyEqual(r.signals_plot, "");
        end

        function singlePassMovesStatusToPass(tc)
            r = val.new_result('mil','X','t','X');
            r = val.check(r,'k1', true, 'ok', 1, 1);
            tc.verifyEqual(r.status, "pass");
            tc.verifyEqual(numel(r.checks), 1);
            tc.verifyEqual(r.checks(1).status, "pass");
        end

        function anyFailMovesStatusToFail(tc)
            r = val.new_result('mil','X','t','X');
            r = val.check(r,'k1', true,  'ok',   1, 1);
            r = val.check(r,'k2', false, 'bad',  3, 2);
            tc.verifyEqual(r.status, "fail");
        end

        function errorStatusStickyOverFail(tc)
            r = val.new_result('mil','X','t','X');
            r.status = "error";
            r = val.check(r,'k1', false, 'bad', 0, 1);
            tc.verifyEqual(r.status, "error",  ...
                'A pre-existing error must not be downgraded to fail.');
        end
    end
end
