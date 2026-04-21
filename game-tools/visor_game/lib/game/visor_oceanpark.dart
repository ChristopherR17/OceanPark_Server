import 'package:flame/game.dart';
import 'package:flame/components.dart';
import '../network/server_manager.dart'; // Importamos nuestra red

class VisorOceanPark extends FlameGame {
  late ServerManager server;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    
    // 1. CARGAR GRÁFICOS BASE
    await _cargarEscenario();

    // 2. INICIAR CONEXIÓN AL SERVIDOR
    // Le pasamos la función _manejarDatosDelServidor para que nos avise
    server = ServerManager(onDatosRecibidos: _manejarDatosDelServidor);
    server.conectar();
  }

  Future<void> _cargarEscenario() async {
    // Fondo
    final spriteFondo = await loadSprite('backgrounds/background.png');
    final fondo = SpriteComponent(sprite: spriteFondo);
    add(fondo);

    // Plataforma
    final spritePlataforma = await loadSprite('platforms/platform.png');
    final plataforma = SpriteComponent(
      sprite: spritePlataforma,
      size: Vector2(fondo.size.x, 60), 
      anchor: Anchor.bottomLeft,
      position: Vector2(0, fondo.size.y),
    );
    add(plataforma);

    // Obstáculos
    final spriteObstaculo = await loadSprite('platforms/obstacle.png');
    final obstaculo = SpriteComponent(
      sprite: spriteObstaculo,
      size: Vector2(70, 70), 
      anchor: Anchor.bottomLeft,
      position: Vector2(300, fondo.size.y - 60),
    );
    add(obstaculo);

    print("🎨 Escenario visual cargado");
  }

  // 3. REACCIONAR A LOS DATOS DEL SERVIDOR
  void _manejarDatosDelServidor(Map<String, dynamic> mensaje) {
    final tipo = mensaje['type'];
    final data = mensaje['data'];

    switch (tipo) {
      case 'player-joined':
        print("📺 VISOR: Entró un jugador nuevo -> ${data['player']['nickname']}");
        // TODO: Aquí cargaremos el sprite del nuevo jugador
        break;
      
      case 'player-left':
        print("📺 VISOR: Un jugador se fue.");
        // TODO: Aquí borraremos el sprite del jugador que se fue
        break;

      case 'player-moved':
        // TODO: Aquí actualizaremos las coordenadas (X, Y) del sprite
        break;
    }
  }
}