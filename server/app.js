const WebSocket = require("ws");
const crypto = require("crypto");
require("dotenv").config();

const Room = require("./room");
const Player = require("./player");
const startGameLoop = require("./gameLoop");
const logger = require("./logger");

const SERVER_PORT = process.env.SERVER_PORT || 3000;

const wss = new WebSocket.Server({ port: SERVER_PORT});
const room = new Room();

logger.info(`Server running on ws://localhost:${SERVER_PORT}`);

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

      const player = new Player(id, name, ws);
      const added = room.addPlayer(player);

      if (!added) {
        ws.send(JSON.stringify({ type: "ERROR", message: "Room is full" }));
        return;
      }

      ws.send(
        JSON.stringify({
          type: "JOINED",
          playerId: id,
          name: player.name,
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

      player.input.left = !!data.left;
      player.input.right = !!data.right;
      player.input.jump = !!data.jump;

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