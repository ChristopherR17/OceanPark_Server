const fs = require("fs");
const path = require("path");
const logger = require("./logger");

let PlayerModel, GameSession, Movement;

function setModels(models) {
    PlayerModel = models.PlayerModel;
    GameSession = models.GameSession;
    Movement = models.Movement;
}

class GameWorld {
    constructor(room) {
        this.room = room;
        
        this.gameData = null;
        this.zonesData = null;
        this.tileMapData = null;
        
        this._loadGameData();
        
        this.width = 2300;
        this.height = 1380;
        this.viewportWidth = 320;
        this.viewportHeight = 180;
        this.backgroundColor = "#568BB1";
        
        this.platforms = [];
        this.deathZones = [];
        this.playerZones = [];
        
        this._processZones();
        
        this.spawnPoints = this._calculateSpawnPoints();
        
        // Llave
        this.keyX = 170;
        this.keyY = 295;
        this.keyWidth = 24;
        this.keyHeight = 24;
        this.keyTaken = false;
        this.keyHolder = null;
        
        // Puerta
        this.doorX = 460;
        this.doorY = 340;
        this.doorWidth = 40;
        this.doorHeight = 60;
        this.doorOpen = false;
        this.levelCompleted = false;
        
        // Monedas
        this.coins = [];
        this.generateCoins();
        
        this.playerZone = this.playerZones.length > 0 
            ? this.playerZones[0] 
            : { x: 25, y: 100, width: 400, height: 400 };

        this.currentSessionId = null;
        this._bonusCoinsSpawned = false;

        this._logWorldInfo();
    }
    
    _loadGameData() {
        try {
            const dataDir = path.join(__dirname, 'data');
            const gameDataPath = path.join(dataDir, 'game_data.json');
            
            if (fs.existsSync(gameDataPath)) {
                this.gameData = JSON.parse(fs.readFileSync(gameDataPath, 'utf8'));
                logger.info("📂 game_data.json cargado");
                
                const level = this.gameData.levels[0];
                
                if (level.viewportWidth) this.viewportWidth = level.viewportWidth;
                if (level.viewportHeight) this.viewportHeight = level.viewportHeight;
                if (level.backgroundColorHex) this.backgroundColor = level.backgroundColorHex;
                
                if (level.layers && level.layers[0]) {
                    const layer = level.layers[0];
                    const tileMapPath = path.join(dataDir, layer.tileMapFile);
                    if (fs.existsSync(tileMapPath)) {
                        this.tileMapData = JSON.parse(fs.readFileSync(tileMapPath, 'utf8'));
                        this._calculateWorldSize(layer);
                    }
                }
                
                if (level.zonesFile) {
                    const zonesPath = path.join(dataDir, level.zonesFile);
                    if (fs.existsSync(zonesPath)) {
                        this.zonesData = JSON.parse(fs.readFileSync(zonesPath, 'utf8'));
                        logger.info("📂 Zones cargadas desde " + level.zonesFile);
                    }
                }
            }
        } catch (error) {
            logger.warn("⚠️ No se pudieron cargar los archivos JSON: " + error.message);
            logger.warn("⚠️ Usando configuración por defecto");
        }
    }
    
    _calculateWorldSize(layer) {
        if (!this.tileMapData || !this.tileMapData.tileMap) return;
        
        const tileMap = this.tileMapData.tileMap;
        const rows = tileMap.length;
        const cols = rows > 0 ? tileMap[0].length : 0;
        const tileW = layer.tilesWidth || 23;
        const tileH = layer.tilesHeight || 23;
        
        this.width = cols * tileW;
        this.height = rows * tileH;
        
        logger.info(`📐 Mundo: ${this.width}x${this.height}px (${cols}x${rows} tiles)`);
    }
    
    _processZones() {
        if (!this.zonesData || !this.zonesData.zones) {
            logger.warn("⚠️ No hay zones.json, usando plataformas por defecto");
            this._useDefaultPlatforms();
            return;
        }
        
        this.platforms = [];
        this.deathZones = [];
        this.playerZones = [];
        
        for (const zone of this.zonesData.zones) {
            const zoneType = (zone.type || "").toLowerCase();
            const zoneName = (zone.name || "").toLowerCase();
            
            const zoneData = {
                x: zone.x,
                y: zone.y,
                width: zone.width,
                height: zone.height,
                name: zone.name,
                type: zone.type,
                color: zone.color
            };
            
            if (zoneType.includes("death") || zoneName.includes("death")) {
                this.deathZones.push(zoneData);
            } else if (zoneType.includes("floor") || 
                       zoneName.includes("suelo") || 
                       zoneName.includes("plataforma") ||
                       zoneName.includes("escaleras") ||
                       zoneName.includes("escalón")) {
                this.platforms.push(zoneData);
            } else if (zoneType.includes("player") || zoneName.includes("player")) {
                this.playerZones.push(zoneData);
            }
        }
        
        if (this.platforms.length === 0) {
            logger.warn("⚠️ No se encontraron plataformas en zones.json");
            this._useDefaultPlatforms();
        }
    }
    
