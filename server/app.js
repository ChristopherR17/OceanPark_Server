const WebSocket = require("ws");
const crypto = require("crypto");
require("dotenv").config();

// Módulos internos
const Room = require("./room");
const Player = require("./player");
const startGameLoop = require("./gameLoop");
const logger = require("./logger");
const GameWorld = require("./gameWorld");

// Configuración
const SERVER_PORT = process.env.SERVER_PORT || 3000;
const MAX_PLAYERS = 8;
const MIN_PLAYERS_TO_START = 1; // Cambiar a 2 para forzar cooperativo

// Inicialización
const wss = new WebSocket.Server({ port: SERVER_PORT, host: '0.0.0.0' });
const room = new Room();
const world = new GameWorld(room);

logger.info(`🚀 Servidor OceanPark iniciado en puerto ${SERVER_PORT}`);
logger.info(`🌐 Esperando conexiones en wss://pico3.ieti.site`);

/**
 * GESTIÓN DE CONEXIONES
 */
wss.on("connection", (ws) => {
    const playerId = crypto.randomUUID();
    logger.info(`🔌 Socket abierto: ID temporal ${playerId}`);

    ws.on("message", (msg) => {
        try {
            const data = JSON.parse(msg);
            handleMessage(ws, playerId, data);
        } catch (error) {
            logger.error(`❌ Error JSON de ${playerId}: ${error.message}`);
            ws.send(JSON.stringify({ 
                type: "ERROR", 
                message: "Formato JSON inválido" 
            }));
        }
    });

    ws.on("close", () => {
        const player = room.players.get(playerId);
        if (player) {
            logger.info(`[-] JUGADOR SALE: ${player.name} (${playerId})`);
            
            // Si tenía la llave, soltarla
            if (world.keyHolder === playerId) {
                world.dropKey(player);
            }
            
            room.removePlayer(playerId);
            
            // Notificar a todos
            broadcastPlayersList();
            
            if (!room.isReady()) {
                room.setState("waiting");
                logger.info("💤 Sala en espera: No hay jugadores activos.");
            }
        } else {
            logger.info(`[-] Socket cerrado sin registro: ${playerId}`);
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
        case "JOIN":
            handleJoin(ws, id, data);
            break;

        case "MOVE":
            handleMove(id, data);
            break;

        case "LEAVE":
            handleLeave(id);
            break;

        case "GET_STATE":
            handleGetState(ws);
            break;

        default:
            logger.info(`❓ Mensaje desconocido de ${id}: ${data.type}`);
            ws.send(JSON.stringify({ 
                type: "ERROR", 
                message: `Tipo desconocido: ${data.type}` 
            }));
    }
}

/**
 * MANEJADOR JOIN
 */
function handleJoin(ws, id, data) {
    if (room.players.has(id)) {
        ws.send(JSON.stringify({ 
            type: "ERROR", 
            message: "Ya estás conectado" 
        }));
        return;
    }

    // Verificar límite de jugadores
    if (room.players.size >= MAX_PLAYERS) {
        ws.send(JSON.stringify({ 
            type: "ERROR", 
            message: `Sala llena: máximo ${MAX_PLAYERS} jugadores` 
        }));
        logger.warn(`🚫 Sala llena. Rechazado.`);
        return;
    }

    const name = (typeof data.name === "string" && data.name.trim()) 
                 ? data.name.trim() 
                 : "Anonymous";

    const isVisor = data.visor === true || name.toLowerCase().includes("visor");
    const icon = isVisor ? "👁️ " : "🎮 ";
    
    logger.info(`${icon} NUEVO ${isVisor ? 'VISOR' : 'JUGADOR'}: "${name}" (ID: ${id})`);

    // Posición de spawn
    const spawnIndex = room.players.size % world.spawnPoints.length;
    const spawn = world.spawnPoints[spawnIndex];

    const player = new Player(id, name, ws);
    player.x = spawn.x;
    player.y = spawn.y;
    player.isVisor = isVisor;
    
    const added = room.addPlayer(player);

    if (!added) {
        ws.send(JSON.stringify({ 
            type: "ERROR", 
            message: "No se pudo añadir a la sala" 
        }));
        return;
    }

    // Enviar confirmación al jugador
    ws.send(JSON.stringify({
        type: "JOINED",
        playerId: id,
        name: player.name,
        spawnPosition: spawn,
        worldState: world.getState()
    }));

    // Notificar a todos la nueva lista
    broadcastPlayersList();

    // Verificar si podemos empezar
    if (room.players.size >= MIN_PLAYERS_TO_START && room.state !== "playing") {
        room.setState("playing");
        logger.info("🎬 ¡Sala en juego! Jugadores: " + room.players.size);
    }
}

/**
 * MANEJADOR MOVE - Ahora con más información
 */
function handleMove(id, data) {
    const player = room.players.get(id);
    if (!player) return;

    const prevLeft = player.input.left;
    const prevRight = player.input.right;
    const prevJump = player.input.jump;

    // Actualizar input (compatible con ambos formatos)
    if (data.left !== undefined) {
        player.input.left = !!data.left;
    } else if (data.dir === "LEFT") {
        player.input.left = true;
        player.input.right = false;
    } else {
        player.input.left = false;
    }

    if (data.right !== undefined) {
        player.input.right = !!data.right;
    } else if (data.dir === "RIGHT") {
        player.input.right = true;
        player.input.left = false;
    } else if (data.dir !== undefined && data.dir !== "LEFT") {
        player.input.right = false;
    }

    // Salto (evento, no estado)
    if (data.jump === true || data.dir === "JUMP" || data.dir === "UP") {
        player.input.jump = true;
    }

    // LOG inteligente
    let acciones = [];
    if (player.input.left) acciones.push("⬅️ Izquierda");
    if (player.input.right) acciones.push("➡️ Derecha");
    if (player.input.jump) acciones.push("⬆️ Salto");
    if (acciones.length === 0) acciones.push("🛑 Parado");
    
    const changed = prevLeft !== player.input.left || 
                    prevRight !== player.input.right || 
                    prevJump !== player.input.jump;
    
    if (changed) {
        logger.info(`🏃 ${player.name}: ${acciones.join(" + ")}`);
    }
}

/**
 * MANEJADOR LEAVE
 */
function handleLeave(id) {
    const player = room.players.get(id);
    if (!player) return;
    
    if (world.keyHolder === id) {
        world.dropKey(player);
    }
    
    room.removePlayer(id);
    logger.info(`👋 ${player.name} abandonó la sala`);
    broadcastPlayersList();
}

/**
 * MANEJADOR GET_STATE
 */
function handleGetState(ws) {
    ws.send(JSON.stringify({
        type: "STATE",
        players: getPlayersState(),
        world: world.getState()
    }));
}

// ==================== BROADCAST ====================

function broadcast(data) {
    const msg = JSON.stringify(data);
    room.players.forEach((player) => {
        if (player.ws.readyState === WebSocket.OPEN) {
            player.ws.send(msg);
        }
    });
}

function broadcastPlayersList() {
    broadcast({
        type: "PLAYERS_LIST",
        players: getPlayersState(),
        world: world.getState()
    });
}

function broadcastState() {
    broadcast({
        type: "STATE",
        players: getPlayersState(),
        world: world.getState()
    });
}

/**
 * Obtener estado de todos los jugadores
 */
function getPlayersState() {
    const playersState = [];
    room.players.forEach((player) => {
        playersState.push({
            id: player.id,
            name: player.name,
            x: Math.round(player.x),
            y: Math.round(player.y),
            state: player.state,
            facingRight: player.facingRight,
            onGround: player.onGround,
            isVisor: player.isVisor,
            hasKey: world.keyHolder === player.id
        });
    });
    return playersState;
}

// Iniciar el ciclo de juego (60 FPS)
startGameLoop(room, world, broadcastState);

// ==================== COMANDOS DE CONSOLA ====================

process.on('SIGINT', () => {
    logger.info('🛑 Servidor detenido');
    process.exit(0);
});

// Log de estado cada 30 segundos
setInterval(() => {
    const playerCount = room.players.size;
    const keyStatus = world.keyTaken ? 
        `Llave: ${world.keyHolder ? 'portada' : 'en el suelo'}` : 
        'Llave: no recogida';
    const doorStatus = world.doorOpen ? 'Abierta' : 'Cerrada';
    
    logger.info(`📊 Estado: ${playerCount} jugadores | ${keyStatus} | Puerta: ${doorStatus} | Sala: ${room.state}`);
}, 30000);