function info = env_info()
% Capture machine + tool versions for the report header.
info.timestamp_utc  = string(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
info.host           = string(getenv('COMPUTERNAME'));
info.user           = string(getenv('USERNAME'));
info.matlab_version = string(version);
try
    info.simulink_version = string(ver('simulink').Version);
catch
    info.simulink_version = "unknown";
end
end
