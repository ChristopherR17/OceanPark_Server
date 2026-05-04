const path = require("path");
const Hitbox = require("./hitbox");

const TILE_SIZE = 23;

// El cliente renderiza todos los niveles con estos offsets fijos en GameScreen.
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

        // Datos del editor, convertidos al mismo sistema Y-down que ya usaba el servidor:
        // y_servidor = y_editor + 673.
        this.levelConfigs = {
            1: {
                tileMapFile: "level_000_layer_000.json",
                layerX: CLIENT_LAYER_X,
                layerY: CLIENT_LAYER_Y,
                // Spawn ajustado a la parte superior de la primera plataforma real.
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
                // En level_001 la primera plataforma jugable está en la fila 13:
                // y = 13 * 23 + 673; el jugador mide 32.
                spawn: { x: 107, y: 13 * TILE_SIZE + CLIENT_LAYER_Y - 32 },
                key: { x: 414, y: 99 + CLIENT_LAYER_Y, width: 32, height: 32 },
                door: { x: 475, y: 181 + CLIENT_LAYER_Y, width: 54, height: 38 },
                button: { x: 342, y: 194 + CLIENT_LAYER_Y, width: 20, height: 22, pressed: false },
                exitOffset: { x: 45, y: -40, width: 80, height: 100 },
                deathY: 900 + CLIENT_LAYER_Y,
                fallY: 1500 + CLIENT_LAYER_Y,
                nextLevel: null,
                // IMPORTANTE: el tilemap tiene muchos tiles decorativos de pared.
                // Si todos los id >= 0 son sólidos, el jugador colisiona con el decorado.
                // Estos ids son las plataformas de suelo visibles principales.
                solidTileIds: new Set([76, 77, 78])
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

        // No todos los tiles visibles son suelo: muchos son decorado/fondo.
        // Solo generamos colisiones con los ids marcados como plataforma.
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

    loadLevelLayer(levelNumber = this.level) {
        const config = this.levelConfigs[levelNumber];
        const fileName = config.tileMapFile;

        const candidates = [
            `./${fileName}`,
            `./tilemaps/${fileName}`,
            path.join(__dirname, fileName),
            path.join(__dirname, "tilemaps", fileName)
        ];

        for (const file of candidates) {
            try {
                return require(file);
            } catch (e) {
                // Probar la siguiente ruta.
            }
        }

        console.error(`No se pudo cargar ${fileName} para colisiones; usando plataformas fallback.`);
        return null;
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

        players.forEach(player => {
            const state = player.getGameState();

            if (state.hasFinishedLevel) {
                return;
            }

            // 1. Movimiento horizontal
            let nextX = state.x;

            if (state.isMovingLeft) nextX -= this.speed;
            if (state.isMovingRight) nextX += this.speed;

            const testHitboxX = new Hitbox(nextX, state.y, state.width, state.height);

            if (this.canMoveTo(player.id, testHitboxX)) {
                state.x = nextX;
            }

            // 2. Gravedad y movimiento vertical
            state.verticalSpeed += this.gravity;

            let nextY = state.y + state.verticalSpeed;
            const testHitboxY = new Hitbox(state.x, nextY, state.width, state.height);

            let platformCol = this.platforms.find(p => testHitboxY.intersects(p));

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

            // 3. Actualizar hitbox
            state.hitbox.updateHitboxPosition(state.x, state.y);

            // 4. Llave
            this.updateKey(player, state);

            // 5. Botón del nivel 2, si existe
            this.updateButton(state);

            // 6. Puerta
            this.updateDoor(player, state);

            // 7. Detectar si ha cruzado la puerta
            this.updatePlayerFinishedLevel(player, state);

            // 8. Muerte / caída
            this.updateDeath(player, state);
        });

        this.checkLevelChange(players);
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

        this.button.pressed = state.hitbox.intersects(buttonHitbox);
    }

    updateDoor(player, state) {
        if (this.door.open) return;

        // Mecánica actual: la llave abre la puerta.
        // El botón del nivel 2 queda publicado como estado para poder dibujarlo/usar su asset
        // desde el cliente sin romper la lógica existente.
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
        if (!this.door.open) return;
        if (players.length === 0) return;

        const everyoneFinished = players.every(p => p.playerGameState.hasFinishedLevel);

        if (!everyoneFinished) return;

        const nextLevel = this.currentConfig.nextLevel;

        if (!nextLevel) {
            return;
        }

        this.levelChanging = true;

        console.log(`🎉 Todos los jugadores han cruzado. Cambiando al nivel ${nextLevel}...`);

        setTimeout(() => {
            this.goToLevel(nextLevel, players);
            this.levelChanging = false;
        }, 1000);
    }

    goToLevel(levelNumber, players) {
        this.loadLevel(levelNumber);

        players.forEach((player, index) => {
            const spawn = this.getSpawnPosition(index);
            player.resetForNextLevel(spawn.x, spawn.y);
        });
    }

    // Compatibilidad con el nombre anterior.
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
}

module.exports = GameEngine;
