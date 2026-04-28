const logger = require("./logger");

function startGameLoop(room, world, broadcastState) {
    const TICK_RATE = 60;
    const DT = 1000 / TICK_RATE; // ~16.67ms

    // Constantes de física
    const SPEED = 5;
    const GRAVITY = 0.8;
    const JUMP_FORCE = -12;
    const MAX_FALL_SPEED = 15;
    const GROUND_Y = 300; // Y del suelo por defecto

    let lastTime = Date.now();

    setInterval(() => {
        if (room.state !== "playing" || room.players.size === 0) return;

        const now = Date.now();
        const deltaFrames = Math.min((now - lastTime) / DT, 5); // Evitar espiral de muerte
        lastTime = now;

        // Actualizar físicas
        for (let f = 0; f < deltaFrames; f++) {
            updatePhysics(room, world);
        }

        // Actualizar animaciones
        updateAnimations(room);

        // Broadcast del estado
        broadcastState();
    }, DT);
}

function updatePhysics(room, world) {
    room.players.forEach((player) => {
        if (player.isVisor) return;

        // 1. MOVIMIENTO HORIZONTAL
        if (player.input.left) {
            player.vx = -SPEED;
            player.facingRight = false;
        } else if (player.input.right) {
            player.vx = SPEED;
            player.facingRight = true;
        } else {
            player.vx *= 0.8; // Fricción
            if (Math.abs(player.vx) < 0.1) player.vx = 0;
        }

        player.x += player.vx;

        // 2. SALTO
        if (player.input.jump && player.onGround) {
            player.vy = JUMP_FORCE;
            player.onGround = false;
            player.input.jump = false; // Consumir el evento
        }

        // 3. GRAVEDAD
        if (!player.onGround) {
            player.vy += GRAVITY;
            if (player.vy > MAX_FALL_SPEED) {
                player.vy = MAX_FALL_SPEED;
            }
        }

        player.y += player.vy;

        // 4. COLISIÓN CON SUELO (usar plataformas del mundo)
        const floorY = world.getFloorYAt(player.x) || GROUND_Y;
        
        if (player.y >= floorY) {
            player.y = floorY;
            player.vy = 0;
            player.onGround = true;
        } else {
            player.onGround = false;
        }

        // 5. LÍMITES DEL MUNDO
        player.x = Math.max(0, Math.min(world.width, player.x));
        player.y = Math.max(0, Math.min(world.height, player.y));

        // 6. COLISIÓN CON LLAVE
        if (!world.keyTaken && world.isPlayerTouchingKey(player)) {
            world.pickUpKey(player);
            logger.info(`🔑 ${player.name} recogió la llave`);
        }

        // 7. COLISIÓN CON PUERTA
        if (world.doorOpen && world.isPlayerAtDoor(player)) {
            player.passedDoor = true;
            logger.info(`🚪 ${player.name} pasó por la puerta`);
        }

        // 8. COLISIÓN CON MONEDAS
        world.collectCoins(player);

        // 9. TRAMPAS / ZONAS DE MUERTE
        if (world.isInDeathZone(player)) {
            world.respawnPlayer(player);
            logger.info(`💀 ${player.name} cayó en una trampa`);
        }
    });

    // 10. COLISIONES ENTRE JUGADORES (se apilan)
    resolvePlayerCollisions(room);

    // 11. Verificar si todos pasaron la puerta
    if (world.doorOpen && world.allPlayersPassedDoor(room)) {
        world.completeLevel(room);
        logger.info("🎉 ¡Todos los jugadores pasaron la puerta! Nivel completado");
    }
}

function resolvePlayerCollisions(room) {
    const players = Array.from(room.players.values()).filter(p => !p.isVisor);
    
    for (let i = 0; i < players.length; i++) {
        for (let j = i + 1; j < players.length; j++) {
            const a = players[i];
            const b = players[j];
            
            const distX = Math.abs(a.x - b.x);
            const distY = Math.abs(a.y - b.y);
            
            const COLLISION_DIST_X = 28;
            const COLLISION_DIST_Y = 30;
            
            if (distX < COLLISION_DIST_X && distY < COLLISION_DIST_Y) {
                // Separar horizontalmente
                const overlapX = COLLISION_DIST_X - distX;
                if (a.x < b.x) {
                    a.x -= overlapX / 2;
                    b.x += overlapX / 2;
                } else {
                    a.x += overlapX / 2;
                    b.x -= overlapX / 2;
                }
                
                // Si uno está sobre el otro, apilar
                if (a.y < b.y - 10) {
                    b.y = a.y + COLLISION_DIST_Y;
                    b.vy = 0;
                    b.onGround = true;
                } else if (b.y < a.y - 10) {
                    a.y = b.y + COLLISION_DIST_Y;
                    a.vy = 0;
                    a.onGround = true;
                }
            }
        }
    }
}

function updateAnimations(room) {
    room.players.forEach((player) => {
        if (!player.onGround) {
            player.state = "JUMP";
        } else if (Math.abs(player.vx) > 0.5) {
            player.state = "RUN";
        } else {
            player.state = "IDLE";
        }
    });
}

module.exports = startGameLoop;