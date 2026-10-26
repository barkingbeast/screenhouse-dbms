$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Test-Path -LiteralPath '.env')) { Copy-Item -LiteralPath '.env.example' -Destination '.env' }
if (-not (Test-Path -LiteralPath 'node_modules/pg')) { npm install; if ($LASTEXITCODE -ne 0) { throw 'npm install failed' } }
docker compose up -d --wait
if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop and try again' }
npm run setup
if ($LASTEXITCODE -ne 0) { throw 'Database setup failed' }
npm start
