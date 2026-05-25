<#
.SYNOPSIS
  Rebuild the HRF fork as a minified static bundle and (optionally) deploy it to Vercel.

.DESCRIPTION
  Scala.js can't build on Vercel, so the flow is: build locally, then upload a
  prebuilt static folder. This script:
    1. Locates the Temurin JDK + sbt and sets a large heap (Closure needs it).
    2. Runs `sbt fullOptJS` in haunt-roll-fail -> target/scala-2.13/hrf-opt.js (~8 MB).
    3. Copies hrf-opt.js over hrf-fastopt.js, the name index.html loads.
    4. Refreshes ./playhere (index.html + the minified JS). vercel.json is left intact.
    5. With -Deploy, runs `vercel deploy --prod --yes` from ./playhere.

  Prereq for step 1: `sbt publishLocal` has been run once in scala-js-dom-reduced
  (publishes the scalajs-dom 2.8.0-SNAPSHOT dependency to ~/.ivy2/local).

.EXAMPLE
  ./build-and-deploy.ps1            # build + package only
  ./build-and-deploy.ps1 -Deploy   # build + package + deploy to Vercel prod
#>
param(
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$game = Join-Path $root 'haunt-roll-fail'
$dist = Join-Path $root 'playhere'
$jsRel = 'target\scala-2.13\hrf-fastopt.js'

# --- locate toolchain ---
$adoptium = 'C:\Program Files\Eclipse Adoptium'
$jdk = Get-ChildItem $adoptium -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue |
       Sort-Object Name -Descending | Select-Object -First 1
if (-not $jdk) { throw "No Temurin JDK found under $adoptium. Install one (winget install EclipseAdoptium.Temurin.21.JDK)." }
$env:JAVA_HOME = $jdk.FullName

$sbtBin = 'C:\Program Files (x86)\sbt\bin'
if (-not (Test-Path (Join-Path $sbtBin 'sbt.bat'))) { throw "sbt not found at $sbtBin. Install it (winget install sbt.sbt)." }

$env:Path = "$($env:JAVA_HOME)\bin;$sbtBin;$($env:Path)"
$env:SBT_OPTS = '-Dsbt.log.noformat=true -Xmx6g -XX:+UseG1GC'

Write-Host "JDK : $($env:JAVA_HOME)"
Write-Host "sbt : $sbtBin"

# --- build (Closure-minified) ---
Push-Location $game
try {
    Write-Host "`n=== sbt fullOptJS ===" -ForegroundColor Cyan
    sbt fullOptJS
    if ($LASTEXITCODE -ne 0) { throw "fullOptJS failed (exit $LASTEXITCODE)" }
}
finally { Pop-Location }

# index.html loads hrf-fastopt.js; fullOpt emits hrf-opt.js -> copy over it.
$optJs = Join-Path $game 'target\scala-2.13\hrf-opt.js'
Copy-Item $optJs (Join-Path $game $jsRel) -Force
$mb = (Get-Item (Join-Path $game $jsRel)).Length / 1MB
Write-Host ("Minified bundle: {0:N1} MB" -f $mb) -ForegroundColor Green

# --- refresh deploy folder (vercel.json untouched) ---
New-Item -ItemType Directory -Force (Join-Path $dist 'target\scala-2.13') | Out-Null
Copy-Item (Join-Path $game 'index.html')            (Join-Path $dist 'index.html') -Force
Copy-Item (Join-Path $game $jsRel)                  (Join-Path $dist $jsRel)        -Force
if (-not (Test-Path (Join-Path $dist 'vercel.json'))) {
    throw "Missing $dist\vercel.json (the proxy rewrites). Restore it before deploying."
}
Write-Host "Packaged -> $dist" -ForegroundColor Green

# --- optional deploy ---
if ($Deploy) {
    $npmBin = (npm prefix -g)
    if ($npmBin) { $env:Path = "$npmBin;$($env:Path)" }
    Push-Location $dist
    try {
        Write-Host "`n=== vercel deploy --prod ===" -ForegroundColor Cyan
        vercel deploy --prod --yes
        if ($LASTEXITCODE -ne 0) { throw "vercel deploy failed (exit $LASTEXITCODE)" }
    }
    finally { Pop-Location }
}
else {
    Write-Host "`nBuild ready. To deploy: ./build-and-deploy.ps1 -Deploy  (or: cd playhere; vercel --prod)" -ForegroundColor Yellow
}
