const path = require("path");
const Hitbox = require("./hitbox");

const TILE_SIZE = 23;

// El cliente renderiza los mapas con estos offsets fijos en GameScreen.
const CLIENT_LAYER_X = -75;
const CLIENT_LAYER_Y = 673;

class GameEngine {
    constructor(playerRegistry) {
        this.playerRegistry = playerRegistry;

        this.gravity = 0.8;
        this.speed = 5;

        this.level = 1;
        this.levelChanging = false;

        this.platforms = [];
        this.movingPlatforms = [];
        this.deathZones = [];

        this.leafKey = {
            x: 0,
            y: 0,
            initialX: 0,
            initialY: 0,
            pickedBy: null,
            width: 32,
            height: 32
        };

        this.door = {
            x: 0,
            y: 0,
            width: 54,
            height: 38,
            open: false
        };

        this.exitZone = {
            x: 0,
            y: 0,
            width: 80,
            height: 100
        };

        /*
         * IMPORTANTE SOBRE LA PLATAFORMA MÓVIL:
         * La lógica está basada en el GameLogic de Laura:
         * - El path NO es la hitbox.
         * - Los puntos del path se tratan como CENTROS de destino.
         * - La plataforma tiene su rectángulo propio: x, y, width, height.
         * - Al moverse, se mueve el rectángulo cambiando su centro.
         * - La colisión usa el rectángulo actual de la plataforma.
         */
        this.levelConfigs = {
            1: {
                tileMapFile: "level_000_layer_000.json",
                layerX: CLIENT_LAYER_X,
                layerY: CLIENT_LAYER_Y,
                spawn: { x: 107, y: 414 + CLIENT_LAYER_Y - 32 },
                key: { x: 45, y: 300 + CLIENT_LAYER_Y, width: 32, height: 32 },
                door: { x: 260, y: 379 + CLIENT_LAYER_Y, width: 54, height: 38 },
                exitOffset: { x: 45, y: -40, width: 80, height: 100 },
                deathY: 900 + CLIENT_LAYER_Y,
                fallY: 1500 + CLIENT_LAYER_Y,
                nextLevel: 2,
                useFallbackPlatforms: true
            },
            2: {
                tileMapFile: "level_001_layer_000.json",
                layerX: CLIENT_LAYER_X,
                layerY: CLIENT_LAYER_Y,
                spawn: { x: 107, y: 13 * TILE_SIZE + CLIENT_LAYER_Y - 32 },

                // Bajada visual respecto al JSON original para que quede más alcanzable.
                key: { x: 414, y: 115 + CLIENT_LAYER_Y, width: 32, height: 32 },

                door: { x: 475, y: 181 + CLIENT_LAYER_Y, width: 54, height: 38 },
                button: { x: 445, y: 13 * TILE_SIZE + CLIENT_LAYER_Y - 22, width: 20, height: 22, pressed: false },
                exitOffset: { x: 45, y: -40, width: 80, height: 100 },
                deathY: 900 + CLIENT_LAYER_Y,
                fallY: 1500 + CLIENT_LAYER_Y,
                nextLevel: null,

                // Tiles sólidos principales. El resto del mapa contiene mucho decorado/pared.
                solidTileIds: new Set([76, 77, 78]),

                movingPlatform: {
                    name: "Movimiento",
                    type: "Movimiento",
                    pathFile: "level_001_paths.json",

                    // Se detecta desde el tilemap igual que el suelo.
                    // En level_001 los bloques marrones de la plataforma son id 145.
                    tileIds: new Set([145]),

                    speed: 2,

                    // Movimiento continuo izquierda <-> derecha tras pulsar el botón.
                    loop: true,

                    fallbackPoints: [
                        { x: 278, y: 177 + CLIENT_LAYER_Y },
                        { x: 193, y: 177 + CLIENT_LAYER_Y }
                    ]
                }
            }
        };

        this.currentConfig = null;
        this.button = null;

        this.loadLevel(1);
    }

