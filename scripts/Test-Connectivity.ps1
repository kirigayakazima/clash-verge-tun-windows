# Read-only HTTP checks with the explicit application proxy bypassed.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is required.' }

$domestic = & curl.exe --silent --show-error --location --max-time 12 --noproxy '*' --output NUL --write-out '%{http_code}' 'https://www.baidu.com/'
if ($LASTEXITCODE -ne 0) { throw 'Domestic HTTP check failed.' }
if ($domestic -notmatch '^[23][0-9][0-9]$') { throw "Domestic HTTP check returned $domestic." }
Write-Output "Domestic HTTP status: $domestic"

$trace = & curl.exe --silent --show-error --max-time 12 --noproxy '*' 'https://www.cloudflare.com/cdn-cgi/trace'
if ($LASTEXITCODE -ne 0) { throw 'External HTTP check failed.' }
$country = ($trace | Select-String '^loc=([A-Z]{2})$').Matches.Groups[1].Value
if (-not $country) { throw 'External check responded, but no country code was returned.' }
Write-Output "External exit country: $country"
Write-Output 'Explicit system proxy is bypassed. With TUN off, this checks the direct path; with TUN on, the result follows its rules.'

# Probe HTTP response only; this does not verify the route or actual playback.
$biliCheck = & curl.exe --silent --show-error --head --max-time 8 --noproxy '*' --output NUL --write-out '%{http_code}' 'https://upos-sz-mirrorcos.bilivideo.com/'
if ($LASTEXITCODE -ne 0 -or $biliCheck -notmatch '^[234][0-9][0-9]$') {
    Write-Warning "Domestic video CDN probe failed (status: $biliCheck). Check connectivity and the actual route in Clash connection records."
} else {
    Write-Output "Domestic video CDN status: $biliCheck (HTTP response received; DIRECT routing and video playback not verified)"
}
