const logger = require("./logger");

// Referencia a los modelos de MongoDB (se inyectan para evitar dependencia circular)
let PlayerModel, GameSession, Movement;

function setModels(models) {
    PlayerModel = models.PlayerModel;
    GameSession = models.GameSession;
    Movement = models.Movement;
}

class GameWorld {
    constructor(room) {
        this.room = room;
        this.width = 2300;   // 100 tiles × 23px
        this.height = 1380;  // 60 tiles × 23px
        this.viewportWidth = 320;
        this.viewportHeight = 180;
        this.backgroundColor = "#568BB1"; // Azul océano
        
        // Spawn points sobre el suelo principal (Y es hacia abajo en este sistema)
        this.spawnPoints = [
            { x: 80, y: 370 },
            { x: 130, y: 370 },
            { x: 180, y: 370 },
            { x: 230, y: 370 },
            { x: 280, y: 370 },
            { x: 370, y: 370 },
            { x: 420, y: 370 },
            { x: 470, y: 370 }
        ];
        
        // === LLAVE ===
        this.keyX = 170;
        this.keyY = 295;
        this.keyWidth = 24;
        this.keyHeight = 24;
        this.keyTaken = false;
        this.keyHolder = null;
        
        // === PUERTA ===
        this.doorX = 460;
        this.doorY = 340;
        this.doorWidth = 40;
        this.doorHeight = 60;
        this.doorOpen = false;
        this.levelCompleted = false;
        
        // === MONEDAS ===
        this.coins = [];
        this.generateCoins();
        
        // === PLATAFORMAS (desde zones.json) ===
        this.platforms = [
            { x: 42, y: 402, width: 246, height: 13, name: "Suelo1" },
            { x: 335, y: 401, width: 168, height: 14, name: "Suelo2" },
            { x: 150, y: 325, width: 62, height: 14, name: "Plataforma" },
            { x: 58, y: 278, width: 47, height: 14, name: "PlataformaAlta" },
            { x: 104, y: 278, width: 16, height: 14, name: "Escalon1" },
            { x: 120, y: 294, width: 16, height: 14, name: "Escalon2" },
            { x: 42, y: 264, width: 16, height: 14, name: "Escalon3" },
            { x: 26, y: 249, width: 16, height: 14, name: "Escalon4" },
            { x: 134, y: 309, width: 16, height: 14, name: "Escalon5" }
        ];
        
        // === ZONAS DE MUERTE ===
        this.deathZones = [
            { x: -231, y: 436, width: 1664, height: 153, name: "Foso" }
        ];
        
        // === ZONA DE JUGADOR (spawn zone) ===
        this.playerZone = { x: 25, y: 100, width: 400, height: 400 };

        // === ESTADO DE LA SESIÓN ===
        this.currentSessionId = null;

        logger.info("🌍 Mundo Ocean World cargado:");
        logger.info(`   - ${this.platforms.length} plataformas`);
        logger.info(`   - ${this.coins.length} monedas`);
        logger.info(`   - Llave en (${this.keyX}, ${this.keyY})`);
        logger.info(`   - Puerta en (${this.doorX}, ${this.doorY})`);
    }
    
    generateCoins() {
        const coinPositions = [
            // Camino inicial (suelo principal 1)
            { x: 70, y: 380 }, { x: 110, y: 380 }, { x: 150, y: 380 },
            { x: 190, y: 380 }, { x: 230, y: 380 }, { x: 270, y: 380 },
            
            // Plataforma media (cerca de la llave)
            { x: 165, y: 300 }, { x: 185, y: 300 },
            
            // Suelo principal 2 (camino a la puerta)
            { x: 370, y: 375 }, { x: 410, y: 375 }, { x: 450, y: 375 },
            
            // Plataforma alta (recompensa por escalar)
            { x: 70, y: 255 }, { x: 85, y: 255 },
            
            // Cerca de la puerta
            { x: 480, y: 375 }
        ];
        
        this.coins = coinPositions.map((pos, index) => ({
            id: `coin_${index}`,
            x: pos.x,
            y: pos.y,
            width: 12,
            height: 12,
            collected: false,
            value: 10,
            collectedBy: null,
            collectedAt: null
        }));
    }
    
    /**
     * Establece el ID de la sesión actual para registrar movimientos
     */
    setSessionId(sessionId) {
        this.currentSessionId = sessionId;
    }
    
    /**
     * Obtener la Y del suelo en una posición X dada
     */
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
    
    /**
     * Verificar si un jugador toca la llave
     */
    isPlayerTouchingKey(player) {
        if (this.keyTaken) return false;
        
        const playerLeft = player.x - 16;
        const playerRight = player.x + 16;
        const playerTop = player.y - 32;
        const playerBottom = player.y;
        
        return playerRight > this.keyX && 
               playerLeft < this.keyX + this.keyWidth &&
               playerBottom > this.keyY && 
               playerTop < this.keyY + this.keyHeight;
    }
    