    _useDefaultPlatforms() {
        this.platforms = [
            { x: 42, y: 402, width: 246, height: 13, name: "Suelo1" },
            { x: 335, y: 401, width: 168, height: 14, name: "Suelo2" },
            { x: 150, y: 325, width: 62, height: 14, name: "Plataforma" },
            { x: 58, y: 278, width: 47, height: 14, name: "PlataformaAlta" }
        ];
    }
    
    _calculateSpawnPoints() {
        if (this.playerZones.length > 0) {
            const zone = this.playerZones[0];
            const points = [];
            const spacing = Math.min(zone.width / 9, 50);
            const startX = zone.x + spacing;
            const spawnY = zone.y + zone.height - 32;
            
            for (let i = 0; i < 8; i++) {
                points.push({ x: startX + i * spacing, y: spawnY });
            }
            return points;
        }
        
        return [
            { x: 80, y: 370 }, { x: 130, y: 370 },
            { x: 180, y: 370 }, { x: 230, y: 370 },
            { x: 280, y: 370 }, { x: 370, y: 370 },
            { x: 420, y: 370 }, { x: 470, y: 370 }
        ];
    }
    
    _logWorldInfo() {
        logger.info("═".repeat(50));
        logger.info("🌍 Mundo Ocean World cargado:");
        logger.info(`   📐 ${this.width}x${this.height}px`);
        logger.info(`   🏗️ ${this.platforms.length} plataformas`);
        logger.info(`   💀 ${this.deathZones.length} zonas de muerte`);
        logger.info(`   🪙 ${this.coins.length} monedas`);
        logger.info(`   🔑 Llave: (${this.keyX}, ${this.keyY})`);
        logger.info(`   🚪 Puerta: (${this.doorX}, ${this.doorY})`);
        logger.info("═".repeat(50));
    }
    
    generateCoins() {
        const coinPositions = [
            { x: 70, y: 380 }, { x: 110, y: 380 }, { x: 150, y: 380 },
            { x: 190, y: 380 }, { x: 230, y: 380 }, { x: 270, y: 380 },
            { x: 165, y: 300 }, { x: 185, y: 300 },
            { x: 370, y: 375 }, { x: 410, y: 375 }, { x: 450, y: 375 },
            { x: 70, y: 255 }, { x: 85, y: 255 },
            { x: 480, y: 375 }
        ];
        
        this.coins = coinPositions.map((pos, index) => ({
            id: `coin_${index}`,
            x: pos.x,
            y: pos.y,
            width: 12,
            height: 12,
            collected: false,
            value: 10
        }));
    }
    
    setSessionId(sessionId) {
        this.currentSessionId = sessionId;
    }
    
    getFloorYAt(x) {
        let floorY = this.height;
        
        for (const platform of this.platforms) {
            if (x >= platform.x && x <= platform.x + platform.width) {
                if (platform.y < floorY) {
                    floorY = platform.y;
                }
            }
        }
        
        return floorY;
    }
    
    isPlayerTouchingKey(player) {
        if (this.keyTaken) return false;
        
        return player.x + 16 > this.keyX && 
               player.x - 16 < this.keyX + this.keyWidth &&
               player.y > this.keyY && 
               player.y - 32 < this.keyY + this.keyHeight;
    }
    
    pickUpKey(player) {
        this.keyTaken = true;
        this.keyHolder = player.id;
        this.doorOpen = true;
        logger.info(`🔑 ¡${player.name} recogió la llave!`);
        this._logMovement(player, 'KEY_PICKUP', { keyHolder: player.id });
    }
    
    dropKey(player) {
        this.keyTaken = false;
        this.keyHolder = null;
        this.keyX = Math.round(player.x);
        this.keyY = Math.round(player.y - 16);
        this.doorOpen = false;
        logger.info(`🔑 Llave soltada en (${this.keyX}, ${this.keyY})`);
        this._logMovement(player, 'KEY_DROP', {});
    }
    
    isPlayerAtDoor(player) {
        return player.x > this.doorX && 
               player.x < this.doorX + this.doorWidth &&
               player.y >= this.doorY && 
               player.y <= this.doorY + this.doorHeight;
    }
    
    playerPassDoor(player) {
        player.passedDoor = true;
        logger.info(`🚪 ${player.name} pasó por la puerta`);
        this._logMovement(player, 'DOOR_PASS', {});
    }
    
    collectCoins(player) {
        for (const coin of this.coins) {
            if (coin.collected) continue;
            
            if (player.x + 16 > coin.x - 8 && 
                player.x - 16 < coin.x + 8 &&
                player.y > coin.y - 8 && 
                player.y - 32 < coin.y + 8) {
                
                coin.collected = true;
                player.coins = (player.coins || 0) + coin.value;
            }
        }
    }
    
    isInDeathZone(player) {
        for (const zone of this.deathZones) {
            if (player.y >= zone.y && 
                player.y <= zone.y + zone.height &&
                player.x >= zone.x && 
                player.x <= zone.x + zone.width) {
                return true;
            }
        }
        
        if (player.y > this.height - 50) return true;
        return false;
    }
    
