const winston = require("winston");
const path = require("path");
const fs = require("fs");

//Confirmar que existe la carpeta "logs"
const logDir = path.join(process.cwd(), "logs");

if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir);
}

// 🧠 Configuración del logger
const logger = winston.createLogger({
  level: "debug",

  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.printf(({ timestamp, level, message }) => {
      return `[${timestamp}] ${level.toUpperCase()}: ${message}`;
    })
  ),

  transports: [
    // 🖥️ consola (desarrollo)
    new winston.transports.Console({
      format: winston.format.colorize()
    }),

    // 📄 archivo (persistencia)
    new winston.transports.File({
      filename: path.join(logDir, "server.log")
    })
  ]
});

module.exports = logger;