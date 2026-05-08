function r = test_REQ_LL_RT_RAM_01()
% REQ-LL-RT-RAM-01  Static RAM footprint of the bms_master PIL ELF
% (initialised .data + zero-initialised .bss) on the STM32 H7A3 SHALL
% stay below req.RT_RAM_max_kb. Read from arm-none-eabi-size on the
% built ELF; no MCU run is required.
r = val.new_result("pil","RT-RAM-01","bms_master static RAM footprint","REQ-LL-RT-RAM-01");

req       = evalin('base', 'req');
BUDGET_KB = req.RT_RAM_max_kb;

here    = fileparts(mfilename('fullpath'));
valRoot = fileparts(fileparts(here));
proj    = fileparts(valRoot);
elf     = fullfile(proj, 'bms_master_ert_rtw', 'pil', 'bms_master.elf');
if ~isfile(elf)
    error('pil:ram:noElf', 'PIL ELF not found: %s (run pil.build first)', elf);
end

sizeExe = fullfile(matlabroot, '..', '..', 'ProgramData', 'MATLAB', ...
    'SupportPackages', 'R2024b', '3P.instrset', 'gnuarm-armcortex.instrset', ...
    'win', 'bin', 'arm-none-eabi-size.exe');
if ~isfile(sizeExe)
    sizeExe = 'C:\ProgramData\MATLAB\SupportPackages\R2024b\3P.instrset\gnuarm-armcortex.instrset\win\bin\arm-none-eabi-size.exe';
end
[st, out] = system(sprintf('"%s" "%s"', sizeExe, elf));
if st ~= 0
    error('pil:ram:size', 'arm-none-eabi-size failed: %s', strtrim(out));
end
% Header line + one data line: "  text  data  bss  dec  hex  filename"
nums = sscanf(out, '%*s %*s %*s %*s %*s %*s %d %d %d', 3);
if numel(nums) < 3
    nums = sscanf(regexprep(out, '.*filename\s*', ''), '%d %d %d', 3);
end
text_b = nums(1);  data_b = nums(2);  bss_b = nums(3);
ram_kb   = (data_b + bss_b) / 1024;
flash_kb = (text_b + data_b) / 1024;

ok = ram_kb < BUDGET_KB;
r  = val.check(r, "ram_within_budget", ok, ...
    sprintf('RAM (data+bss) = %.2f KB  (flash text+data = %.2f KB, budget %.0f KB)', ...
        ram_kb, flash_kb, BUDGET_KB), ...
    ram_kb, sprintf('< %.0f KB', BUDGET_KB));

r.metrics.ram_kb    = ram_kb;
r.metrics.flash_kb  = flash_kb;
r.metrics.text_b    = text_b;
r.metrics.data_b    = data_b;
r.metrics.bss_b     = bss_b;
r.metrics.budget_kb = BUDGET_KB;
end