    respawnPlayer(player) {
        player.deaths = (player.deaths || 0) + 1;
        
        let closestSpawn = this.spawnPoints[0];
        let closestDist = Infinity;
        
        for (const spawn of this.spawnPoints) {
            const dist = Math.abs(player.x - spawn.x) + Math.abs(player.y - spawn.y);
            if (dist < closestDist) {
                closestDist = dist;
                closestSpawn = spawn;
            }
        }
        
        player.x = closestSpawn.x;
        player.y = closestSpawn.y;
        player.vy = 0;
        player.vx = 0;
        
        if (this.keyHolder === player.id) {
            this.dropKey(player);
        }
        
        logger.info(`💀 ${player.name} murió → respawn`);
        this._logMovement(player, 'DEATH', { totalDeaths: player.deaths });
    }
    
    allPlayersPassedDoor(room) {
        if (!room || room.players.size === 0 || !this.doorOpen) return false;
        
        let allPassed = true;
        room.players.forEach((player) => {
            if (!player.isVisor && !player.passedDoor) {
                allPassed = false;
            }
        });
        
        return allPassed;
    }
    
    checkPlayerCountActivators(room) {
        const playerCount = room ? room.players.size : 0;
        
        if (playerCount >= 4 && !this._bonusCoinsSpawned) {
            this._spawnBonusCoins();
            this._bonusCoinsSpawned = true;
            logger.info(`🌟 Monedas bonus activadas (${playerCount} jugadores)`);
        }
        
        return {
            bonusCoinsActive: playerCount >= 4,
            totalPlayers: playerCount
        };
    }
    
    _spawnBonusCoins() {
        const bonusPositions = [
            { x: 200, y: 350 }, { x: 220, y: 350 }, { x: 240, y: 350 },
            { x: 390, y: 350 }, { x: 410, y: 350 }
        ];
        
        bonusPositions.forEach((pos, index) => {
            this.coins.push({
                id: `bonus_coin_${index}`,
                x: pos.x,
                y: pos.y,
                width: 12,
                height: 12,
                collected: false,
                value: 25,
                isBonus: true
            });
        });
    }
    
    completeLevel(room) {
        this.levelCompleted = true;
        room.setState("completed");
        
        let totalCoins = 0;
        room.players.forEach(p => { totalCoins += (p.coins || 0); });
        
        const totalAvailable = this.coins.reduce((sum, c) => sum + c.value, 0);
        const elapsedTime = this.getElapsedTime(room);
        
        logger.info("═".repeat(50));
        logger.info("🎉 ¡NIVEL COMPLETADO! - Ocean World");
        logger.info(`   ⏱️  Tiempo: ${elapsedTime}s`);
        logger.info(`   🪙 Monedas: ${totalCoins}/${totalAvailable}`);
        logger.info(`   👥 Jugadores: ${room.players.size}`);
        logger.info("═".repeat(50));
        
        room.players.forEach((player) => {
            if (!player.isVisor) {
                this._logMovement(player, 'LEVEL_COMPLETE', {
                    coins: player.coins || 0,
                    time: elapsedTime
                });
            }
        });
    }
    
    getElapsedTime(room) {
        if (!room || !room.startTime) return 0;
        return Math.round((Date.now() - room.startTime) / 1000);
    }
    
    reset() {
        this.keyTaken = false;
        this.keyHolder = null;
        this.doorOpen = false;
        this.levelCompleted = false;
        this._bonusCoinsSpawned = false;
        this.coins = [];
        this.generateCoins();
        logger.info("🔄 Mundo reiniciado");
    }
    
    getState() {
        return {
            key: {
                x: this.keyX,
                y: this.keyY,
                width: this.keyWidth,
                height: this.keyHeight,
                taken: this.keyTaken,
                holderId: this.keyHolder
            },
            door: {
                x: this.doorX,
                y: this.doorY,
                width: this.doorWidth,
                height: this.doorHeight,
                open: this.doorOpen
            },
            coins: this.coins
                .filter(c => !c.collected)
                .map(c => ({
                    id: c.id,
                    x: c.x,
                    y: c.y,
                    value: c.value,
                    isBonus: c.isBonus || false
                })),
            totalCoins: this.coins.length,
            collectedCoins: this.coins.filter(c => c.collected).length,
            platforms: this.platforms,
            deathZones: this.deathZones,
            spawnPoints: this.spawnPoints,
            playerZone: this.playerZone,
            levelCompleted: this.levelCompleted,
            width: this.width,
            height: this.height,
            viewportWidth: this.viewportWidth,
            viewportHeight: this.viewportHeight,
            backgroundColor: this.backgroundColor
        };
    }
    
    async _logMovement(player, action, data = {}) {
        if (!this.currentSessionId || !Movement) return;
        
        try {
            await Movement.create({
                sessionId: this.currentSessionId,
                playerId: player.id,
                playerName: player.name,
                action: action,
                position: {
                    x: Math.round(player.x),
                    y: Math.round(player.y)
                },
                data: data,
                timestamp: new Date()
            });
        } catch (error) {
            // No detener el juego por error de logging
        }
    }
}

module.exports = GameWorld;
module.exports.setModels = setModels;