function port = detect_stlink_port()
% Returns the COM port name of the ST-Link Virtual COM Port.
% Use "all" (not "available") so the port is found even when it is
% momentarily held open by STM32CubeProgrammer during flashing.
ports = serialportlist("all");
if isempty(ports)
    error('pil:detect_stlink_port:none', 'No serial ports found.');
end

% Identify the ST-Link VCP via Windows PnP info.
[ok, out] = system('powershell -NoProfile -Command "Get-PnpDevice -Class Ports -Status OK | Where-Object { $_.FriendlyName -match ''STLink'' } | Select-Object -ExpandProperty FriendlyName"');
if ok == 0 && contains(out, 'COM')
    tok = regexp(out, 'COM\d+', 'match', 'once');
    if ~isempty(tok) && any(ports == tok)
        port = tok;
        return
    end
end

port = char(ports(1));
warning('pil:detect_stlink_port:fallback', ...
    'ST-Link VCP not detected; using first port %s.', port);
end