    loadLevel(levelNumber) {
        const config = this.levelConfigs[levelNumber];

        if (!config) {
            console.error(`No existe configuración para el nivel ${levelNumber}`);
            return;
        }

        this.level = levelNumber;
        this.currentConfig = config;

        this.platforms = [];
        this.movingPlatforms = [];
        this.deathZones = [];

        this.leafKey.width = config.key.width;
        this.leafKey.height = config.key.height;
        this.leafKey.initialX = config.key.x;
        this.leafKey.initialY = config.key.y;
        this.resetKey();

        this.door.x = config.door.x;
        this.door.y = config.door.y;
        this.door.width = config.door.width;
        this.door.height = config.door.height;
        this.door.open = false;

        this.exitZone.x = this.door.x + config.exitOffset.x;
        this.exitZone.y = this.door.y + config.exitOffset.y;
        this.exitZone.width = config.exitOffset.width;
        this.exitZone.height = config.exitOffset.height;

        this.button = config.button ? { ...config.button, pressed: false } : null;

        this.loadPlatformsFromTileMap(levelNumber);
        this.loadMovingPlatforms(levelNumber);
        this.deathZones.push(new Hitbox(-500, config.deathY, 3000, 100));

        console.log(`🗺️ Nivel cargado en servidor: ${this.level}`);
    }

    getSpawnPosition(index = 0) {
        const spawn = this.currentConfig.spawn;
        return {
            x: spawn.x + index * 40,
            y: spawn.y
        };
    }

    loadPlatformsFromTileMap(levelNumber = this.level) {
        const layer = this.loadLevelLayer(levelNumber);

        if (!layer || !layer.tileMap) {
            this.loadFallbackPlatforms();
            return;
        }

        const config = this.levelConfigs[levelNumber];

        if (config.useFallbackPlatforms) {
            this.loadFallbackPlatforms();
            return;
        }

        const tileMap = layer.tileMap;
        const solidTileIds = config.solidTileIds || new Set();

        for (let row = 0; row < tileMap.length; row++) {
            let startCol = -1;

            for (let col = 0; col <= tileMap[row].length; col++) {
                const id = col < tileMap[row].length ? tileMap[row][col] : -1;
                const isSolid = solidTileIds.has(id);

                if (isSolid && startCol === -1) {
                    startCol = col;
                }

                if (!isSolid && startCol !== -1) {
                    const x = config.layerX + startCol * TILE_SIZE;
                    const y = config.layerY + row * TILE_SIZE;
                    const width = (col - startCol) * TILE_SIZE;

                    this.platforms.push(new Hitbox(x, y, width, TILE_SIZE));
                    startCol = -1;
                }
            }
        }
    }

    loadMovingPlatforms(levelNumber = this.level) {
        const config = this.levelConfigs[levelNumber];
        const mpConfig = config.movingPlatform;

        if (!mpConfig) return;

        const rect = this.findMovingPlatformRectFromTileMap(levelNumber, mpConfig);

        if (!rect) {
            console.warn(`No se encontró la plataforma móvil ${mpConfig.name} en el tilemap.`);
            return;
        }

        let points = this.loadPathPoints(mpConfig.pathFile, mpConfig.name);

        if (!points || points.length < 2) {
            points = mpConfig.fallbackPoints;
            console.warn(`No se pudo cargar una ruta válida para ${mpConfig.name}; usando fallback.`);
        }

        /*
         * El tilemap define la posición real de la plataforma.
         * El path define cuánto se desplaza.
         *
         * Así la hitbox coincide con los bloques dibujados y el path deja de
         * colocar la plataforma en una posición falsa.
         */
        const startCenter = {
            x: rect.x + rect.width * 0.5,
            y: rect.y + rect.height * 0.5
        };

        const firstPoint = points[0];
        const pathCenters = points.map(p => ({
            x: startCenter.x + (p.x - firstPoint.x),
            y: startCenter.y + (p.y - firstPoint.y)
        }));

        this.movingPlatforms.push({
            name: mpConfig.name,
            type: mpConfig.type || mpConfig.name,
            tileId: Array.from(mpConfig.tileIds)[0],
            x: rect.x,
            y: rect.y,
            prevX: rect.x,
            prevY: rect.y,
            width: rect.width,
            height: rect.height,
            pathCenters,
            targetIndex: 1,
            direction: 1,
            speed: mpConfig.speed,
            loop: mpConfig.loop,
            active: false,
            finished: false,
            dx: 0,
            dy: 0,
            hitbox: new Hitbox(rect.x, rect.y, rect.width, rect.height)
        });
    }

