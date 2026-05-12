function configure(mdl)
% pil.configure  Apply the STM32 PIL hardware configuration to mdl and
% every model it references. Idempotent. Must be called *every* MATLAB
% session before either pil.build or any PIL sim(), because none of these
% settings are saved back to the .slx (we do not want to dirty the model).
%
%   pil.configure('bms_master')

if nargin < 1
    error('pil:configure:noModel', 'Usage: pil.configure(modelname)');
end

scriptDir = fileparts(mfilename('fullpath'));      % validator/pil/+pil
pilRoot   = fileparts(scriptDir);                  % validator/pil
iocFile   = fullfile(pilRoot, 'board', 'nucleo_h7a3zit_q.ioc');
comPort   = pil.detect_stlink_port();              % e.g. 'COM3'

% Register STM32CubeMX + STM32CubeProgrammer with MATLAB if installed at
% the standard Windows location but not yet linked. The CubeMX project
% (.ioc) is consumed by the STM32 target during code-gen and the
% programmer CLI is invoked to flash the resulting .elf. Override the
% default install location with the BMS_STM32CUBEMX / BMS_STM32CUBEPROG
% environment variables if Cube is installed elsewhere.
cubeMxDir = getenv('BMS_STM32CUBEMX');
if isempty(cubeMxDir)
    cubeMxDir = 'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeMX';
end
if exist(fullfile(cubeMxDir, 'STM32CubeMX.exe'), 'file') == 2
    setpref('MW_STM32', 'STM32CubeMX', ...
        struct('Location', cubeMxDir, 'Version', '6.4.0'));
end
cubeProgDir = getenv('BMS_STM32CUBEPROG');
if isempty(cubeProgDir)
    cubeProgDir = 'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer';
end
if exist(fullfile(cubeProgDir, 'bin', 'STM32_Programmer_CLI.exe'), 'file') == 2
    setpref('MW_STM32', 'STM32CubeProgrammer', ...
        struct('Location', fullfile(cubeProgDir, 'bin'), 'Version', '2.6.0'));
end

board = 'STM32H7xx Based (Single-core)';

load_system(mdl);
% Avoid the Variants warning that find_mdlrefs emits when it walks past
% Variant Subsystem boundaries with no explicit match filter.
set_param(mdl, 'Dirty', 'off');

refs = find_mdlrefs(mdl, 'AllLevels', true, ...
    'MatchFilter', @Simulink.match.allVariants);
refs = [refs(:); {mdl}];

for i = 1:numel(refs)
    m = refs{i};
    load_system(m);
    set_param(m, 'SystemTargetFile',  'ert.tlc');
    set_param(m, 'TargetLang',        'C');
    set_param(m, 'GenerateReport',    'off');
    set_param(m, 'HardwareBoard',     board);
    % ARM toolchain has 64-bit long long; enable it so word-size checks pass.
    set_param(m, 'ProdLongLongMode',  'on');
    set_param(m, 'TargetLongLongMode','on');
    % Force "test = production" so the generated C does not pull in x86
    % SIMD intrinsics (emmintrin.h) for the host-side emulation header.
    set_param(m, 'ProdEqTarget',      'on');
    % Drop any code-replacement library inherited from the host SIL build.
    set_param(m, 'CodeReplacementLibrary', 'None');
    % Compile the embedded code with -O3 (Faster Runs); the BMS step is
    % LSTM-heavy and at -O0 it overruns the 100 ms BMS tick by ~96 ms.
    set_param(m, 'BuildConfiguration', 'Faster Runs');

    % Coverage instrumentation is incompatible with on-chip execution-
    % time profiling (Embedded Coder refuses to build PIL with both on).
    % Force every cov knob off; if a previous MIL run dirtied the in-
    % memory model these will still be 'on'.
    set_param(m, 'CovEnable',         'off');
    set_param(m, 'RecordCoverage',    'off');
    set_param(m, 'CovModelRefEnable', 'off');

    % Point the STM32 target at the bundled Nucleo H7A3 CubeMX project
    % and the ST-Link virtual COM port for the PIL serial transport.
    cs   = getActiveConfigSet(m);
    data = codertarget.data.getData(cs);
    data.STM32CubeMX.ProjectFile  = iocFile;
    data.STM32CubeMX.DeviceId     = 'STM32H7A3Z(G-I)TxQ';
    data.STM32CubeMX.Family       = 'STM32H7';
    data.Connection.Serialport    = comPort;
    data.PIL.Interface            = 'Serial';
    % Nucleo-H7A3ZI-Q runs at 280 MHz.
    data.Clocking.cpuClockRateMHz = 280;

    % On-chip code-execution profiling is only meaningful on the top PIL
    % model. Sample the cycle-accurate free-running 32-bit TIM5 counter
    % (clocked from APB1-timer = 280 MHz, no prescaler -> 1 tick = 3.57 ns,
    % wraps every ~15.3 s). The Embedded Coder profiling runtime
    % (profiler_timer.c, shipped in the STM32 support package) enables
    % the TIM5 clock and starts the counter from C, so no extra .ioc
    % entries are required. TIM5 has no NVIC IRQ -> cannot preempt the
    % USART3 / DMA1_Stream0 PIL serial path.
    if strcmp(m, mdl)
        data.PIL.Timer.Source    = 'TIM5';
        data.PIL.Timer.Prescaler = 0;
        data.PIL.Timer.Counter   = 4294967295;
    end
    codertarget.data.setData(cs, data);

    % Per-step on-chip execution-time samples for the WCET test. We only
    % need the model-step section, so use coarse-grained instrumentation
    % (a single TIM5 read pair per BMS step). 'Detailed' would wrap every
    % atomic subsystem (including each LSTM gate) and add multi-ms of
    % pure profiling overhead -- pointless for a top-level WCET budget.
    if strcmp(m, mdl)
        set_param(m, 'CodeExecutionProfiling',       'on');
        set_param(m, 'CodeProfilingInstrumentation', 'Coarse');
        set_param(m, 'CodeProfilingSaveOptions',     'AllData');
    end
end

% Clear the dirty flag on every touched model. PIL configuration is meant
% to be transient (we deliberately do not persist these settings to .slx),
% but Simulink still flags the model as modified, which trips a downstream
% "unsaved changes" warning on the next find_mdlrefs walk.
for i = 1:numel(refs)
    try, set_param(refs{i}, 'Dirty', 'off'); catch, end %#ok<CTCH>
end

% Final assertion: with CodeExecutionProfiling=on on the top model, no
% model in the PIL graph may have any coverage flag still on, otherwise
% slbuild errors out late with a confusing message.
for i = 1:numel(refs)
    if strcmp(get_param(refs{i}, 'CovEnable'), 'on')
        error('pil:configure:covStillOn', ...
            'CovEnable is still ''on'' for model ''%s'' after configure.', refs{i});
    end
end
end
