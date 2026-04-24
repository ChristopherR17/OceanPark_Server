const WebSocket = require("ws");
const crypto = require("crypto");
require("dotenv").config();

// Módulos internos
const Room = require("./room");
const Player = require("./player");
const startGameLoop = require("./gameLoop");
const logger = require("./logger");

// Configuración del puerto (3000 por defecto en Proxmox)
const SERVER_PORT = process.env.SERVER_PORT || 3000;

// Inicialización
const wss = new WebSocket.Server({ port: SERVER_PORT, host: '0.0.0.0' });
const room = new Room();

logger.info(`🚀 Servidor OceanPark iniciado en puerto ${SERVER_PORT}`);
logger.info(`🌐 Esperando conexiones en wss://pico3.ieti.site`);

/**
 * GESTIÓN DE CONEXIONES
 */
  wss.on("connection", (ws) => {
    const playerId = crypto.randomUUID();
    
    // LOG: Conexión técnica inicial
    logger.info(`🔌 Socket abierto: ID temporal ${playerId}`);

    ws.on("message", (msg) => {
      try {
        const data = JSON.parse(msg);
        handleMessage(ws, playerId, data);
      } catch (error) {
        logger.error(`❌ Error JSON de ${playerId}: ${error.message}`);
      }
    });

  ws.on("close", () => {
    const player = room.players.get(playerId);
    if (player) {
      logger.info(`[-] JUGADOR SALIÓ: ${player.name} (${playerId})`);
      room.removePlayer(playerId);
    } else {
      logger.info(`[-] Socket cerrado sin registro: ${playerId}`);
    }

    if (!room.isReady()) {
      room.setState("waiting");
      logger.info("💤 Sala en espera: No hay jugadores activos.");
    }
  });

  ws.on("error", (error) => {
    logger.error(`⚠️ Error en socket ${playerId}: ${error.message}`);
  });
});

/**
 * LÓGICA DE MENSAJES
 */
function handleMessage(ws, id, data) {
  if (!data || typeof data.type !== "string") return;

  switch (data.type) {
    case "JOIN": {
      if (room.players.has(id)) return;

      const name = (typeof data.name === "string" && data.name.trim()) 
                   ? data.name.trim() 
                   : "Anonymous";

      // LOG: Identificar si es el visor o un jugador de LibGDX
      const isVisor = name.toLowerCase().includes("visor");
      const icon = isVisor ? "👁️ " : "🎮 ";
      logger.info(`${icon} NUEVO ${isVisor ? 'VISOR' : 'JUGADOR'}: "${name}" (ID: ${id})`);

      const player = new Player(id, name, ws);
      const added = room.addPlayer(player);

      if (!added) {
        logger.error(`🚫 Sala llena. No se pudo añadir a ${name}`);
        ws.send(JSON.stringify({ type: "ERROR", message: "Room is full" }));
        return;
      }

      // Enviar confirmación y datos del mapa
      ws.send(JSON.stringify({
        type: "JOINED",
        playerId: id,
        name: player.name,
        spawnPosition: room.levelData.spawn,
        layer: room.levelData.layer
      }));

      if (room.isReady() && room.state !== "playing") {
        room.setState("playing");
        logger.info("🎬 Estado de la sala: PLAYING (Iniciando GameLoop)");
      }
      break;
    }

  case "MOVE": {
        const player = room.players.get(id);
        if (player) {
          // Guardamos el estado anterior para comparar
          const prevLeft = player.input.left;
          const prevRight = player.input.right;
          const prevJump = player.input.jump;

          // Persistente
          player.input.left = !!data.left;
          player.input.right = !!data.right;

          // Evento
          if (data.jump) {
            player.input.jump = true;
          }

          // LOG INTELIGENTE: Solo avisa si algo ha cambiado
          if (prevLeft !== player.input.left || prevRight !== player.input.right || (data.jump && !prevJump)) {
              // Creamos un texto visual de qué está haciendo
              let accion = [];
              if (player.input.left) accion.push("⬅️ Izquierda");
              if (player.input.right) accion.push("➡️ Derecha");
              if (data.jump) accion.push("⬆️ Salto");
              if (accion.length === 0) accion.push("🛑 Parado");

              logger.info(`🏃 ${player.name} acción: ${accion.join(" + ")}`);
          }
        }
        break;
    }

    default:
      logger.info(`❓ Mensaje desconocido de ${id}: ${data.type}`);
      break;
  }
}

/**
 * TRANSMISIÓN (BROADCAST)
 */
function broadcast(data) {
  const msg = JSON.stringify(data);
  room.players.forEach((player) => {
    if (player.ws.readyState === WebSocket.OPEN) {
      player.ws.send(msg);
    }
  });
}

// Iniciar el ciclo de juego
startGameLoop(room, broadcast);