    findMovingPlatformRectFromTileMap(levelNumber, mpConfig) {
        const layer = this.loadLevelLayer(levelNumber);
        const config = this.levelConfigs[levelNumber];

        if (!layer || !layer.tileMap) return null;

        const tileMap = layer.tileMap;
        const tileIds = mpConfig.tileIds || new Set();

        let best = null;

        for (let row = 0; row < tileMap.length; row++) {
            let startCol = -1;

            for (let col = 0; col <= tileMap[row].length; col++) {
                const id = col < tileMap[row].length ? tileMap[row][col] : -1;
                const isPlatformTile = tileIds.has(id);

                if (isPlatformTile && startCol === -1) {
                    startCol = col;
                }

                if (!isPlatformTile && startCol !== -1) {
                    const rect = {
                        x: config.layerX + startCol * TILE_SIZE,
                        y: config.layerY + row * TILE_SIZE,
                        width: (col - startCol) * TILE_SIZE,
                        height: TILE_SIZE
                    };

                    if (!best || rect.width > best.width) {
                        best = rect;
                    }

                    startCol = -1;
                }
            }
        }

        return best;
    }

    loadPathPoints(fileName, pathName) {
        const data = this.loadJsonFile(fileName, [
            `./${fileName}`,
            `./paths/${fileName}`,
            path.join(__dirname, fileName),
            path.join(__dirname, "paths", fileName)
        ]);

        if (!data) return null;

        const rawPoints = this.extractPointsFromPathData(data, pathName);
        if (!rawPoints || rawPoints.length < 2) return null;

        return rawPoints.map(p => ({
            x: Number(p.x),
            y: Number(p.y) + CLIENT_LAYER_Y
        })).filter(p => Number.isFinite(p.x) && Number.isFinite(p.y));
    }

    extractPointsFromPathData(data, pathName) {
        const arraysToTry = [];

        const collectFromNode = (node) => {
            if (!node || typeof node !== "object") return;

            const nodeName = node.name || node.type || node.id;
            const matchesName = !pathName || nodeName === pathName;

            if (matchesName) {
                for (const key of ["points", "waypoints", "path", "nodes"]) {
                    if (Array.isArray(node[key])) arraysToTry.push(node[key]);
                }
            }

            if (Array.isArray(node)) {
                node.forEach(collectFromNode);
            } else {
                Object.values(node).forEach(collectFromNode);
            }
        };

        collectFromNode(data);

        for (const arr of arraysToTry) {
            const points = arr.map(item => this.normalizePoint(item)).filter(Boolean);
            if (points.length >= 2) return points;
        }

        if (Array.isArray(data)) {
            const points = data.map(item => this.normalizePoint(item)).filter(Boolean);
            if (points.length >= 2) return points;
        }

        return null;
    }

    normalizePoint(item) {
        if (!item || typeof item !== "object") return null;

        if (Number.isFinite(Number(item.x)) && Number.isFinite(Number(item.y))) {
            return { x: Number(item.x), y: Number(item.y) };
        }

        if (item.position && Number.isFinite(Number(item.position.x)) && Number.isFinite(Number(item.position.y))) {
            return { x: Number(item.position.x), y: Number(item.position.y) };
        }

        return null;
    }

    loadJsonFile(fileName, candidates) {
        for (const file of candidates) {
            try {
                return require(file);
            } catch (e) {
                // Probar siguiente ruta.
            }
        }

        console.error(`No se pudo cargar ${fileName}.`);
        return null;
    }

