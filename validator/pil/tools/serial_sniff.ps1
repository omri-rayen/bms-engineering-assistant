# validator/pil/tools/serial_sniff.ps1
# Dumps raw bytes from a serial port for N seconds. Used to diagnose
# the PIL rtiostream handshake on the Nucleo-H7A3ZI-Q (STLink VCP / COM3).
#
# Usage:
#   pwsh -File validator/pil/tools/serial_sniff.ps1 -Port COM3 -Baud 115200 -Seconds 10
#   pwsh -File validator/pil/tools/serial_sniff.ps1            # defaults: COM3 / 115200 / 10s
#
# Interpretation:
#   - 0 bytes received  -> MCU is silent (init problem, wrong pin mux, halted, or stuck in HardFault)
#   - bytes received but unreadable / wrong framing -> baud or parity mismatch
#   - readable text     -> firmware is alive but not running the rtiostream protocol

[CmdletBinding()]
param(
    [string]$Port = 'COM3',
    [int]$Baud = 115200,
    [int]$Seconds = 10,
    [string]$Parity = 'None',     # None / Odd / Even
    [int]$DataBits = 8,
    [string]$StopBits = 'One'     # One / OnePointFive / Two
)

$ErrorActionPreference = 'Stop'

Write-Host "[serial_sniff] $Port @ $Baud, $DataBits$($Parity[0])$StopBits, listening $Seconds s ..." -ForegroundColor Cyan

# Make sure the port isn't held open by another process (e.g. MATLAB still has it after a failed PIL).
$inUse = [System.IO.Ports.SerialPort]::GetPortNames() -contains $Port
if (-not $inUse) {
    Write-Host "[serial_sniff] WARNING: $Port is not enumerated. Available: $([System.IO.Ports.SerialPort]::GetPortNames() -join ', ')" -ForegroundColor Yellow
    exit 1
}

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, $Parity, $DataBits, $StopBits
$sp.ReadTimeout  = 200
$sp.WriteTimeout = 200
$sp.DtrEnable    = $true
$sp.RtsEnable    = $true

try {
    $sp.Open()
} catch {
    Write-Host "[serial_sniff] Could not open $Port : $_" -ForegroundColor Red
    Write-Host "[serial_sniff] Likely held open by MATLAB. Close MATLAB or wait for the previous PIL session to time out." -ForegroundColor Yellow
    exit 2
}

$buf       = New-Object byte[] 4096
$total     = 0
$chunks    = 0
$start     = Get-Date
$deadline  = $start.AddSeconds($Seconds)
$collected = New-Object System.Collections.Generic.List[byte]

while ((Get-Date) -lt $deadline) {
    try {
        $avail = $sp.BytesToRead
        if ($avail -gt 0) {
            $n = $sp.Read($buf, 0, [Math]::Min($avail, $buf.Length))
            if ($n -gt 0) {
                $chunks++
                $total += $n
                for ($i = 0; $i -lt $n; $i++) { $collected.Add($buf[$i]) }
            }
        } else {
            Start-Sleep -Milliseconds 50
        }
    } catch [System.TimeoutException] {
        # ignore
    }
}

$sp.Close()
$sp.Dispose()

$elapsed = ((Get-Date) - $start).TotalSeconds
Write-Host ""
Write-Host "[serial_sniff] done in $([Math]::Round($elapsed,2)) s : $total bytes in $chunks chunk(s)" -ForegroundColor Cyan

if ($total -eq 0) {
    Write-Host "[serial_sniff] VERDICT: MCU is SILENT. No bytes received." -ForegroundColor Red
    Write-Host "[serial_sniff] -> Check: (1) was the new .elf actually flashed and reset, (2) USART3 pins (PD8/PD9 on Nucleo-H7A3ZI-Q), (3) MCU not stuck in HardFault." -ForegroundColor Yellow
    exit 3
}

# Print a hex+ascii dump of the first 256 bytes.
$dumpLen = [Math]::Min(256, $collected.Count)
Write-Host ""
Write-Host "[serial_sniff] first $dumpLen bytes (hex | ascii):" -ForegroundColor Cyan
for ($off = 0; $off -lt $dumpLen; $off += 16) {
    $hex = ''
    $asc = ''
    for ($j = 0; $j -lt 16 -and ($off + $j) -lt $dumpLen; $j++) {
        $b = $collected[$off + $j]
        $hex += ('{0:X2} ' -f $b)
        if ($b -ge 0x20 -and $b -lt 0x7F) { $asc += [char]$b } else { $asc += '.' }
    }
    '{0,4:X4}  {1,-48}  {2}' -f $off, $hex, $asc | Write-Host
}

# Heuristic: rtiostream serial framing starts with byte 0x02 (STX) followed by length+payload.
$looksLikeRtio = ($collected.Count -ge 4) -and ($collected[0] -eq 0x02)
if ($looksLikeRtio) {
    Write-Host ""
    Write-Host "[serial_sniff] VERDICT: looks like rtiostream framing (starts with 0x02). The MCU IS speaking the protocol." -ForegroundColor Green
    Write-Host "[serial_sniff] -> If MATLAB still times out: MATLAB may have lost the port (already opened it for the failing handshake). Close MATLAB then retry pil.run." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "[serial_sniff] VERDICT: bytes received but NOT rtiostream framing. Likely baud/parity mismatch or HAL printf debug output." -ForegroundColor Yellow
}
