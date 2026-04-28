const express = require('express');
const cors = require('cors');
const WebSocket = require("ws");
const crypto = require("crypto");
require("dotenv").config();

// Módulos internos
const Room = require("./room");
const Player = require("./player");
const startGameLoop = require("./gameLoop");
const logger = require("./logger");
const GameWorld = require("./gameWorld");

// MongoDB
const { connectDatabase } = require("./config/database");
const PlayerModel = require("./models/Player");
const GameSessionModel = require("./models/GameSession");
const Movement = require("./models/Movement");
const navisionApi = require("./api/navisionApi");

// Inyectar modelos en GameWorld
GameWorld.setModels({
    PlayerModel,
    GameSession: GameSessionModel,
    Movement
});

// Configuración
const SERVER_PORT = process.env.SERVER_PORT || 3000;
const API_PORT = process.env.API_PORT || 3001;
const MAX_PLAYERS = 8;

// --- Servidor Express (API REST) ---
const app = express();
app.use(cors());
app.use(express.json());
app.use('/api/navision', navisionApi);

app.get('/', (req, res) => {
    res.json({
        servicio: 'OceanPark API',
        version: '1.0.0',
        endpoints: {
            jugadores: '/api/navision/jugadores',
            partidas: '/api/navision/partidas',
            partidasJugadores: '/api/navision/partidas-jugadores',
            kpi1: '/api/navision/kpi/1',
            kpi2: '/api/navision/kpi/2',
            kpi3: '/api/navision/kpi/3',
            health: '/api/navision/health'
        }
    });
});

app.listen(API_PORT, '0.0.0.0', () => {
    logger.info(`📡 API Navision iniciada en puerto ${API_PORT}`);
});

// --- Servidor WebSocket ---
const wss = new WebSocket.Server({ port: SERVER_PORT, host: '0.0.0.0' });
const room = new Room();
const world = new GameWorld(room);

// Conectar MongoDB
connectDatabase().then((ok) => {
    persistenceEnabled = ok;
});

logger.info(`🚀 Servidor OceanPark iniciado en puerto ${SERVER_PORT}`);

// Sesión actual
let currentSession = null;
let persistenceEnabled = true;


wss.on("connection", (ws) => {
    const playerId = crypto.randomUUID();
    logger.info(`🔌 Socket abierto: ID temporal ${playerId}`);

    ws.on("message", (msg) => {
        try {
            const data = JSON.parse(msg);
            handleMessage(ws, playerId, data);
        } catch (error) {
            logger.error(`❌ Error JSON de ${playerId}: ${error.message}`);
            ws.send(JSON.stringify({ type: "ERROR", message: "Formato JSON inválido" }));
        }
    });

    ws.on("close", async () => {
        const player = room.players.get(playerId);
        if (player) {
            logger.info(`[-] JUGADOR SALE: ${player.name} (${playerId})`);
            
            if (currentSession && persistenceEnabled) {
                try {
                    await Movement.create({
                        sessionId: currentSession.sessionId,
                        playerId: playerId,
                        playerName: player.name,
                        action: 'LEAVE',
                        position: { x: Math.round(player.x), y: Math.round(player.y) },
                        timestamp: new Date()
                    });
                } catch (error) {
                    persistenceEnabled = false;
                    logger.warn("⚠️ No se pudo registrar LEAVE: " + error.message);
                }
            }
            
            if (world.keyHolder === playerId) {
                world.dropKey(player);
            }
            
            room.removePlayer(playerId);
            broadcastPlayersList();
            
            if (!room.isReady()) {
                room.setState("waiting");
                await finalizeSession();
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
            logger.info(`❓ Mensaje desconocido: ${data.type}`);
            ws.send(JSON.stringify({ type: "ERROR", message: `Tipo desconocido: ${data.type}` }));
    }
}


function getPersistentPlayerId(name, socketId) {
    const clean = String(name || "anonymous")
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9_-]/g, "_")
        .slice(0, 32);
    return clean || socketId;
}

async function safeFindOrCreateDbPlayer(socketId, name) {
    if (!persistenceEnabled) return { category: "Junior" };

    try {
        const persistentId = getPersistentPlayerId(name, socketId);
        let dbPlayer = await PlayerModel.findOne({ playerId: persistentId });
        if (!dbPlayer) {
            dbPlayer = await PlayerModel.create({
                playerId: persistentId,
                nickname: name,
                category: "Junior",
                firstSeen: new Date(),
                lastSeen: new Date()
            });
        } else {
            dbPlayer.nickname = name;
            dbPlayer.lastSeen = new Date();
            await dbPlayer.save();
        }
        return dbPlayer;
    } catch (error) {
        persistenceEnabled = false;
        logger.warn("⚠️ MongoDB no disponible en JOIN: " + error.message);
        return { category: "Junior" };
    }
}

async function safeCreateSession() {
    if (!persistenceEnabled) {
        return {
            sessionId: crypto.randomUUID(),
            completed: false,
            startTime: new Date(),
            playerCount: 0,
            save: async () => {},
            finalize: async () => {}
        };
    }

    try {
        return await GameSessionModel.create({
            sessionId: crypto.randomUUID(),
            levelName: "Ocean World",
            levelIndex: 0,
            startTime: new Date(),
            playerCount: 0,
            totalCoinsAvailable: world.coins.length
        });
    } catch (error) {
        persistenceEnabled = false;
        logger.warn("⚠️ MongoDB no disponible al crear sesión: " + error.message);
        return {
            sessionId: crypto.randomUUID(),
            completed: false,
            startTime: new Date(),
            playerCount: 0,
            save: async () => {},
            finalize: async () => {}
        };
    }
}

async function handleJoin(ws, id, data) {
    if (room.players.has(id)) {
        ws.send(JSON.stringify({ type: "ERROR", message: "Ya estás conectado" }));
        return;
    }

    if (room.players.size >= MAX_PLAYERS) {
        ws.send(JSON.stringify({ type: "ERROR", message: `Sala llena: máximo ${MAX_PLAYERS} jugadores` }));
        return;
    }

    const name = (typeof data.name === "string" && data.name.trim()) 
                 ? data.name.trim() 
                 : "Anonymous";

    const isVisor = data.visor === true || name.toLowerCase().includes("visor");
    const icon = isVisor ? "👁️ " : "🎮 ";
    
    logger.info(`${icon} NUEVO ${isVisor ? 'VISOR' : 'JUGADOR'}: "${name}" (ID: ${id})`);

    // MongoDB: buscar o crear jugador. Si Mongo falla, el juego sigue funcionando.
    const dbPlayer = await safeFindOrCreateDbPlayer(id, name);

    // Crear sesión si es necesario. Si Mongo falla, se usa una sesión en memoria.
    if (!currentSession || currentSession.completed) {
        currentSession = await safeCreateSession();
        world.setSessionId(currentSession.sessionId);
        logger.info(`📋 Nueva sesión: ${currentSession.sessionId}`);
    }

    // Posición de spawn
    const spawnIndex = room.players.size % world.spawnPoints.length;
    const spawn = world.spawnPoints[spawnIndex];

    const player = new Player(id, name, ws);
    player.x = spawn.x;
    player.y = spawn.y;
    player.isVisor = isVisor;
    player.category = dbPlayer.category;
    
    const added = room.addPlayer(player);
    if (!added) {
        ws.send(JSON.stringify({ type: "ERROR", message: "No se pudo añadir a la sala" }));
        return;
    }

    // Actualizar sesión
    currentSession.playerCount = room.players.size;
    await currentSession.save();

    // Responder al jugador
    ws.send(JSON.stringify({
        type: "JOINED",
        playerId: id,
        name: player.name,
        spawnPosition: spawn,
        worldState: world.getState()
    }));

    // Enviar un STATE completo inmediatamente para que la APP pinte sin esperar al siguiente tick.
    ws.send(JSON.stringify({
        type: "STATE",
        players: getPlayersState(),
        world: world.getState()
    }));

    broadcastPlayersList();

    if (room.players.size >= 1 && room.state !== "playing") {
        room.setState("playing");
        room.startTime = Date.now();
    }
}

function handleMove(id, data) {
    const player = room.players.get(id);

    if (!player) {
        logger.warn(`MOVE ignorado: no existe jugador con id ${id}`);
        return;
    }

    if (data.RIGHT !== undefined || data.right !== undefined) {
        player.input.right = data.RIGHT === true || data.right === true;
    }

    if (data.LEFT !== undefined || data.left !== undefined) {
        player.input.left = data.LEFT === true || data.left === true;
    }

    if (data.JUMP === true || data.jump === true) {
        player.input.jump = true;
    }

    logger.info(`MOVE ${player.name}: ${JSON.stringify(data)} | input=${JSON.stringify(player.input)}`);
}

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

function handleGetState(ws) {
    ws.send(JSON.stringify({
        type: "STATE",
        players: getPlayersState(),
        world: world.getState()
    }));
}

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
    });
}

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
            hasKey: world.keyHolder === player.id,
            coins: player.coins || 0,
            deaths: player.deaths || 0,
            category: player.category
        });
    });
    return playersState;
}