    loadLevelLayer(levelNumber = this.level) {
        const config = this.levelConfigs[levelNumber];
        const fileName = config.tileMapFile;

        return this.loadJsonFile(fileName, [
            `./${fileName}`,
            `./tilemaps/${fileName}`,
            path.join(__dirname, fileName),
            path.join(__dirname, "tilemaps", fileName)
        ]);
    }

    loadFallbackPlatforms() {
        // Fallback del nivel 1 original.
        this.platforms.push(new Hitbox(40, 414 + CLIENT_LAYER_Y, 138, 23));
        this.platforms.push(new Hitbox(40, 437 + CLIENT_LAYER_Y, 161, 23));
        this.platforms.push(new Hitbox(201, 460 + CLIENT_LAYER_Y, 46, 23));
        this.platforms.push(new Hitbox(201, 483 + CLIENT_LAYER_Y, 115, 23));
        this.platforms.push(new Hitbox(224, 506 + CLIENT_LAYER_Y, 115, 23));
        this.platforms.push(new Hitbox(23, 598 + CLIENT_LAYER_Y, 414, 23));
        this.platforms.push(new Hitbox(523, 598 + CLIENT_LAYER_Y, 253, 23));
    }

    update() {
        const players = this.playerRegistry.getPlayersSnapshot();

        if (this.button) {
            this.button.pressed = false;
        }

        this.updateMovingPlatforms(players);

        players.forEach(player => {
            const state = player.getGameState();

            if (state.hasFinishedLevel) {
                return;
            }

            // Si estaba sobre una plataforma móvil antes de aplicar input/física,
            // lo arrastramos con el delta de la plataforma.
            this.carryPlayerIfOnMovingPlatform(state);

            let nextX = state.x;

            if (state.isMovingLeft) nextX -= this.speed;
            if (state.isMovingRight) nextX += this.speed;

            const testHitboxX = new Hitbox(nextX, state.y, state.width, state.height);

            if (this.canMoveTo(player.id, testHitboxX)) {
                state.x = nextX;
            }

            state.verticalSpeed += this.gravity;

            let nextY = state.y + state.verticalSpeed;
            const testHitboxY = new Hitbox(state.x, nextY, state.width, state.height);

            let platformCol = this.getAllPlatforms().find(p => testHitboxY.intersects(p));

            let otherPlayerCol = players.find(other =>
                other.id !== player.id &&
                !other.playerGameState.hasFinishedLevel &&
                testHitboxY.intersects(other.playerGameState.hitbox)
            );

            if (state.verticalSpeed > 0) {
                if (platformCol) {
                    state.y = platformCol.y - state.height;
                    state.verticalSpeed = 0;
                    state.canJump = true;
                } else if (
                    otherPlayerCol &&
                    state.y + state.height <= otherPlayerCol.playerGameState.y + 10
                ) {
                    state.y = otherPlayerCol.playerGameState.y - state.height;
                    state.verticalSpeed = 0;
                    state.canJump = true;

                    if (otherPlayerCol.playerGameState.isMovingLeft) state.x -= this.speed;
                    if (otherPlayerCol.playerGameState.isMovingRight) state.x += this.speed;
                } else {
                    state.y = nextY;
                    state.canJump = false;
                }
            } else {
                state.y = nextY;
                state.canJump = false;
            }

            state.hitbox.updateHitboxPosition(state.x, state.y);

            this.updateKey(player, state);
            this.updateButton(state);
            this.updateDoor(player, state);
            this.updatePlayerFinishedLevel(player, state);
            this.updateDeath(player, state);
        });

        this.checkLevelChange(players);
    }

    getAllPlatforms() {
        return [
            ...this.platforms,
            ...this.movingPlatforms.map(mp => mp.hitbox)
        ];
    }

