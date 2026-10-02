# Prepare le dossier a publier sur Netlify :
#   site-web/                     landing page
#   site-web/app/                 application web (Flutter)
#   site-web/AtelierCouture.apk   application Android (si presente)
# puis cree site-web.zip.
#
# Usage (PowerShell, depuis ce dossier) :  .\preparer-site.ps1
# Ajouter -AvecApk pour recompiler aussi l'APK Android.
# (Fichier volontairement sans accents : Windows PowerShell 5.1 lit mal l'UTF-8 sans BOM.)
param([switch]$AvecApk)

$ErrorActionPreference = 'Stop'
$racine = $PSScriptRoot
$app = Join-Path $racine 'app'
$sortie = Join-Path $racine 'site-web'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { $env:Path += ';E:\flutter\bin' }

Push-Location $app
try {
  Write-Host 'Compilation de l application web...'
  flutter build web --release --base-href /app/ --dart-define-from-file=config.json --no-wasm-dry-run
  if ($LASTEXITCODE -ne 0) { throw 'Echec de la compilation web' }
  if ($AvecApk) {
    Write-Host 'Compilation de l APK Android...'
    flutter build apk --release --dart-define-from-file=config.json
    if ($LASTEXITCODE -ne 0) { throw 'Echec de la compilation Android' }
    Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' (Join-Path $racine 'AtelierCouture.apk') -Force
  }
} finally {
  Pop-Location
}

if (Test-Path $sortie) { Remove-Item $sortie -Recurse -Force }
New-Item -ItemType Directory $sortie | Out-Null
Copy-Item (Join-Path $racine 'landing\*') $sortie -Recurse
Copy-Item (Join-Path $app 'build\web') (Join-Path $sortie 'app') -Recurse
$apk = Join-Path $racine 'AtelierCouture.apk'
if (Test-Path $apk) { Copy-Item $apk $sortie }

$zip = Join-Path $racine 'site-web.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $sortie '*') -DestinationPath $zip
Write-Host "Pret : $sortie (et site-web.zip), a glisser sur Netlify (onglet Deploys)."
