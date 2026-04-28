const express = require('express');
const router = express.Router();
const PlayerModel = require('../models/Player');
const GameSession = require('../models/GameSession');
const Movement = require('../models/Movement');

const API_KEY = process.env.NAVISION_API_KEY || 'oceanpark-navision-2026';

function checkApiKey(req, res, next) {
    const key = req.headers['x-api-key'] || req.query.api_key;
    if (key !== API_KEY) {
        return res.status(401).json({ error: 'API Key inválida' });
    }
    next();
}

router.use(checkApiKey);

// GET /api/navision/jugadores
router.get('/jugadores', async (req, res) => {
    try {
        const players = await PlayerModel.find({}).lean();
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
        res.json({ success: true, total: data.length, data: data, exportado: new Date().toISOString() });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET /api/navision/partidas
router.get('/partidas', async (req, res) => {
    try {
        const filter = {};
        if (req.query.desde) filter.startTime = { $gte: new Date(req.query.desde) };
        if (req.query.hasta) filter.startTime = { ...filter.startTime, $lte: new Date(req.query.hasta) };
        if (req.query.completadas === 'true') filter.completed = true;
        else if (req.query.completadas === 'false') filter.completed = false;

        const sessions = await GameSession.find(filter).sort({ startTime: -1 }).limit(1000).lean();
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
        res.json({ success: true, total: data.length, data: data, exportado: new Date().toISOString() });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET /api/navision/partidas-jugadores
router.get('/partidas-jugadores', async (req, res) => {
    try {
        const filter = {};
        if (req.query.sesion_id) filter.sessionId = req.query.sesion_id;
        const sessions = await GameSession.find(filter).sort({ startTime: -1 }).limit(1000).lean();
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
        res.json({ success: true, total: data.length, data: data, exportado: new Date().toISOString() });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET /api/navision/kpi/1
router.get('/kpi/1', async (req, res) => {
    try {
        const distribution = await PlayerModel.aggregate([
            { $group: { _id: '$category', numJugadores: { $sum: 1 } } },
            { $sort: { _id: 1 } }
        ]);
        const total = distribution.reduce((sum, d) => sum + d.numJugadores, 0);
        const data = distribution.map(d => ({
            Categoria: d._id,
            Numero_Jugadores: d.numJugadores,
            Porcentaje: total > 0 ? Math.round((d.numJugadores / total) * 10000) / 100 : 0
        }));
        res.json({ success: true, kpi: 'Distribución de Jugadores por Categoría', totalJugadores: total, data: data });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET /api/navision/kpi/2
router.get('/kpi/2', async (req, res) => {
    try {
        const sessions = await GameSession.find({ completed: true }).lean();
        const categoryStats = {};
        for (const session of sessions) {
            for (const player of session.players) {
                const cat = player.category || 'Junior';
                if (!categoryStats[cat]) {
                    categoryStats[cat] = { sesiones: new Set(), tiempoTotal: 0, totalRegistros: 0 };
                }
                categoryStats[cat].sesiones.add(session.sessionId);
                categoryStats[cat].tiempoTotal += (player.timePlayed || 0);
                categoryStats[cat].totalRegistros++;
            }
        }
        const data = Object.entries(categoryStats).map(([categoria, stats]) => ({
            Categoria: categoria,
            Numero_Sesiones: stats.sesiones.size,
            Tiempo_Promedio_Sesion_Seg: stats.totalRegistros > 0 ? Math.round(stats.tiempoTotal / stats.totalRegistros) : 0,
            Tiempo_Total_Horas: Math.round(stats.tiempoTotal / 3600 * 100) / 100
        }));
        res.json({ success: true, kpi: 'Tiempo Medio de Juego por Categoría', data: data });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET /api/navision/kpi/3
router.get('/kpi/3', async (req, res) => {
    try {
        const sessions = await GameSession.find({ completed: true }).sort({ startTime: -1 }).limit(100).lean();
        const data = sessions.map(s => ({
            Sesion_ID: s.sessionId,
            Nivel_Nombre: s.levelName,
            Numero_Jugadores: s.playerCount,
            Duracion_Segundos: s.duration,
            Mejor_Puntuacion_Sesion: s.bestPlayerScore,
            Puntuacion_Total_Sesion: s.players.reduce((sum, p) => sum + (p.score || 0), 0)
        }));
        res.json({ success: true, kpi: 'Puntuación Media por Sesión', total: data.length, data: data });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET /api/navision/health
router.get('/health', async (req, res) => {
    try {
        const playerCount = await PlayerModel.countDocuments();
        const sessionCount = await GameSession.countDocuments();
        res.json({ success: true, status: 'online', stats: { jugadores: playerCount, partidas: sessionCount } });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;