import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class ServerManager {
  late WebSocketChannel _canal;
  final String url = 'ws://ieticloudpro.ieti.cat:3000';
  
  // Esta función permitirá que el juego reaccione cuando lleguen datos
  final Function(Map<String, dynamic>) onDatosRecibidos;

  ServerManager({required this.onDatosRecibidos});

  void conectar() {
    try {
      _canal = WebSocketChannel.connect(Uri.parse(url));
      print("📡 Conectando al servidor de OceanPark...");

      _canal.stream.listen(
        (mensajeServidor) {
          _procesarMensaje(mensajeServidor);
        },
        onError: (error) => print("❌ Error de red: $error"),
        onDone: () => print("🔌 Desconectado del servidor"),
      );
    } catch (e) {
      print("No se pudo iniciar el socket: $e");
    }
  }

  void _procesarMensaje(dynamic mensajeServidor) {
    try {
      final mensaje = jsonDecode(mensajeServidor);
      final tipo = mensaje['type'];
      final data = mensaje['data'] ?? {};

      // Respuestas automáticas del visor
      if (tipo == 'connected') {
        print("✅ Conectado. Socket ID: ${data['socketId']}");
        _enviarRegistroVisor();
      } else if (tipo == 'registered') {
        print("✅ Registrado como visor.");
        // NOTA: Para ver una partida, tendrás que decirle a qué sala unirse.
        // Descomenta la línea de abajo y pon el código de la sala cuando lo tengas:
        // unirseASala('CODIGO_AQUI');
      }

      // Le pasamos los datos limpios al juego (Flame) para que dibuje
      onDatosRecibidos(mensaje);
      
    } catch (e) {
      print("Error decodificando mensaje: $e");
    }
  }

  // --- Comandos que enviamos al servidor ---
  void _enviarRegistroVisor() {
    final mensaje = {
      "type": "register",
      "data": {
        "nickname": "Pantalla_Visor",
        "color": "#000000"
      }
    };
    _canal.sink.add(jsonEncode(mensaje));
  }

  void unirseASala(String codigoSala) {
    final mensaje = {
      "type": "join-room",
      "data": {
        "roomId": codigoSala
      }
    };
    _canal.sink.add(jsonEncode(mensaje));
    print("Tentando unirse a la sala: $codigoSala");
  }
}