const WebSocket = require("ws");
const crypto = require("crypto");
const fs = require("fs"); // Importamos el sistema de archivos
const path = require("path"); // Importamos manejador de rutas
require("dotenv").config();

const Room = require("./room");
const Player = require("./player");
const startGameLoop = require("./gameLoop");
const logger = require("./logger");

const SERVER_PORT = process.env.SERVER_PORT || 3000;

const wss = new WebSocket.Server({ port: SERVER_PORT });
const room = new Room();

// --- 1. CARGAR LOS DATOS DEL NIVEL ---
const layerPath = path.join(__dirname, 'level_000_layer_000.json');
const zonesPath = path.join(__dirname, 'level_000_zones.json');

// Leemos la matriz del mapa y las zonas
const layerData = JSON.parse(fs.readFileSync(layerPath, 'utf8'));
const zonesData = JSON.parse(fs.readFileSync(zonesPath, 'utf8'));

// Buscamos las coordenadas de inicio del Player Zone
const playerZone = zonesData.zones.find(z => z.type === "Player Zone");
const spawnX = playerZone ? playerZone.x : 100; // Será 25 según tu JSON
const spawnY = playerZone ? playerZone.y : 100; // Será 100 según tu JSON

logger.info(`Server running on ${SERVER_PORT}. Spawn: [${spawnX}, ${spawnY}]`);

/**
 * CONEXIÓN
 */
wss.on("connection", (ws) => {
  const playerId = crypto.randomUUID();

  logger.info(`Client connected: ${playerId}`);

  ws.on("message", (msg) => {
    try {
      const data = JSON.parse(msg);
      handleMessage(ws, playerId, data);
    } catch (error) {
      logger.error(`Invalid JSON from: ${playerId}`);
    }
  });

  ws.on("close", () => {
    room.removePlayer(playerId);

    if (!room.isReady()) {
      room.setState("waiting");
    }

    logger.info(`Client disconnected: ${playerId}`);
  });

  ws.on("error", (error) => {
    logger.error(`Socket error from ${playerId}: ${error.message}`);
  });
});

/**
 * MENSAJES
 */
function handleMessage(ws, id, data) {
  if (!data || typeof data.type !== "string") {
    ws.send(JSON.stringify({ type: "ERROR", message: "Invalid message format" }));
    return;
  }

  switch (data.type) {
case "JOIN": {
      if (room.players.has(id)) {
        ws.send(JSON.stringify({ type: "ERROR", message: "Player already joined" }));
        return;
      }

      const name =
        typeof data.name === "string" && data.name.trim()
          ? data.name.trim()
          : "Anonymous";

      // 1. Pasamos spawnX y spawnY al crear el jugador
      const player = new Player(id, name, ws, spawnX, spawnY);
      const added = room.addPlayer(player);

      if (!added) {
        ws.send(JSON.stringify({ type: "ERROR", message: "Room is full" }));
        return;
      }

      // 2. Le enviamos la confirmación al cliente JUNTO con el mapa y su posición inicial
      ws.send(
        JSON.stringify({
          type: "JOINED",
          playerId: id,
          name: player.name,
          map: layerData.tileMap, // Enviamos la matriz del mapa del JSON
          spawnPosition: { x: spawnX, y: spawnY } // Le decimos dónde aparece
        })
      );

      if (room.isReady() && room.state !== "playing") {
        room.setState("playing");
        logger.info("Room state changed to playing");
      }

      break;
    }

    case "MOVE": {
      const player = room.players.get(id);
      if (!player) {
        ws.send(JSON.stringify({ type: "ERROR", message: "Player not found" }));
        return;
      }

      const JUMP_FORCE = -12;
      const GROUND_Y = 100;

      // movimiento horizontal
      if (data.left) player.vx = -5;
      else if (data.right) player.vx = 5;
      else player.vx = 0;

      // salto real (solo si está en el suelo)
      if (data.jump && player.y >= GROUND_Y) {
        player.vy = JUMP_FORCE;
      }

      break;
    }

    default:
      ws.send(JSON.stringify({ type: "ERROR", message: "Unknown message type" }));
      break;
  }
}

/**
 * BROADCAST (usando players en vez de wss.clients)
 */
function broadcast(data) {
  const msg = JSON.stringify(data);

  room.players.forEach((player) => {
    if (player.ws.readyState === WebSocket.OPEN) {
      player.ws.send(msg);
    }
  });
}

/**
 * GAME LOOP
 */
startGameLoop(room, broadcast);