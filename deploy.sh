#!/bin/bash

# Configuración
SERVER_USER="pico3"
SERVER_HOST="ieticloudpro.ieti.cat"
SERVER_PORT="20127"
APP_NAME="oceanpark-server"
REMOTE_DIR="~/${APP_NAME}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Iniciando despliegue de OceanPark Server${NC}"
echo "================================================"

# 1. Crear .env para producción
echo -e "${YELLOW}📝 Creando .env para producción...${NC}"
cat > .env.production << EOF
PORT=3000
NODE_ENV=production
MONGODB_URI=mongodb://localhost:27017/oceanpark
EOF

# 2. Crear archivo comprimido
echo -e "${YELLOW}📦 Empaquetando archivos...${NC}"
tar -czf deploy.tar.gz \
  src/ \
  package.json \
  ecosystem.config.js \
  .env.production \
  --exclude=node_modules \
  --exclude=.git \
  --exclude=logs \
  --exclude=*.tar.gz \
  --exclude=.env

if [ ! -f deploy.tar.gz ]; then
    echo -e "${RED}❌ Error al crear el archivo comprimido${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Archivo creado: deploy.tar.gz ($(du -h deploy.tar.gz | cut -f1))${NC}"

# 3. Copiar al servidor
echo -e "${YELLOW}📤 Subiendo archivo al servidor...${NC}"
scp -P ${SERVER_PORT} deploy.tar.gz ${SERVER_USER}@${SERVER_HOST}:~/

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error al subir el archivo${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Archivo subido correctamente${NC}"

# 4. Ejecutar comandos en el servidor
echo -e "${YELLOW}🔧 Configurando servidor remoto...${NC}"
ssh -p ${SERVER_PORT} ${SERVER_USER}@${SERVER_HOST} << 'ENDSSH'
    # Configuración
    APP_NAME="oceanpark-server"
    REMOTE_DIR="$HOME/$APP_NAME"
    
    echo "📁 Preparando directorio $REMOTE_DIR..."
    mkdir -p $REMOTE_DIR
    cd $REMOTE_DIR
    
    # ============ VERIFICAR Y DETENER SERVIDOR ============
    echo "🛑 Verificando si el servidor está corriendo..."
    
    if command -v pm2 &> /dev/null; then
        if pm2 list | grep -q "$APP_NAME"; then
            echo "⚠️ Servidor encontrado en ejecución. Deteniendo..."
            pm2 stop $APP_NAME
            pm2 delete $APP_NAME
            echo "✅ Servidor detenido"
        else
            echo "✅ No hay servidor en ejecución"
        fi
    else
        echo "📦 PM2 no instalado, se instalará después"
    fi
    
    # ============ DESPLEGAR NUEVA VERSIÓN ============
    echo "📦 Extrayendo archivos..."
    tar -xzf ~/deploy.tar.gz
    mv .env.production .env
    rm ~/deploy.tar.gz
    
    echo "📦 Instalando dependencias..."
    npm install --production
    
    # ============ VERIFICAR MONGODB ============
    echo "🗄️ Verificando MongoDB..."
    if ! systemctl is-active --quiet mongodb; then
        echo "⚠️ MongoDB no está corriendo, iniciando..."
        sudo systemctl start mongodb
        sleep 2
    fi
    
    if systemctl is-active --quiet mongodb; then
        echo "✅ MongoDB está activo"
    else
        echo "❌ Error: MongoDB no pudo iniciarse"
        exit 1
    fi
    
    # ============ INSTALAR PM2 SI NO EXISTE ============
    if ! command -v pm2 &> /dev/null; then
        echo "📦 Instalando PM2..."
        sudo npm install -g pm2
    fi
    
    # ============ INICIAR SERVIDOR ============
    echo "🚀 Iniciando servidor..."
    pm2 start ecosystem.config.js
    
    # Esperar a que inicie
    sleep 3
    
    # Verificar que está corriendo
    if pm2 list | grep -q "$APP_NAME.*online"; then
        echo "✅ Servidor iniciado correctamente"
    else
        echo "❌ Error: El servidor no pudo iniciarse"
        pm2 logs $APP_NAME --lines 10 --nostream
        exit 1
    fi
    
    pm2 save
    
    # ============ VERIFICAR QUE RESPONDE ============
    echo "🔍 Verificando que el servidor responde..."
    sleep 2
    
    if curl -s http://localhost:3000/status > /dev/null; then
        echo "✅ Servidor respondiendo correctamente"
    else
        echo "⚠️ El servidor no responde en el puerto 3000"
        echo "📝 Últimas líneas del log:"
        pm2 logs $APP_NAME --lines 10 --nostream
    fi
    
    echo ""
    echo -e "\033[0;32m✅ ¡Despliegue completado en el servidor!\033[0m"
    echo ""
    echo "📊 Estado de la aplicación:"
    pm2 status
    
    echo ""
    echo "📝 Últimas líneas del log:"
    pm2 logs $APP_NAME --lines 10 --nostream
    
    echo ""
    echo "🌐 Conexiones activas:"
    curl -s http://localhost:3000/status | python3 -m json.tool 2>/dev/null || echo "No se pudo obtener estado"
ENDSSH

# 5. Limpiar archivos locales
echo ""
echo -e "${YELLOW}🧹 Limpiando archivos temporales...${NC}"
rm deploy.tar.gz
rm .env.production

echo ""
echo "================================================"
echo -e "${GREEN}✨ ¡Despliegue y reinicio completado exitosamente!${NC}"
echo ""
echo -e "${BLUE}🌐 Servidor disponible en: ws://${SERVER_HOST}:3000${NC}"
echo -e "${BLUE}📊 Estado en: http://${SERVER_HOST}:3000/status${NC}"