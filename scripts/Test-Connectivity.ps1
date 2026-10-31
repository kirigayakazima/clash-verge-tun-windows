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

# Domestic media stream check (verify domestic video CDN does not hang or get hijacked by proxy)
$biliCheck = & curl.exe --silent --show-error --head --max-time 8 --noproxy '*' --output NUL --write-out '%{http_code}' 'https://upos-sz-mirrorcos.bilivideo.com/'
if ($LASTEXITCODE -ne 0 -or $biliCheck -notmatch '^[234][0-9][0-9]$') {
    Write-Warning "Domestic video CDN probe failed (status: $biliCheck). Check if '国内网站' is routing to a proxy node."
} else {
    Write-Output "Domestic video CDN status: $biliCheck (direct reach ok)"
}
