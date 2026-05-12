classdef test_orch_list_reports < matlab.unittest.TestCase
%TEST_ORCH_LIST_REPORTS REQ-SW-MOR-01: list_reports unions PART1, PART2
% and JSON timestamps and returns newest-first.
%
% This test stubs the doc_generator/reports directory by writing
% empty files into it then restores after.

    properties
        repsDir
        backupNames = {};
    end

    methods (TestClassSetup)
        function addPaths(tc)
            here = fileparts(mfilename('fullpath'));
            repo = fileparts(fileparts(here));
            addpath(fullfile(repo,'orch'));
            tc.repsDir = fullfile(repo,'doc_generator','reports');
            if ~isfolder(tc.repsDir), mkdir(tc.repsDir); end
        end
    end

    methods (TestMethodTeardown)
        function cleanFiles(tc)
            for i = 1:numel(tc.backupNames)
                f = tc.backupNames{i};
                if exist(f,'file'), delete(f); end
            end
            tc.backupNames = {};
        end
    end

    methods (Test)
        function newestFirstOrdering(tc)
            ts1 = '20200101_000000';
            ts2 = '20300101_000000';
            f1 = fullfile(tc.repsDir, ['REPORT_PART1_' ts1 '.html']);
            f2 = fullfile(tc.repsDir, ['REPORT_PART1_' ts2 '.html']);
            tc.touch(f1); tc.touch(f2);

            r = orch.list_reports();
            tc.verifyGreaterThanOrEqual(numel(r), 2);

            ts = [r.ts];
            % Find our two synthetic timestamps; verify ts2 appears first.
            i1 = find(ts == ts1, 1);
            i2 = find(ts == ts2, 1);
            tc.verifyTrue(~isempty(i1) && ~isempty(i2));
            tc.verifyLessThan(i2, i1, ...
                'Newest timestamp must come first');
        end

        function jsonOnlyRunStillListed(tc)
            ts = '20210101_010101';
            f = fullfile(tc.repsDir, ['FULL_REPORT_' ts '.json']);
            tc.touch(f);
            r = orch.list_reports();
            row = r([r.ts] == ts);
            tc.verifyTrue(~isempty(row));
            tc.verifyTrue(row.has_json);
            tc.verifyFalse(row.has_html1);
        end
    end

    methods
        function touch(tc, f)
            fid = fopen(f,'w'); fwrite(fid,'<!--stub-->'); fclose(fid);
            tc.backupNames{end+1} = f;
        end
    end
end