async function finalizeSessionFromSnapshot(playersSnapshot) {
    if (!currentSession || currentSession.completed) return;

    const playersData = [];
    for (const player of playersSnapshot) {
        if (player.isVisor) continue;

        playersData.push({
            id: player.id,
            name: player.name,
            category: player.category,
            coins: player.coins || 0,
            deaths: player.deaths || 0,
            passedDoor: player.passedDoor || false
        });

        if (persistenceEnabled) {
            try {
                const persistentId = getPersistentPlayerId(player.name, player.id);
                const dbPlayer = await PlayerModel.findOne({ playerId: persistentId });
                if (dbPlayer) {
                    await dbPlayer.updateStats({
                        sessionId: currentSession.sessionId,
                        startTime: currentSession.startTime,
                        endTime: new Date(),
                        duration: Math.round((Date.now() - currentSession.startTime) / 1000),
                        coinsCollected: player.coins || 0,
                        deaths: player.deaths || 0,
                        completed: player.passedDoor || false,
                        score: (player.coins || 0) * 10,
                        levelReached: 0
                    });
                }
            } catch (error) {
                persistenceEnabled = false;
                logger.warn("⚠️ No se pudo actualizar stats: " + error.message);
            }
        }
    }

    if (persistenceEnabled && typeof currentSession.finalize === "function") {
        try {
            await currentSession.finalize(playersData);
        } catch (error) {
            persistenceEnabled = false;
            logger.warn("⚠️ No se pudo finalizar sesión en Mongo: " + error.message);
        }
    }

    currentSession.completed = true;
    world.reset();
    logger.info(`📋 Sesión finalizada: ${currentSession.sessionId}`);
}

async function finalizeSession() {
    const playersSnapshot = Array.from(room.players.values());
    await finalizeSessionFromSnapshot(playersSnapshot);
}

// Game Loop
startGameLoop(room, world, broadcastState);

// Log periódico
setInterval(() => {
    const playerCount = room.players.size;
    logger.info(`📊 Estado: ${playerCount} jugadores | Sala: ${room.state}`);
}, 30000);

process.on('SIGINT', () => {
    logger.info('🛑 Servidor detenido');
    process.exit(0);
});