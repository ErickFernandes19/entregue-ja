
$ErrorActionPreference = "Stop"

$flutterPath = "C:\FlutterProjects\flutter_3_50\bin\flutter.bat"
$buildIndexPath = "build\web\index.html"

if (-not (Test-Path $flutterPath)) {
    throw "Flutter 3.50 nao encontrado."
}

if ([string]::IsNullOrWhiteSpace($env:GOOGLE_MAPS_WEB_KEY)) {
    throw "A variavel GOOGLE_MAPS_WEB_KEY nao foi configurada."
}

& $flutterPath build web --release --no-tree-shake-icons --no-wasm-dry-run --dart-define="API_BASE_URL=https://entregue-ja-production.up.railway.app" --dart-define="GOOGLE_MAPS_API_KEY=$env:GOOGLE_MAPS_WEB_KEY"

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

Write-Host "Flutter Web compilado com sucesso."
Write-Host "Google Maps Web configurado."
Write-Host "URL do Railway configurada."
Write-Host "Icones Material preservados."
