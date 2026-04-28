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
connectDatabase();

logger.info(`🚀 Servidor OceanPark iniciado en puerto ${SERVER_PORT}`);

// Sesión actual
let currentSession = null;

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
            
            if (currentSession) {
                await Movement.create({
                    sessionId: currentSession.sessionId,
                    playerId: playerId,
                    playerName: player.name,
                    action: 'LEAVE',
                    position: { x: Math.round(player.x), y: Math.round(player.y) },
                    timestamp: new Date()
                });
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

    // MongoDB: buscar o crear jugador
    let dbPlayer = await PlayerModel.findOne({ playerId: id });
    if (!dbPlayer) {
        dbPlayer = await PlayerModel.create({
            playerId: id,
            nickname: name,
            category: 'Junior',
            firstSeen: new Date(),
            lastSeen: new Date()
        });
    } else {
        if (dbPlayer.nickname !== name) {
            dbPlayer.nickname = name;
            await dbPlayer.save();
        }
    }

    // Crear sesión si es necesario
    if (!currentSession || currentSession.completed) {
        currentSession = await GameSessionModel.create({
            sessionId: crypto.randomUUID(),
            levelName: 'Ocean World',
            levelIndex: 0,
            startTime: new Date(),
            playerCount: 0,
            totalCoinsAvailable: world.coins.length
        });
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

    broadcastPlayersList();

    if (room.players.size >= 1 && room.state !== "playing") {
        room.setState("playing");
        room.startTime = Date.now();
    }
}

function handleMove(id, data) {
    const player = room.players.get(id);
    if (!player) return;

    // Aceptar formato de la app: { type: "MOVE", RIGHT: true/false, LEFT: true/false, JUMP: true/false }
    // Y también formato alternativo: { type: "MOVE", left: true, right: true, jump: true }
    
    if (data.RIGHT !== undefined) {
        player.input.right = !!data.RIGHT;
    } else if (data.right !== undefined) {
        player.input.right = !!data.right;
    }
    
    if (data.LEFT !== undefined) {
        player.input.left = !!data.LEFT;
    } else if (data.left !== undefined) {
        player.input.left = !!data.left;
    }
    
    if (data.JUMP !== undefined) {
        player.input.jump = !!data.JUMP;
    } else if (data.jump !== undefined) {
        player.input.jump = !!data.jump;
    }
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
        world: world.getState()
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

async function finalizeSession() {
    if (!currentSession || currentSession.completed) return;
    
    const playersData = [];
    for (const player of room.players.values()) {
        if (player.isVisor) continue;
        
        playersData.push({
            id: player.id,
            name: player.name,
            category: player.category,
            coins: player.coins || 0,
            deaths: player.deaths || 0,
            passedDoor: player.passedDoor || false
        });
        
        const dbPlayer = await PlayerModel.findOne({ playerId: player.id });
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
    }
    
    await currentSession.finalize(playersData);
    logger.info(`📋 Sesión finalizada: ${currentSession.sessionId}`);
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