    updateMovingPlatforms() {
        for (const mp of this.movingPlatforms) {
            mp.prevX = mp.x;
            mp.prevY = mp.y;
            mp.dx = 0;
            mp.dy = 0;

            if (!mp.active || mp.pathCenters.length < 2) {
                continue;
            }

            const currentCenter = this.platformCenter(mp);
            const target = mp.pathCenters[mp.targetIndex];

            const vx = target.x - currentCenter.x;
            const vy = target.y - currentCenter.y;
            const distance = Math.hypot(vx, vy);

            if (distance <= mp.speed) {
                this.setPlatformCenter(mp, target.x, target.y);

                if (mp.loop) {
                    /*
                     * Movimiento continuo tipo ping-pong:
                     * 0 -> 1 -> 0 -> 1...
                     * Para más de dos puntos: 0 -> 1 -> 2 -> 1 -> 0...
                     */
                    if (mp.targetIndex >= mp.pathCenters.length - 1) {
                        mp.direction = -1;
                    } else if (mp.targetIndex <= 0) {
                        mp.direction = 1;
                    }

                    mp.targetIndex += mp.direction;
                } else {
                    if (mp.targetIndex < mp.pathCenters.length - 1) {
                        mp.targetIndex++;
                    } else {
                        mp.finished = true;
                    }
                }
            } else {
                this.setPlatformCenter(
                    mp,
                    currentCenter.x + (vx / distance) * mp.speed,
                    currentCenter.y + (vy / distance) * mp.speed
                );
            }

            mp.dx = mp.x - mp.prevX;
            mp.dy = mp.y - mp.prevY;
            mp.hitbox.updateHitboxPosition(mp.x, mp.y);
        }
    }

    platformCenter(mp) {
        return {
            x: mp.x + mp.width * 0.5,
            y: mp.y + mp.height * 0.5
        };
    }

    setPlatformCenter(mp, x, y) {
        mp.x = x - mp.width * 0.5;
        mp.y = y - mp.height * 0.5;
    }

    carryPlayerIfOnMovingPlatform(state) {
        for (const mp of this.movingPlatforms) {
            if (mp.dx === 0 && mp.dy === 0) continue;

            const playerBottom = state.y + state.height;
            const wasOnTop =
                Math.abs(playerBottom - mp.prevY) <= 6 &&
                state.x + state.width > mp.prevX &&
                state.x < mp.prevX + mp.width;

            if (wasOnTop) {
                state.x += mp.dx;
                state.y += mp.dy;
                state.hitbox.updateHitboxPosition(state.x, state.y);
                return;
            }
        }
    }

    updateKey(player, state) {
        if (this.leafKey.pickedBy === player.id) {
            this.leafKey.x = state.x;
            this.leafKey.y = state.y - 35;
            return;
        }

        if (!this.leafKey.pickedBy) {
            const keyHitbox = new Hitbox(
                this.leafKey.x,
                this.leafKey.y,
                this.leafKey.width,
                this.leafKey.height
            );

            if (state.hitbox.intersects(keyHitbox)) {
                this.leafKey.pickedBy = player.id;
                console.log(`${player.name} ha cogido la llave`);
            }
        }
    }

    updateButton(state) {
        if (!this.button) return;

        const buttonHitbox = new Hitbox(
            this.button.x,
            this.button.y,
            this.button.width,
            this.button.height
        );

        if (state.hitbox.intersects(buttonHitbox)) {
            this.button.pressed = true;
            this.activateMovingPlatforms();
        }
    }

    activateMovingPlatforms() {
        for (const mp of this.movingPlatforms) {
            mp.active = true;
        }
    }

    updateDoor(player, state) {
        if (this.door.open) return;
        if (this.leafKey.pickedBy !== player.id) return;

        const doorHitbox = new Hitbox(
            this.door.x,
            this.door.y,
            this.door.width,
            this.door.height
        );

        if (state.hitbox.intersects(doorHitbox)) {
            this.door.open = true;
            console.log(`🚪 ${player.name} ha abierto la puerta`);
        }
    }

