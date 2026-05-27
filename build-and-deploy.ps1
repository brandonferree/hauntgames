<#
.SYNOPSIS
  Rebuild the HRF fork as a minified static bundle and (optionally) deploy it to
  Cloudflare Pages (project "meeples", https://meeples.pages.dev).

.DESCRIPTION
  Scala.js can't build on Cloudflare, so the flow is: build locally, then upload a
  prebuilt static folder. This script:
    1. Locates the Temurin JDK + sbt and sets a large heap (Closure needs it).
    2. Runs `sbt fullOptJS` in haunt-roll-fail -> target/scala-2.13/hrf-opt.js (~8 MB).
    3. Copies hrf-opt.js over hrf-fastopt.js, the name index.html loads.
    4. Refreshes ./cf-pages (index.html + the minified JS). _worker.js is left intact
       (it serves static files and proxies missing art/fonts to hrf.im).
    5. With -Deploy, runs `wrangler pages deploy cf-pages --project-name=meeples`.

  Prereqs:
    - `sbt publishLocal` has been run once in scala-js-dom-reduced (publishes the
      scalajs-dom 2.8.0-SNAPSHOT dependency to ~/.ivy2/local).
    - `wrangler` is installed and logged in (`wrangler login`).
    - Access (Google SSO) on meeples.pages.dev is managed in the Cloudflare Zero
      Trust dashboard, not here.

.EXAMPLE
  ./build-and-deploy.ps1            # build + package only
  ./build-and-deploy.ps1 -Deploy   # build + package + deploy to Cloudflare Pages
#>
param(
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$game = Join-Path $root 'haunt-roll-fail'
$dist = Join-Path $root 'cf-pages'
$jsRel = 'target\scala-2.13\hrf-fastopt.js'
$project = 'meeples'

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

# --- refresh deploy folder (_worker.js untouched) ---
New-Item -ItemType Directory -Force (Join-Path $dist 'target\scala-2.13') | Out-Null
Copy-Item (Join-Path $game 'index.html')            (Join-Path $dist 'index.html') -Force
Copy-Item (Join-Path $game $jsRel)                  (Join-Path $dist $jsRel)        -Force
if (-not (Test-Path (Join-Path $dist '_worker.js'))) {
    throw "Missing $dist\_worker.js (the static-server + hrf.im proxy). Restore it before deploying."
}
Write-Host "Packaged -> $dist" -ForegroundColor Green

# --- optional deploy ---
if ($Deploy) {
    Write-Host "`n=== wrangler pages deploy ($project) ===" -ForegroundColor Cyan
    wrangler pages deploy $dist --project-name=$project --branch=main --commit-dirty=true
    if ($LASTEXITCODE -ne 0) { throw "wrangler pages deploy failed (exit $LASTEXITCODE)" }
}
else {
    Write-Host "`nBuild ready. To deploy: ./build-and-deploy.ps1 -Deploy  (or: wrangler pages deploy cf-pages --project-name=$project)" -ForegroundColor Yellow
}
