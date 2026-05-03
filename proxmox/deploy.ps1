$ErrorActionPreference = "Stop"

$ORIGINAL_DIR = Get-Location

function Escape-SingleQuotes {
    param([string]$Text)
    return $Text -replace "'", "'\''"
}

try {
    # Cargar config.env
    $configPath = ".\config.env"

    if (!(Test-Path $configPath)) {
        Write-Host "Error: No s'ha trobat config.env" -ForegroundColor Red
        exit 1
    }

    Get-Content $configPath | ForEach-Object {
        $line = $_.Trim()

        if ($line -eq "" -or $line.StartsWith("#")) {
            return
        }

        if ($line -match "^\s*([^=]+)\s*=\s*(.*)\s*$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"').Trim("'")
            Set-Variable -Name $name -Value $value -Scope Script
        }
    }

    $USER = if ($args.Count -ge 1 -and $args[0]) { $args[0] } else { $DEFAULT_USER }
    $RSA_PATH = if ($args.Count -ge 2 -and $args[1]) { $args[1] } else { $DEFAULT_RSA_PATH }
    $SERVER_PORT = if ($args.Count -ge 3 -and $args[2]) { $args[2] } else { $DEFAULT_SERVER_PORT }

    $RSA_PATH = $RSA_PATH.Trim()
    $RSA_PATH = $RSA_PATH -replace '^\$HOME', $HOME
    $RSA_PATH = $RSA_PATH -replace '^~', $HOME

    $HOST_NAME = "ieticloudpro.ieti.cat"
    $PORT_SSH = "20127"
    $ZIP_NAME = "server-package.zip"
    $REMOTE_SCRIPT_NAME = "remote-deploy-oceanpark.sh"

    if (!(Test-Path $RSA_PATH)) {
        Write-Host "Error: No s'ha trobat la clau privada: $RSA_PATH" -ForegroundColor Red
        exit 1
    }

    $securePwd = Read-Host "Pwd sudo remota" -AsSecureString
    $SUDO_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
    )

    Set-Location ..

    if (Test-Path $ZIP_NAME) {
        Remove-Item $ZIP_NAME -Force
    }

    if (Test-Path $REMOTE_SCRIPT_NAME) {
        Remove-Item $REMOTE_SCRIPT_NAME -Force
    }

    # Crear ZIP compatible con Linux usando tar.exe
    tar.exe -a -cf $ZIP_NAME `
        --exclude=./proxmox `
        --exclude=./node_modules `
        --exclude=./data `
        --exclude=./.git `
        --exclude=./.gitignore `
        --exclude=./server-package.zip `
        --exclude=./remote-deploy-oceanpark.sh `
        .

    $remoteScript = @'
#!/bin/bash
set -e

SERVER_PORT="$1"
APP_DIR="$HOME/nodejs_server"
PKG="$HOME/server-package.zip"
TMP_DIR="$(mktemp -d)"

export PATH="$HOME/.npm-global/bin:/usr/local/bin:$PATH"

sudo_cmd() {
  echo "$SUDO_PWD" | sudo -S "$@"
}

echo "Puerto servidor: $SERVER_PORT"
echo "Directorio app: $APP_DIR"

mkdir -p "$APP_DIR"
cd "$APP_DIR"

if command -v pm2 >/dev/null 2>&1; then
  pm2 delete app >/dev/null 2>&1 || true
fi

for i in {1..10}; do
  ss -tln | grep -q ":$SERVER_PORT " && sleep 1 || break
done

find "$APP_DIR" -mindepth 1 -maxdepth 1 -name "data" -prune -o -exec rm -rf {} + 2>/dev/null || true

if ! command -v unzip >/dev/null 2>&1; then
  sudo_cmd apt-get update
  sudo_cmd apt-get install -y unzip
fi

if ! command -v rsync >/dev/null 2>&1; then
  sudo_cmd apt-get update
  sudo_cmd apt-get install -y rsync
fi

test -f "$PKG"

unzip -q -o "$PKG" -d "$TMP_DIR"
rm -f "$PKG"

if [[ -f "$TMP_DIR/package.json" ]]; then
  rsync -a --delete "$TMP_DIR/" "$APP_DIR/"
elif [[ -f "$TMP_DIR/nodejs_server/package.json" ]]; then
  rsync -a --delete "$TMP_DIR/nodejs_server/" "$APP_DIR/"
elif [[ -f "$TMP_DIR/nodejs_web/package.json" ]]; then
  rsync -a --delete "$TMP_DIR/nodejs_web/" "$APP_DIR/"
else
  echo "Error: no trobo package.json dins del zip"
  echo "Contenido del ZIP descomprimido:"
  find "$TMP_DIR" -maxdepth 3 -type f | head -50
  exit 1
fi

rm -rf "$TMP_DIR"

cd "$APP_DIR"
test -f package.json

npm install --omit=dev

sudo_cmd npm install -g pm2

pm2 start server/app.js --name app --update-env
pm2 save

echo "Deploy correcte. Estat PM2:"
pm2 status
'@

    $remoteScript = $remoteScript -replace "`r`n", "`n"
    $remoteScript = $remoteScript -replace "`r", "`n"

    [System.IO.File]::WriteAllText(
        (Join-Path (Get-Location) $REMOTE_SCRIPT_NAME),
        $remoteScript,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "Subiendo ZIP..."
    scp -i "$RSA_PATH" -P $PORT_SSH -o UpdateHostKeys=no "$ZIP_NAME" "${USER}@${HOST_NAME}:~/server-package.zip"

    Write-Host "Subiendo script remoto..."
    scp -i "$RSA_PATH" -P $PORT_SSH -o UpdateHostKeys=no "$REMOTE_SCRIPT_NAME" "${USER}@${HOST_NAME}:~/remote-deploy-oceanpark.sh"

    Remove-Item $ZIP_NAME -Force
    Remove-Item $REMOTE_SCRIPT_NAME -Force

    $escapedPwd = Escape-SingleQuotes $SUDO_PASSWORD

    Write-Host "Ejecutando deploy remoto..."
    ssh -i "$RSA_PATH" -p $PORT_SSH -o UpdateHostKeys=no "${USER}@${HOST_NAME}" `
    "chmod +x ~/remote-deploy-oceanpark.sh && SUDO_PWD='$escapedPwd' bash ~/remote-deploy-oceanpark.sh '$SERVER_PORT'"

    if ($LASTEXITCODE -ne 0) {
        throw "El deploy remoto ha fallado."
    }

    Write-Host "Deploy terminado."
}
finally {
    Set-Location $ORIGINAL_DIR
}