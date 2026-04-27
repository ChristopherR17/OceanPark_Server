const express = require('express');
const router = express.Router();
const PlayerModel = require('../models/Player');
const GameSession = require('../models/GameSession');
const Movement = require('../models/Movement');

// Middleware de seguridad básico
const API_KEY = process.env.NAVISION_API_KEY || 'oceanpark-navision-2026';

function checkApiKey(req, res, next) {
    const key = req.headers['x-api-key'] || req.query.api_key;
    if (key !== API_KEY) {
        return res.status(401).json({ error: 'API Key inválida' });
    }
    next();
}

router.use(checkApiKey);

// ==================== JUGADORES ====================

/**
 * GET /api/navision/jugadores
 * Obtiene todos los jugadores para Navision
 */
router.get('/jugadores', async (req, res) => {
    try {
        const players = await PlayerModel.find({})
            .select({
                playerId: 1,
                nickname: 1,
                category: 1,
                'stats.totalSessions': 1,
                'stats.totalPlayTime': 1,
                'stats.totalCoins': 1,
                'stats.totalDeaths': 1,
                'stats.levelsCompleted': 1,
                'stats.bestScore': 1,
                'stats.averageSessionTime': 1,
                'stats.averageCoinsPerSession': 1,
                firstSeen: 1,
                lastSeen: 1
            })
            .lean();

        // Transformar al formato que espera Navision
        const data = players.map(p => ({
            Player_ID: p.playerId,
            Nickname: p.nickname,
            Categoria: p.category,
            Total_Sesiones: p.stats?.totalSessions || 0,
            Total_Tiempo_Seg: p.stats?.totalPlayTime || 0,
            Total_Monedas: p.stats?.totalCoins || 0,
            Total_Muertes: p.stats?.totalDeaths || 0,
            Niveles_Completados: p.stats?.levelsCompleted || 0,
            Mejor_Puntuacion: p.stats?.bestScore || 0,
            Promedio_Tiempo_Sesion: p.stats?.averageSessionTime || 0,
            Promedio_Monedas_Sesion: p.stats?.averageCoinsPerSession || 0,
            Fecha_Registro: p.firstSeen?.toISOString() || null,
            Ultima_Conexion: p.lastSeen?.toISOString() || null
        }));

        res.json({
            success: true,
            total: data.length,
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

/**
 * GET /api/navision/jugadores/:id
 * Obtiene un jugador específico
 */
router.get('/jugadores/:id', async (req, res) => {
    try {
        const player = await PlayerModel.findOne({ playerId: req.params.id }).lean();
        if (!player) {
            return res.status(404).json({ error: 'Jugador no encontrado' });
        }

        res.json({
            success: true,
            data: {
                Player_ID: player.playerId,
                Nickname: player.nickname,
                Categoria: player.category,
                Total_Sesiones: player.stats?.totalSessions || 0,
                Total_Tiempo_Seg: player.stats?.totalPlayTime || 0,
                Total_Monedas: player.stats?.totalCoins || 0,
                Total_Muertes: player.stats?.totalDeaths || 0,
                Niveles_Completados: player.stats?.levelsCompleted || 0,
                Mejor_Puntuacion: player.stats?.bestScore || 0,
                Fecha_Registro: player.firstSeen?.toISOString() || null,
                Ultima_Conexion: player.lastSeen?.toISOString() || null
            }
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ==================== PARTIDAS ====================

/**
 * GET /api/navision/partidas
 * Obtiene todas las partidas
 * Query params:
 *   - desde: fecha inicio (ISO string)
 *   - hasta: fecha fin (ISO string)
 *   - completadas: true/false
 */
router.get('/partidas', async (req, res) => {
    try {
        const filter = {};
        
        if (req.query.desde) {
            filter.startTime = { $gte: new Date(req.query.desde) };
        }
        if (req.query.hasta) {
            filter.startTime = { ...filter.startTime, $lte: new Date(req.query.hasta) };
        }
        if (req.query.completadas === 'true') {
            filter.completed = true;
        } else if (req.query.completadas === 'false') {
            filter.completed = false;
        }

        const sessions = await GameSession.find(filter)
            .sort({ startTime: -1 })
            .limit(req.query.limit ? parseInt(req.query.limit) : 1000)
            .lean();

        const data = sessions.map(s => ({
            Sesion_ID: s.sessionId,
            Nivel_Nombre: s.levelName,
            Nivel_Indice: s.levelIndex,
            Numero_Jugadores: s.playerCount,
            Completada: s.completed ? 1 : 0,
            Estado: s.completed ? 'completed' : 'playing',
            Fecha_Inicio: s.startTime?.toISOString() || null,
            Fecha_Fin: s.endTime?.toISOString() || null,
            Duracion_Segundos: s.duration || 0,
            Total_Monedas_Recogidas: s.totalCoinsCollected || 0,
            Total_Monedas_Disponibles: s.totalCoinsAvailable || 0,
            Total_Muertes: s.totalDeaths || 0,
            Mejor_Puntuacion: s.bestPlayerScore || 0,
            Tiempo_Promedio_Jugador: s.averagePlayerTime || 0
        }));

        res.json({
            success: true,
            total: data.length,
            filtros: {
                desde: req.query.desde || null,
                hasta: req.query.hasta || null,
                completadas: req.query.completadas || 'todas'
            },
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ==================== PARTIDAS - JUGADORES ====================

/**
 * GET /api/navision/partidas-jugadores
 * Obtiene el detalle de jugadores por partida
 */
router.get('/partidas-jugadores', async (req, res) => {
    try {
        const filter = {};
        if (req.query.sesion_id) {
            filter.sessionId = req.query.sesion_id;
        }

        const sessions = await GameSession.find(filter)
            .sort({ startTime: -1 })
            .limit(req.query.limit ? parseInt(req.query.limit) : 1000)
            .lean();

        const data = [];
        for (const session of sessions) {
            for (const player of session.players) {
                data.push({
                    Sesion_ID: session.sessionId,
                    Player_ID: player.playerId,
                    Nickname: player.nickname,
                    Categoria: player.category,
                    Monedas_Recogidas: player.coinsCollected || 0,
                    Muertes: player.deaths || 0,
                    Puntuacion: player.score || 0,
                    Completo_Nivel: player.completed ? 1 : 0,
                    Tiempo_Jugado_Seg: player.timePlayed || 0
                });
            }
        }

        res.json({
            success: true,
            total: data.length,
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ==================== MOVIMIENTOS ====================

/**
 * GET /api/navision/movimientos
 * Obtiene movimientos recientes
 */
router.get('/movimientos', async (req, res) => {
    try {
        const filter = {};
        
        if (req.query.sesion_id) {
            filter.sessionId = req.query.sesion_id;
        }
        if (req.query.player_id) {
            filter.playerId = req.query.player_id;
        }
        if (req.query.accion) {
            filter.action = req.query.accion.toUpperCase();
        }

        const movements = await Movement.find(filter)
            .sort({ timestamp: -1 })
            .limit(req.query.limit ? parseInt(req.query.limit) : 5000)
            .lean();

        const data = movements.map(m => ({
            Sesion_ID: m.sessionId,
            Player_ID: m.playerId,
            Player_Nombre: m.playerName,
            Accion: m.action,
            Posicion_X: m.position?.x || 0,
            Posicion_Y: m.position?.y || 0,
            Datos_Adicionales: JSON.stringify(m.data || {}),
            Fecha_Accion: m.timestamp?.toISOString() || null
        }));

        res.json({
            success: true,
            total: data.length,
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ==================== RÉCORDS DE NIVELES ====================

/**
 * GET /api/navision/niveles-records
 * Obtiene los récords por nivel y número de jugadores
 */
router.get('/niveles-records', async (req, res) => {
    try {
        const records = await GameSession.aggregate([
            { $match: { completed: true } },
            { 
                $group: {
                    _id: { 
                        nivel: '$levelName', 
                        jugadores: '$playerCount' 
                    },
                    mejorTiempo: { $min: '$duration' },
                    mejorPuntuacion: { $max: '$bestPlayerScore' },
                    totalPartidas: { $sum: 1 },
                    tiempoPromedio: { $avg: '$duration' },
                    puntuacionPromedio: { $avg: '$bestPlayerScore' },
                    ultimaPartida: { $max: '$startTime' }
                }
            },
            { $sort: { '_id.nivel': 1, '_id.jugadores': 1 } }
        ]);

        const data = records.map(r => ({
            Nivel_Nombre: r._id.nivel,
            Numero_Jugadores: r._id.jugadores,
            Mejor_Tiempo_Seg: r.mejorTiempo,
            Mejor_Puntuacion: r.mejorPuntuacion,
            Total_Partidas: r.totalPartidas,
            Total_Completadas: r.totalPartidas,
            Tiempo_Promedio_Seg: Math.round(r.tiempoPromedio),
            Puntuacion_Promedio: Math.round(r.puntuacionPromedio),
            Ultima_Actualizacion: r.ultimaPartida?.toISOString() || null
        }));

        res.json({
            success: true,
            total: data.length,
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ==================== KPIs ====================

/**
 * GET /api/navision/kpi/1
 * KPI 1: Distribución de jugadores por categoría
 */
router.get('/kpi/1', async (req, res) => {
    try {
        const distribution = await PlayerModel.aggregate([
            {
                $group: {
                    _id: '$category',
                    numJugadores: { $sum: 1 },
                    tiempoPromedio: { $avg: '$stats.averageSessionTime' },
                    nivelesPromedio: { $avg: '$stats.levelsCompleted' },
                    monedasPromedio: { $avg: '$stats.averageCoinsPerSession' }
                }
            },
            { $sort: { _id: 1 } }
        ]);

        const total = distribution.reduce((sum, d) => sum + d.numJugadores, 0);

        const data = distribution.map(d => ({
            Categoria: d._id,
            Numero_Jugadores: d.numJugadores,
            Porcentaje: total > 0 ? Math.round((d.numJugadores / total) * 10000) / 100 : 0,
            Tiempo_Promedio_Seg: Math.round(d.tiempoPromedio || 0),
            Niveles_Promedio: Math.round(d.nivelesPromedio || 0),
            Monedas_Promedio: Math.round(d.monedasPromedio || 0)
        }));

        res.json({
            success: true,
            kpi: 'Distribución de Jugadores por Categoría',
            totalJugadores: total,
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

/**
 * GET /api/navision/kpi/2
 * KPI 2: Tiempo medio de juego por categoría
 */
router.get('/kpi/2', async (req, res) => {
    try {
        const sessions = await GameSession.find({ completed: true }).lean();
        
        const categoryStats = {};
        
        for (const session of sessions) {
            for (const player of session.players) {
                const cat = player.category || 'Junior';
                if (!categoryStats[cat]) {
                    categoryStats[cat] = {
                        sesiones: new Set(),
                        jugadores: new Set(),
                        tiempoTotal: 0,
                        monedasTotal: 0,
                        completados: 0,
                        totalRegistros: 0
                    };
                }
                
                categoryStats[cat].sesiones.add(session.sessionId);
                categoryStats[cat].jugadores.add(player.playerId);
                categoryStats[cat].tiempoTotal += (player.timePlayed || 0);
                categoryStats[cat].monedasTotal += (player.coinsCollected || 0);
                if (player.completed) categoryStats[cat].completados++;
                categoryStats[cat].totalRegistros++;
            }
        }

        const data = Object.entries(categoryStats).map(([categoria, stats]) => ({
            Categoria: categoria,
            Numero_Sesiones: stats.sesiones.size,
            Numero_Jugadores: stats.jugadores.size,
            Tiempo_Promedio_Sesion_Seg: stats.totalRegistros > 0 
                ? Math.round(stats.tiempoTotal / stats.totalRegistros) 
                : 0,
            Tiempo_Promedio_Sesion_Min: stats.totalRegistros > 0 
                ? Math.round((stats.tiempoTotal / stats.totalRegistros) / 60 * 100) / 100 
                : 0,
            Tiempo_Total_Seg: stats.tiempoTotal,
            Tiempo_Total_Horas: Math.round(stats.tiempoTotal / 3600 * 100) / 100,
            Monedas_Promedio: stats.totalRegistros > 0 
                ? Math.round(stats.monedasTotal / stats.totalRegistros) 
                : 0,
            Tasa_Completado: stats.totalRegistros > 0 
                ? Math.round((stats.completados / stats.totalRegistros) * 10000) / 100 
                : 0
        }));

        res.json({
            success: true,
            kpi: 'Tiempo Medio de Juego por Categoría',
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

/**
 * GET /api/navision/kpi/3
 * KPI 3: Puntuación media por sesión
 */
router.get('/kpi/3', async (req, res) => {
    try {
        const sessions = await GameSession.find({ completed: true })
            .sort({ startTime: -1 })
            .limit(100)
            .lean();

        const data = sessions.map(s => {
            const puntuaciones = {
                total: 0,
                junior: { suma: 0, count: 0 },
                senior: { suma: 0, count: 0 },
                expert: { suma: 0, count: 0 }
            };

            for (const player of s.players) {
                const cat = (player.category || 'junior').toLowerCase();
                puntuaciones.total += player.score || 0;
                
                if (puntuaciones[cat]) {
                    puntuaciones[cat].suma += player.score || 0;
                    puntuaciones[cat].count++;
                }
            }

            return {
                Sesion_ID: s.sessionId,
                Nivel_Nombre: s.levelName,
                Numero_Jugadores: s.playerCount,
                Duracion_Segundos: s.duration,
                Fecha_Inicio: s.startTime?.toISOString() || null,
                Mejor_Puntuacion_Sesion: s.bestPlayerScore,
                Puntuacion_Total_Sesion: puntuaciones.total,
                Puntuacion_Promedio_Jugador: s.players.length > 0 
                    ? Math.round(puntuaciones.total / s.players.length) 
                    : 0,
                Monedas_Promedio_Jugador: s.players.length > 0 
                    ? Math.round(s.totalCoinsCollected / s.players.length) 
                    : 0,
                Puntuacion_Promedio_Junior: puntuaciones.junior.count > 0 
                    ? Math.round(puntuaciones.junior.suma / puntuaciones.junior.count) 
                    : 0,
                Puntuacion_Promedio_Senior: puntuaciones.senior.count > 0 
                    ? Math.round(puntuaciones.senior.suma / puntuaciones.senior.count) 
                    : 0,
                Puntuacion_Promedio_Expert: puntuaciones.expert.count > 0 
                    ? Math.round(puntuaciones.expert.suma / puntuaciones.expert.count) 
                    : 0,
                Porcentaje_Recoleccion: s.totalCoinsAvailable > 0 
                    ? Math.round((s.totalCoinsCollected / s.totalCoinsAvailable) * 10000) / 100 
                    : 0
            };
        });

        res.json({
            success: true,
            kpi: 'Puntuación Media por Sesión',
            total: data.length,
            data: data,
            exportado: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

/**
 * GET /api/navision/health
 * Verifica que la API está funcionando
 */
router.get('/health', async (req, res) => {
    try {
        const playerCount = await PlayerModel.countDocuments();
        const sessionCount = await GameSession.countDocuments();
        const movementCount = await Movement.countDocuments();

        res.json({
            success: true,
            status: 'online',
            mongodb: 'connected',
            stats: {
                jugadores: playerCount,
                partidas: sessionCount,
                movimientos: movementCount
            },
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ 
            success: false,
            status: 'error',
            error: error.message 
        });
    }
});

module.exports = router;