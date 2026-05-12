classdef test_orch_scenarios < matlab.unittest.TestCase
%TEST_ORCH_SCENARIOS REQ-SW-MOR-03/04: scenarios catalog covers every
% MIL group and exposes both SIL and PIL entries.

    methods (TestClassSetup)
        function addPaths(tc)
            here = fileparts(mfilename('fullpath'));
            repo = fileparts(fileparts(here));
            addpath(fullfile(repo,'orch'));
        end
    end

    methods (Test)
        function returnsStructArrayWithExpectedFields(tc)
            s = orch.scenarios();
            tc.verifyClass(s, 'struct');
            tc.verifyTrue(numel(s) >= 14);  % 14 MIL + 1 SIL + 1 PIL
            tc.verifyTrue(all(isfield(s, ...
                {'key','label','path','filter'})));
        end

        function pathsAreOnlyMilSilPil(tc)
            s = orch.scenarios();
            paths = unique({s.path});
            tc.verifyEqual(sort(paths), {'mil','pil','sil'});
        end

        function eachBmsSubsystemHasFilterPrefix(tc)
            s = orch.scenarios();
            mil = s(strcmp({s.path},'mil'));
            keys = {mil.key};
            for k = {'vmon','tmon','imon','fsm','soc','soh','bal', ...
                     'thm','pwr','wdg','hwp','agg','prd'}
                tc.verifyTrue(any(strcmp(keys, k{1})), ...
                    sprintf('Missing MIL scenario key %s', k{1}));
            end
        end

        function silAndPilExist(tc)
            s = orch.scenarios();
            tc.verifyTrue(any(strcmp({s.path},'sil')));
            tc.verifyTrue(any(strcmp({s.path},'pil')));
        end
    end
end
