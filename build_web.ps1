
$ErrorActionPreference = "Stop"

$indexPath = "web\index.html"
$buildIndexPath = "build\web\index.html"

if (-not $env:GOOGLE_MAPS_WEB_KEY) {
    throw "A variavel GOOGLE_MAPS_WEB_KEY nao foi configurada."
}

flutter build web --release --dart-define=API_BASE_URL=https://entregue-ja-production.up.railway.app

if ($LASTEXITCODE -ne 0) {
    throw "Falha na compilacao do Flutter Web."
}

$content = [System.IO.File]::ReadAllText((Resolve-Path $buildIndexPath))

if (-not $content.Contains("GOOGLE_MAPS_WEB_KEY")) {
    throw "Marcador GOOGLE_MAPS_WEB_KEY nao encontrado no HTML compilado."
}

$content = $content.Replace("GOOGLE_MAPS_WEB_KEY", $env:GOOGLE_MAPS_WEB_KEY)

[System.IO.File]::WriteAllText(
    (Resolve-Path $buildIndexPath),
    $content
)

Write-Host "Flutter Web compilado com a chave do Google Maps."
