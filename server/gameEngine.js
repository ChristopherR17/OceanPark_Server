const Hitbox = require("./hitbox");
const fs = require("fs");
const path = require("path");

class GameEngine {
    constructor(playerRegistry) {
        this.playerRegistry = playerRegistry;
        this.gravity = 0.8;
        this.speed = 5;
        this.platforms = [];
        this.deathZones = [];

        this.leafKey = {
            x: 45,
            y: 261,
            initialX: 45,
            initialY: 261,
            pickedBy: null,
            width: 32,
            height: 32
        };

        this.door = {
            x: 450,
            y: 548,
            width: 36,
            height: 64,
            open: false
        };

        this.loadGameData();
    }

    loadGameData() {
        try {
            const assetsPath = path.join(__dirname, "games-tool-assets");
            const mainPath = path.join(assetsPath, "game_data.json");

            if (!fs.existsSync(mainPath)) {
                console.log("⚠️ No existe games-tool-assets/game_data.json. Usando datos por defecto.");
                this.platforms.push(new Hitbox(70, 580, 310, 12));
                this.platforms.push(new Hitbox(405, 580, 100, 13));
                this.deathZones.push(new Hitbox(-250, 605, 1700, 150));
                return;
            }

            const mainJson = JSON.parse(fs.readFileSync(mainPath, "utf8"));
            const level = mainJson.levels[0];

            const keySprite = level.sprites.find(s => {
                const name = String(s.name || "").toLowerCase();
                const type = String(s.type || "").toLowerCase();
                return name.includes("key")
                    || type.includes("key")
                    || name.includes("leaf")
                    || type.includes("leaf");
            });

            if (keySprite) {
                this.leafKey.x = this.leafKey.initialX = keySprite.x;
                this.leafKey.y = this.leafKey.initialY = keySprite.y;
            }

            const doorSprite = level.sprites.find(s => {
                const name = String(s.name || "").toLowerCase();
                const type = String(s.type || "").toLowerCase();
                return name.includes("door") || type.includes("door") || name.includes("porta") || type.includes("porta");
            });

            if (doorSprite) {
                this.door.x = doorSprite.x;
                this.door.y = doorSprite.y;
                this.door.width = doorSprite.width || this.door.width;
                this.door.height = doorSprite.height || this.door.height;
            }

            const zonesData = JSON.parse(fs.readFileSync(path.join(assetsPath, level.zonesFile), "utf-8"));
            zonesData.zones.forEach(z => {
                const box = new Hitbox(z.x, z.y, z.width, z.height);
                const type = String(z.type || "").toLowerCase();
                const name = String(z.name || "").toLowerCase();

                if (type.includes("floor") || type.includes("platform") || name.includes("suelo")) {
                    this.platforms.push(box);
                } else if (type.includes("death") || name.includes("death")) {
                    this.deathZones.push(box);
                } else if (type.includes("door") || name.includes("puerta") || name.includes("porta")) {
                    this.door.x = z.x;
                    this.door.y = z.y;
                    this.door.width = z.width;
                    this.door.height = z.height;
                }
            });

            console.log(`✅ Mapa cargado: ${this.platforms.length} suelos, ${this.deathZones.length} zonas muerte`);
            console.log(`🚪 Puerta: x=${this.door.x}, y=${this.door.y}, w=${this.door.width}, h=${this.door.height}`);
        } catch (e) {
            console.log("⚠️ Error cargando mapa:", e.message);
            this.platforms.push(new Hitbox(70, 580, 310, 12));
            this.platforms.push(new Hitbox(405, 580, 100, 13));
            this.deathZones.push(new Hitbox(-250, 605, 1700, 150));
        }
    }

    update() {
        const players = this.playerRegistry.getPlayersSnapshot();

        players.forEach(player => {
            const state = player.getGameState();

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

            let platformCol = this.platforms.find(p => testHitboxY.intersects(p));

            let otherPlayerCol = players.find(other =>
                other.id !== player.id && testHitboxY.intersects(other.playerGameState.hitbox)
            );

            if (state.verticalSpeed > 0) {
                if (platformCol) {
                    state.y = platformCol.y - state.height;
                    state.verticalSpeed = 0;
                    state.canJump = true;
                } else if (otherPlayerCol && state.y + state.height <= otherPlayerCol.playerGameState.y + 10) {
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
            this.updateDoor(player, state);

            if (this.deathZones.find(dz => state.hitbox.intersects(dz)) || state.y > 1500) {
                if (this.leafKey.pickedBy === player.id) {
                    this.leafKey.pickedBy = null;
                    this.leafKey.x = this.leafKey.initialX;
                    this.leafKey.y = this.leafKey.initialY;
                }
                player.resetPosition();
            }
        });

        this.updateWinCondition();
    }

    updateKey(player, state) {
        if (this.leafKey.pickedBy === player.id) {
            this.leafKey.x = state.x;
            this.leafKey.y = state.y - 35;
            return;
        }

        if (!this.leafKey.pickedBy) {
            const keyHitbox = new Hitbox(this.leafKey.x, this.leafKey.y, this.leafKey.width, this.leafKey.height);
            if (state.hitbox.intersects(keyHitbox)) {
                this.leafKey.pickedBy = player.id;
                state.hasKey = true;
            }
        }
    }

    updateDoor(player, state) {
        const doorHitbox = new Hitbox(this.door.x, this.door.y, this.door.width, this.door.height);

        if (this.leafKey.pickedBy === player.id && state.hitbox.intersects(doorHitbox)) {
            this.door.open = true;
            this.leafKey.pickedBy = null;
            this.leafKey.x = this.door.x;
            this.leafKey.y = this.door.y;
            state.hasKey = false;
        }

        if (this.door.open && state.hitbox.intersects(doorHitbox)) {
            state.crossedDoor = true;
        }
    }

    updateWinCondition() {
        const players = this.playerRegistry.getPlayersSnapshot();
        if (players.length === 0) {
            return;
        }

        const allPassed = players.every(p => p.playerGameState.crossedDoor === true);
        if (allPassed) {
            this.door.allPlayersPassed = true;
        }
    }

    canMoveTo(playerId, hitbox) {
        if (!this.door.open) {
            const doorHitbox = new Hitbox(this.door.x, this.door.y, this.door.width, this.door.height);
            if (hitbox.intersects(doorHitbox)) {
                return false;
            }
        }

        for (const other of this.playerRegistry.getPlayersSnapshot()) {
            if (other.id !== playerId) {
                const otherState = other.playerGameState;
                if (hitbox.intersects(otherState.hitbox)) {
                    if (Math.abs(hitbox.y - otherState.y) < 20) return false;
                }
            }
        }
        return true;
    }

    getKeyState() {
        return {
            x: Math.round(this.leafKey.x),
            y: Math.round(this.leafKey.y),
            pickedBy: this.leafKey.pickedBy
        };
    }

    getDoorState() {
        const players = this.playerRegistry.getPlayersSnapshot();
        const passedPlayers = players.filter(p => p.playerGameState.crossedDoor === true).length;
        const allPlayersPassed = players.length > 0 && passedPlayers === players.length;

        return {
            x: this.door.x,
            y: this.door.y,
            width: this.door.width,
            height: this.door.height,
            open: this.door.open,
            passedPlayers,
            totalPlayers: players.length,
            allPlayersPassed
        };
    }

    getPlatformsState() {
        return this.platforms.map(p => ({
            x: p.x,
            y: p.y,
            width: p.width,
            height: p.height
        }));
    }
}

module.exports = GameEngine;
