const WebSocket = require("ws");
const express = require("express");
const http = require("http");
const path = require("path");
const fs = require("fs");

const Player = require("./player");
const PlayerRegistry = require("./playerRegistry");
const Game = require("./game");

const PORT = process.env.PORT || 3000;
const SERVER_HOST = process.env.SERVER_HOST || "pico3.ieti.site";

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const playerRegistry = new PlayerRegistry();
const game = new Game(playerRegistry);

let emptyGameResetTimeout = null;

/**
 * Página antigua con QR para descargar la APK.
 * Se mantiene en:
 * https://pico3.ieti.site/web
 */
app.get("/web", (req, res) => {
    const apkUrl = `https://${SERVER_HOST}/apk`;
    const indexPath = path.join(__dirname, "..", "web", "index.html");

    fs.readFile(indexPath, "utf8", (err, data) => {
        if (err) {
            console.error("Error al leer index.html:", err.message);
            return res.status(500).send("Error al cargar la web del QR");
        }

        const html = data.replace(/text:\s*"[^"]*"/, `text: "${apkUrl}"`);
        res.send(html);
    });
});

/**
 * Descargar APK.
 * https://pico3.ieti.site/apk
 */
app.get("/apk", (req, res) => {
    const apkPath = path.join(__dirname, "..", "apk", "android-debug.apk");

    if (!fs.existsSync(apkPath)) {
        console.error("APK no encontrada en:", apkPath);
        return res.status(404).send("APK no encontrada");
    }

    res.download(apkPath, "oceanpark.apk");
});

/**
 * Health check.
 * https://pico3.ieti.site/health
 */
app.get("/health", (req, res) => {
    res.json({ ok: true });
});

/**
 * Flutter Web.
 *
 * El contenido generado con:
 * flutter build web --release --base-href /
 *
 * debe copiarse dentro de:
 * OCEANPARK_SERVER/flutter/
 *
 * Ejemplo:
 * OCEANPARK_SERVER/flutter/index.html
 * OCEANPARK_SERVER/flutter/flutter_bootstrap.js
 * OCEANPARK_SERVER/flutter/main.dart.js
 * OCEANPARK_SERVER/flutter/assets/
 * OCEANPARK_SERVER/flutter/canvaskit/
 */
const flutterWebPath = path.join(__dirname, "..", "flutter");

app.use(express.static(flutterWebPath));

/**
 * Fallback para Flutter Web.
 *
 * Esto permite que Flutter maneje rutas internas si algún día usas navegación.
 * Importante: debe ir después de /web, /apk y /health.
 */
app.get((req, res) => {
    res.sendFile(path.join(flutterWebPath, "index.html"));
});

wss.on("connection", (ws) => {
    console.log("Cliente conectado");

    ws.on("message", (message) => {
        try {
            const data = JSON.parse(message);

            if (data.type === "JOIN") {
                handleJoin(ws, data);
            } else if (data.type === "SPECTATE") {
                ws.isSpectator = true;
            } else if (data.type === "MOVE") {
                handleMove(ws, data);
            }
        } catch (e) {
            console.error("Error en mensaje:", e.message);
        }
    });

    ws.on("close", () => {
        const player = playerRegistry.getPlayer(ws);

        if (player) {
            if (
                game.gameEngine.leafKey &&
                game.gameEngine.leafKey.pickedBy === player.id
            ) {
                game.gameEngine.resetKey();
            }

            playerRegistry.removePlayer(ws);
            console.log(`Jugador desconectado: ${player.name}`);

            if (playerRegistry.getPlayersSnapshot().length === 0) {
                scheduleEmptyGameReset();
            }
        }
    });
});

function handleJoin(ws, data) {
    const name = String(data.name || "").trim();

    if (!name) {
        ws.send(JSON.stringify({
            type: "ERROR",
            message: "Nombre vacío"
        }));
        return;
    }

    if (playerRegistry.nameIsAlreadyTaken(name)) {
        ws.send(JSON.stringify({
            type: "ERROR",
            message: "Nombre ya usado"
        }));
        return;
    }

    const newId = Math.random().toString(36).substr(2, 9);

    const spawnIndex = playerRegistry.getPlayersSnapshot().length;
    const spawn = game.gameEngine.getSpawnPosition(spawnIndex);

    const newPlayer = new Player(newId, name, spawn.x, spawn.y);

    playerRegistry.addPlayer(ws, newPlayer);
    cancelEmptyGameReset();

    ws.send(JSON.stringify({
        type: "JOINED",
        playerId: newPlayer.id,
        name: newPlayer.name
    }));

    console.log(`Nuevo jugador: ${newPlayer.name} (${newPlayer.id})`);
}

function handleMove(ws, data) {
    if (ws.isSpectator) return;

    playerRegistry.setMovement(ws, data.dir);

    if (data.jump) {
        playerRegistry.setJump(ws);
    }
}

setInterval(() => {
    game.update();
    broadcastState();
}, 1000 / 60);

function broadcastState() {
    const playersSnapshot = playerRegistry.getPlayersSnapshot().map(p => {
        const gs = p.playerGameState;

        let visualState = "IDLE";

        if (gs.verticalSpeed !== 0 || !gs.canJump) {
            visualState = "JUMP";
        }

        if ((gs.isMovingLeft || gs.isMovingRight) && gs.canJump) {
            visualState = "RUN";
        }

        return {
            id: p.id,
            name: p.name,
            x: Math.round(gs.x),
            y: Math.round(gs.y),
            state: visualState,
            facingRight: !gs.isMovingLeft,
            hasKey: game.gameEngine.leafKey.pickedBy === p.id,
            hasFinishedLevel: gs.hasFinishedLevel
        };
    });

    const stateMsg = JSON.stringify({
        type: "STATE",
        level: game.gameEngine.level,
        players: playersSnapshot,
        leafKey: game.gameEngine.getKeyState(),
        door: game.gameEngine.getDoorState(),
        exitZone: game.gameEngine.getExitZoneState(),
        button: game.gameEngine.getButtonState(),
        movingPlatforms: game.gameEngine.getMovingPlatformsState()
    });

    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(stateMsg);
        }
    });
}

function scheduleEmptyGameReset() {
    if (emptyGameResetTimeout) return;

    emptyGameResetTimeout = setTimeout(() => {
        const players = playerRegistry.getPlayersSnapshot();

        if (players.length === 0) {
            console.log("No hay jugadores desde hace 5 segundos. Reiniciando partida al nivel 1...");
            game.gameEngine.resetToLevel1();
        }

        emptyGameResetTimeout = null;
    }, 5000);
}

function cancelEmptyGameReset() {
    if (!emptyGameResetTimeout) return;

    clearTimeout(emptyGameResetTimeout);
    emptyGameResetTimeout = null;
}

server.listen(PORT, "0.0.0.0", () => {
    console.log(`Servidor Ocean Park en puerto ${PORT}`);
    console.log(`Flutter Web: https://${SERVER_HOST}/`);
    console.log(`Web QR: https://${SERVER_HOST}/web`);
    console.log(`APK: https://${SERVER_HOST}/apk`);
});