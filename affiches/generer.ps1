# Genere les affiches (PNG pour les reseaux sociaux, PDF A4 pour l'impression)
# a partir de affiche-fr.html et affiche-en.html, avec Google Chrome.
# Usage : .\generer.ps1
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$dossier = $PSScriptRoot
$profil = Join-Path $env:TEMP 'chrome-affiches'

function Rendre([string[]]$arguments) {
  # Chaque rendu attend la fin du precedent (meme profil Chrome).
  Start-Process -FilePath $chrome -ArgumentList $arguments -Wait -WindowStyle Hidden
}

foreach ($langue in 'fr', 'en') {
  $url = 'file:///' + ((Join-Path $dossier "affiche-$langue.html") -replace '\\', '/')
  $commun = @('--headless=new', '--disable-gpu', "--user-data-dir=`"$profil`"", '--virtual-time-budget=8000')
  Rendre ($commun + @('--hide-scrollbars', '--window-size=1240,1754',
    "--screenshot=`"$dossier\Atelier-Couture-affiche-$langue.png`"", $url))
  Rendre ($commun + @('--no-pdf-header-footer', "--print-to-pdf=`"$dossier\Atelier-Couture-affiche-$langue.pdf`"", $url))
  # Format Statut WhatsApp (vertical 1080 x 1920)
  $statut = 'file:///' + ((Join-Path $dossier 'statut.html') -replace '\\', '/') + "?lang=$langue"
  Rendre ($commun + @('--hide-scrollbars', '--window-size=1080,1920',
    "--screenshot=`"$dossier\Atelier-Couture-statut-$langue.png`"", $statut))
}
Get-ChildItem $dossier -Filter 'Atelier-Couture-*' | Select-Object Name, Length