    updatePlayerFinishedLevel(player, state) {
        if (!this.door.open) return;

        const exitHitbox = new Hitbox(
            this.exitZone.x,
            this.exitZone.y,
            this.exitZone.width,
            this.exitZone.height
        );

        if (state.hitbox.intersects(exitHitbox)) {
            state.hasFinishedLevel = true;
            state.isMovingLeft = false;
            state.isMovingRight = false;
            state.verticalSpeed = 0;

            console.log(`✅ ${player.name} ha cruzado la puerta`);
        }
    }

    updateDeath(player, state) {
        const diedByZone = this.deathZones.find(dz => state.hitbox.intersects(dz));
        const diedByFall = state.y > this.currentConfig.fallY;

        if (diedByZone || diedByFall) {
            if (this.leafKey.pickedBy === player.id) {
                this.resetKey();
            }

            player.resetPosition();
        }
    }

    checkLevelChange(players) {
        if (this.levelChanging) return;
        if (!this.currentConfig.nextLevel) return;
        if (!this.door.open) return;
        if (players.length === 0) return;

        const everyoneFinished = players.every(p => p.playerGameState.hasFinishedLevel);

        if (everyoneFinished) {
            this.levelChanging = true;

            console.log(`🎉 Todos los jugadores han cruzado. Cambiando al nivel ${this.currentConfig.nextLevel}...`);

            setTimeout(() => {
                this.goToLevel(this.currentConfig.nextLevel, players);
                this.levelChanging = false;
            }, 1000);
        }
    }

    goToLevel(levelNumber, players) {
        this.loadLevel(levelNumber);

        players.forEach((player, index) => {
            const spawn = this.getSpawnPosition(index);
            player.resetForNextLevel(spawn.x, spawn.y);
        });
    }

    goToLevel2(players) {
        this.goToLevel(2, players);
    }

    resetKey() {
        this.leafKey.pickedBy = null;
        this.leafKey.x = this.leafKey.initialX;
        this.leafKey.y = this.leafKey.initialY;
    }

    canMoveTo(playerId, hitbox) {
        if (!this.door.open) {
            const doorHitbox = new Hitbox(
                this.door.x,
                this.door.y,
                this.door.width,
                this.door.height
            );

            if (hitbox.intersects(doorHitbox)) {
                return false;
            }
        }

        for (const platform of this.platforms) {
            if (hitbox.intersects(platform)) {
                return false;
            }
        }

        for (const other of this.playerRegistry.getPlayersSnapshot()) {
            if (other.id !== playerId) {
                const otherState = other.playerGameState;

                if (otherState.hasFinishedLevel) continue;

                if (hitbox.intersects(otherState.hitbox)) {
                    if (Math.abs(hitbox.y - otherState.y) < 20) {
                        return false;
                    }
                }
            }
        }

        return true;
    }

    getKeyState() {
        return {
            x: Math.round(this.leafKey.x),
            y: Math.round(this.leafKey.y),
            pickedBy: this.leafKey.pickedBy,
            picked: this.leafKey.pickedBy !== null
        };
    }

    getDoorState() {
        return {
            x: Math.round(this.door.x),
            y: Math.round(this.door.y),
            width: this.door.width,
            height: this.door.height,
            open: this.door.open
        };
    }

    getExitZoneState() {
        return {
            x: Math.round(this.exitZone.x),
            y: Math.round(this.exitZone.y),
            width: this.exitZone.width,
            height: this.exitZone.height
        };
    }

    getButtonState() {
        if (!this.button) return null;

        return {
            x: Math.round(this.button.x),
            y: Math.round(this.button.y),
            width: this.button.width,
            height: this.button.height,
            pressed: this.button.pressed
        };
    }

    getMovingPlatformsState() {
        return this.movingPlatforms.map(mp => ({
            name: mp.name,
            tileId: mp.tileId,
            x: Math.round(mp.x),
            y: Math.round(mp.y),
            width: mp.width,
            height: mp.height,
            active: mp.active,
            finished: mp.finished,
            targetIndex: mp.targetIndex
        }));
    }
}

module.exports = GameEngine;
