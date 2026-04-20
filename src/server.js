//server.js
const WebSocket = require("ws");
const crypto = require("crypto");

const Room = require("./room");
const Player = require("./player");
const startGameLoop = require("./gameLoop");
const logger = require("./logger");

const wss = new WebSocket.Server({ port: 3000 });

const room = new Room();

logger.info("Server running on 3000");

/**
 * CONEXIÓN
 */
wss.on("connection", (ws) => {

  let playerId = crypto.randomUUID();

  logger.info('Client connected: ${playerId}');

  ws.on("message", (msg) => {
    try {
      const data = JSON.parse(msg);

      handleMessage(ws, playerId, data);
    } catch (error) {
      logger.error('Invalida JSON from: ${playerId}')
    }
  });

  ws.on("close", () => {
    room.removePlayer(playerId);
    logger.info('Client disconnected: ${playerId}')
  });

});

/**
 * MENSAJES
 */
function handleMessage(ws, id, data) {

  switch (data.type) {

    case "JOIN": {
      const player = new Player(id, data.name);

      room.addPlayer(player);

      if (room.isReady()) {
        room.setState("playing");
      }

      break;
    }

    case "MOVE": {
      const player = room.players.get(id);
      if (!player) return;

      if (data.left) player.x -= 5;
      if (data.right) player.x += 5;
      if (data.jump) player.y -= 10;

      break;
    }
  }
}

/**
 * BROADCAST
 */
function broadcast(data) {

  const msg = JSON.stringify(data);

  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(msg);
    }
  });
}

/**
 * GAME LOOP
 */
startGameLoop(room, broadcast);