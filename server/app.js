require("dotenv").config();
const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const path = require("path");
const fs = require("fs");
const winston = require("winston");

// --- CONFIGURACIÓN DEL LOGGER (Tu funcionalidad original) ---
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
    ),
    transports: [new winston.transports.Console()]
});

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// --- LECTURA DEL NIVEL (La nueva funcionalidad de Game Tools) ---
let levelData = {
    layer: null,
    spawn: { x: 100, y: 100 }
};

function loadGameLevel() {
    try {
        const gameDataRaw = fs.readFileSync(path.join(__dirname, 'game_data.json'), 'utf8');
        const gameData = JSON.parse(gameDataRaw);
        
        const firstLevel = gameData.levels[0];
        const firstLayer = firstLevel.layers[0];

        const tileMapRaw = fs.readFileSync(path.join(__dirname, firstLayer.tileMapFile), 'utf8');
        const tileMapJson = JSON.parse(tileMapRaw);

        const zonesRaw = fs.readFileSync(path.join(__dirname, firstLevel.zonesFile), 'utf8');
        const zonesJson = JSON.parse(zonesRaw);
        const playerZone = zonesJson.zones.find(z => z.type.includes("Player") || z.name.includes("Player"));

        levelData.layer = {
            tilesWidth: firstLayer.tilesWidth,
            tilesHeight: firstLayer.tilesHeight,
            tilesSheetFile: firstLayer.tilesSheetFile,
            tileMap: tileMapJson.tileMap
        };

        if (playerZone) {
            levelData.spawn = { x: playerZone.x, y: playerZone.y };
        }

        logger.info(`Nivel cargado correctamente: ${firstLevel.name} | Spawn: ${levelData.spawn.x}, ${levelData.spawn.y}`);
    } catch (err) {
        logger.error("Error cargando el nivel. Revisa game_data.json y los archivos de capa/zonas: " + err.message);
    }
}

// Ejecutamos la carga al arrancar
loadGameLevel();

// --- GESTIÓN DE JUGADORES Y WEBSOCKET ---
let players = {};
let nextId = 1;

wss.on("connection", (ws) => {
    const id = (nextId++).toString();
    logger.info(`[+] Jugador conectado: ID ${id}`);

    ws.on("message", (raw) => {
        const data = JSON.parse(raw);

        switch (data.type) {
            case "JOIN": {
                // Mantenemos la estructura de inputs de tu código original
                players[id] = { 
                    id: id, 
                    name: data.name, 
                    x: levelData.spawn.x, 
                    y: levelData.spawn.y, 
                    right: false, 
                    left: false, 
                    jump: false 
                };
                
                // Enviamos el mapa y el spawn a LibGDX
                ws.send(JSON.stringify({
                    type: "JOINED",
                    playerId: id,
                    spawnPosition: levelData.spawn,
                    layer: levelData.layer 
                }));
                break;
            }
            case "MOVE": {
                if (players[id]) {
                    // Actualizamos las teclas pulsadas (funcionalidad original)
                    if (data.right !== undefined) players[id].right = data.right;
                    if (data.left !== undefined) players[id].left = data.left;
                    if (data.jump !== undefined) players[id].jump = data.jump;
                }
                break;
            }
        }
    });

    ws.on("close", () => {
        logger.info(`[-] Jugador desconectado: ID ${id}`);
        delete players[id];
    });
});

// --- BUCLE DEL SERVIDOR (Físicas originales a 60 FPS) ---
setInterval(() => {
    let speed = 5; // La velocidad que tenías configurada
    let statePlayers = [];

  for (let key in players) {
          let p = players[key];
          
          // Físicas de movimiento
          if (p.right) p.x += speed;
          if (p.left) p.x -= speed;
          if (p.jump) p.y += speed * 2; 

          // EL CHIVATO: Imprimir solo si se está moviendo
          if (p.right || p.left || p.jump) {
              console.log(`Jugador ${p.name} se mueve a: X=${p.x}, Y=${p.y}`);
          }

          statePlayers.push({ id: p.id, name: p.name, x: p.x, y: p.y });
    }

    // Broadcast a todos los jugadores
    const stateMsg = JSON.stringify({ type: "STATE", players: statePlayers });
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(stateMsg);
        }
    });
}, 1000 / 60);

// --- ARRANQUE DEL SERVIDOR ---
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    logger.info(`Server running on port ${PORT}`);
});