    /**
     * Recoger la llave
     */
    pickUpKey(player) {
        this.keyTaken = true;
        this.keyHolder = player.id;
        this.doorOpen = true;
        logger.info(`🔑 ¡${player.name} recogió la llave! La puerta se ha abierto.`);
        
        // Registrar en MongoDB
        this._logMovement(player, 'KEY_PICKUP', {
            keyHolder: player.id
        });
    }
    
    /**
     * Soltar la llave (cuando un jugador se desconecta o muere)
     */
    dropKey(player) {
        this.keyTaken = false;
        this.keyHolder = null;
        this.keyX = Math.round(player.x);
        this.keyY = Math.round(player.y - 16);
        this.doorOpen = false;
        logger.info(`🔑 Llave soltada en (${this.keyX}, ${this.keyY})`);
        
        // Registrar en MongoDB
        this._logMovement(player, 'KEY_DROP', {
            keyX: this.keyX,
            keyY: this.keyY
        });
    }
    
    /**
     * Verificar si un jugador está en la puerta
     */
    isPlayerAtDoor(player) {
        const playerCenterX = player.x;
        const playerBottom = player.y;
        
        return playerCenterX > this.doorX && 
               playerCenterX < this.doorX + this.doorWidth &&
               playerBottom >= this.doorY && 
               playerBottom <= this.doorY + this.doorHeight;
    }
    
    /**
     * Jugador pasa por la puerta
     */
    playerPassDoor(player) {
        player.passedDoor = true;
        logger.info(`🚪 ${player.name} pasó por la puerta`);
        
        // Registrar en MongoDB
        this._logMovement(player, 'DOOR_PASS', {
            doorOpen: this.doorOpen
        });
    }
    
    /**
     * Recoger monedas cercanas al jugador
     */
    collectCoins(player) {
        const playerLeft = player.x - 16;
        const playerRight = player.x + 16;
        const playerTop = player.y - 32;
        const playerBottom = player.y;
        
        let collectedAny = false;
        
        for (const coin of this.coins) {
            if (coin.collected) continue;
            
            if (playerRight > coin.x - 8 && 
                playerLeft < coin.x + 8 &&
                playerBottom > coin.y - 8 && 
                playerTop < coin.y + 8) {
                
                coin.collected = true;
                coin.collectedBy = player.id;
                coin.collectedAt = new Date();
                player.coins = (player.coins || 0) + coin.value;
                collectedAny = true;
                
                logger.info(`🪙 ${player.name} recogió moneda (+${coin.value}). Total: ${player.coins}`);
            }
        }
        
        if (collectedAny) {
            // Registrar en MongoDB (una vez por lote de monedas)
            this._logMovement(player, 'COIN_COLLECT', {
                totalCoins: player.coins,
                coinValue: 10
            });
        }
    }
    
    /**
     * Verificar si un jugador está en zona de muerte
     */
    isInDeathZone(player) {
        // Verificar zonas de muerte definidas
        for (const zone of this.deathZones) {
            if (player.y >= zone.y && player.y <= zone.y + zone.height) {
                if (player.x >= zone.x && player.x <= zone.x + zone.width) {
                    return true;
                }
            }
        }
        
        // También si cae por debajo del mundo
        if (player.y > this.height - 50) {
            return true;
        }
        
        return false;
    }
    
    /**
     * Reaparecer jugador en el spawn más cercano
     */
    respawnPlayer(player) {
        // Registrar muerte
        player.deaths = (player.deaths || 0) + 1;
        
        // Buscar el spawn más cercano
        let closestSpawn = this.spawnPoints[0];
        let closestDist = Infinity;
        
        for (const spawn of this.spawnPoints) {
            const dist = Math.abs(player.x - spawn.x) + Math.abs(player.y - spawn.y);
            if (dist < closestDist) {
                closestDist = dist;
                closestSpawn = spawn;
            }
        }
        
        // Guardar posición anterior para el log
        const deathX = Math.round(player.x);
        const deathY = Math.round(player.y);
        
        // Respawn
        player.x = closestSpawn.x;
        player.y = closestSpawn.y;
        player.vy = 0;
        player.vx = 0;
        
        // Si tenía la llave, la pierde
        if (this.keyHolder === player.id) {
            this.dropKey(player);
        }
        
        logger.info(`💀 ${player.name} murió en (${deathX}, ${deathY}) → Reaparece en (${closestSpawn.x}, ${closestSpawn.y})`);
        
        // Registrar en MongoDB
        this._logMovement(player, 'DEATH', {
            deathX: deathX,
            deathY: deathY,
            spawnX: closestSpawn.x,
            spawnY: closestSpawn.y,
            totalDeaths: player.deaths,
            deathCause: this._getDeathCause(deathX, deathY)
        });
    }
    
    /**
     * Determinar causa de muerte
     */
    _getDeathCause(x, y) {
        for (const zone of this.deathZones) {
            if (y >= zone.y && y <= zone.y + zone.height &&
                x >= zone.x && x <= zone.x + zone.width) {
                return zone.name || 'fell_into_pit';
            }
        }
        return y > this.height - 50 ? 'fell_off_world' : 'unknown';
    }
    
