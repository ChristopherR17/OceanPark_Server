const Hitbox = require("./hitbox");

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
            x: 260,
            y: 379,
            width: 54,
            height: 38,
            open: false
        };

        this.exitZone = {
            x: this.door.x + 45,
            y: this.door.y - 40,
            width: 80,
            height: 100
        };

        this.level2Spawn = {
            x: 107,
            y: 385
        };

        // Llave
        this.leafKey.x = this.leafKey.initialX = 45;
        this.leafKey.y = this.leafKey.initialY = 260;

        // Plataformas generadas del tilemap (tile 23px, layer offset x:-75)
        const floors = [
            { x: -75, y: 230 }, { x: -75, y: 253 }, { x: -75, y: 276 },
            { x: -75, y: 299 }, { x: -75, y: 322 }, { x: -75, y: 345 },
            { x: -75, y: 368 }, { x: -75, y: 391 }, { x: -75, y: 414 },
            { x: -75, y: 437 }, { x: -75, y: 460 }, { x: -75, y: 483 },
            { x: -75, y: 506 }, { x: -75, y: 529 }, { x: -75, y: 552 },
            { x: -75, y: 575 }, { x: -75, y: 598 }, { x: -75, y: 621 },
            { x: -75, y: 644 }, { x: -75, y: 667 }, { x: -75, y: 690 },
            { x: -75, y: 713 }, { x: -75, y: 736 }, { x: -75, y: 759 },
            { x: -75, y: 782 }
        ];
        floors.forEach(f => this.platforms.push(new Hitbox(f.x, f.y, 874, 23)));

        this.deathZones.push(new Hitbox(-500, 900, 3000, 100));
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

            // 5. Puerta
            this.updateDoor(player, state);

            // 6. Detectar si ha cruzado la puerta
            this.updatePlayerFinishedLevel(player, state);

            // 7. Muerte / caída
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
        const diedByFall = state.y > 1500;

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

        if (everyoneFinished) {
            this.levelChanging = true;

            console.log("🎉 Todos los jugadores han cruzado. Cambiando al nivel 2...");

            setTimeout(() => {
                this.goToLevel2(players);
                this.levelChanging = false;
            }, 1000);
        }
    }

    goToLevel2(players) {
        this.level = 2;

        players.forEach((player, index) => {
            const spawnX = this.level2Spawn.x + index * 40;
            const spawnY = this.level2Spawn.y;

            player.resetForNextLevel(spawnX, spawnY);
        });

        this.resetKey();

        this.door.open = false;

        // Puedes cambiar estas coordenadas cuando tengas el mapa real del nivel 2
        this.door.x = 1000;
        this.door.y = 385;

        this.exitZone.x = this.door.x + 35;
        this.exitZone.y = this.door.y - 20;

        console.log("🗺️ Nivel actual:", this.level);
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
}

module.exports = GameEngine;