    /**
     * Verificar si todos los jugadores pasaron la puerta
     */
    allPlayersPassedDoor(room) {
        if (!room || room.players.size === 0) return false;
        if (!this.doorOpen) return false;
        
        let allPassed = true;
        room.players.forEach((player) => {
            if (!player.isVisor && !player.passedDoor) {
                allPassed = false;
            }
        });
        
        return allPassed;
    }
    
    /**
     * Verificar si se necesita un número mínimo de jugadores para activar algo
     * (activadores por número de jugadores)
     */
    checkPlayerCountActivators(room) {
        const playerCount = room ? room.players.size : 0;
        
        // Ejemplo: Si hay 4+ jugadores, aparecen monedas bonus
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
    
    /**
     * Generar monedas bonus (activador por número de jugadores)
     */
    _spawnBonusCoins() {
        const bonusPositions = [
            { x: 200, y: 350 },
            { x: 220, y: 350 },
            { x: 240, y: 350 },
            { x: 390, y: 350 },
            { x: 410, y: 350 }
        ];
        
        const startIndex = this.coins.length;
        bonusPositions.forEach((pos, index) => {
            this.coins.push({
                id: `bonus_coin_${index}`,
                x: pos.x,
                y: pos.y,
                width: 12,
                height: 12,
                collected: false,
                value: 25, // Bonus coins valen más
                collectedBy: null,
                collectedAt: null,
                isBonus: true
            });
        });
        
        logger.info(`🌟 ${bonusPositions.length} monedas bonus generadas (valor: 25 cada una)`);
    }
    
    /**
     * Completar el nivel
     */
    completeLevel(room) {
        this.levelCompleted = true;
        room.setState("completed");
        
        // Contar monedas totales
        let totalCoins = 0;
        room.players.forEach(p => {
            totalCoins += (p.coins || 0);
        });
        
        const totalAvailable = this.coins.reduce((sum, c) => sum + c.value, 0);
        const elapsedTime = this.getElapsedTime(room);
        
        logger.info("═".repeat(50));
        logger.info("🎉 ¡NIVEL COMPLETADO! - Ocean World");
        logger.info(`   ⏱️  Tiempo: ${elapsedTime}s`);
        logger.info(`   🪙 Monedas: ${totalCoins}/${totalAvailable}`);
        logger.info(`   👥 Jugadores: ${room.players.size}`);
        logger.info("═".repeat(50));
        
        // Registrar para cada jugador
        room.players.forEach((player) => {
            if (!player.isVisor) {
                this._logMovement(player, 'LEVEL_COMPLETE', {
                    coins: player.coins || 0,
                    time: elapsedTime,
                    passedDoor: player.passedDoor || false
                });
            }
        });
        
        return {
            completed: true,
            time: elapsedTime,
            totalCoins: totalCoins,
            totalAvailable: totalAvailable,
            playerCount: room.players.size
        };
    }
    
    /**
     * Obtener tiempo transcurrido de la sesión
     */
    getElapsedTime(room) {
        if (!room || !room.startTime) return 0;
        return Math.round((Date.now() - room.startTime) / 1000);
    }
    
    /**
     * Reiniciar el mundo para una nueva partida
     */
    reset() {
        this.keyTaken = false;
        this.keyHolder = null;
        this.doorOpen = false;
        this.levelCompleted = false;
        this._bonusCoinsSpawned = false;
        
        // Resetear monedas
        this.coins = [];
        this.generateCoins();
        
        logger.info("🔄 Mundo reiniciado para nueva partida");
    }
    
    /**
     * Obtener estado completo del mundo para enviar a clientes
     */
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
    
    /**
     * Obtener estadísticas para el ERP
     */
    getStats() {
        const totalCoinsCollected = this.coins.filter(c => c.collected).length;
        const totalCoinsValue = this.coins
            .filter(c => c.collected)
            .reduce((sum, c) => sum + c.value, 0);
        const bonusCoinsCollected = this.coins
            .filter(c => c.collected && c.isBonus).length;
        
        return {
            totalCoinsAvailable: this.coins.length,
            totalCoinsCollected: totalCoinsCollected,
            totalCoinsValue: totalCoinsValue,
            bonusCoinsCollected: bonusCoinsCollected,
            keyCollected: this.keyTaken,
            doorOpened: this.doorOpen,
            levelCompleted: this.levelCompleted
        };
    }
    
    /**
     * Registrar movimiento en MongoDB (interno)
     */
    async _logMovement(player, action, data = {}) {
        if (!this.currentSessionId) return;
        if (!Movement) return; // MongoDB no disponible
        
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
            logger.error(`Error registrando movimiento: ${error.message}`);
        }
    }
}

// Exportar clase y función para inyectar modelos
module.exports = GameWorld;
module.exports.setModels = setModels;