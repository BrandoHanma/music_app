import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M4A Explorer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AudioExplorerPage(),
    );
  }
}

class AudioExplorerPage extends StatefulWidget {
  const AudioExplorerPage({Key? key}) : super(key: key);

  @override
  _AudioExplorerPageState createState() => _AudioExplorerPageState();
}

class _AudioExplorerPageState extends State<AudioExplorerPage> {
  List<FileSystemEntity> audioFiles = [];
  bool isLoading = false;
  final player = AudioPlayer();
  String? currentlyPlayingPath;
  bool hasPermission = false;
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  Duration? duration;
  Duration position = Duration.zero;
  double volume = 1.0;

  @override
  void initState() {
    super.initState();
    _initializePermissions();
    _setupAudioHandlers();
  }

  void _setupAudioHandlers() {
    player.positionStream.listen((pos) {
      setState(() => position = pos);
    });

    player.durationStream.listen((dur) {
      setState(() => duration = dur);
    });

    player.volumeStream.listen((vol) {
      setState(() => volume = vol);
    });
  }

  Future<void> _initializePermissions() async {
    await Future.delayed(const Duration(milliseconds: 100));
    await checkAndRequestPermissions();
  }

  Future<void> checkAndRequestPermissions() async {
    setState(() => isLoading = true);
    print('Verificando permisos...');

    try {
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      print('Android SDK Version: $sdkInt');

      if (sdkInt >= 33) {
        // Android 13 o superior
        final audioPermission = await Permission.audio.request();
        final mediaPermission = await Permission.mediaLibrary.request();
        
        print('Audio permission: $audioPermission');
        print('Media permission: $mediaPermission');
        
        hasPermission = audioPermission.isGranted || mediaPermission.isGranted;
      } else {
        // Android 12 o inferior
        final storagePermission = await Permission.storage.request();
        print('Storage permission: $storagePermission');
        hasPermission = storagePermission.isGranted;
      }

      setState(() {});

      if (hasPermission) {
        await _loadAudioFiles();
      } else {
        _showPermissionDeniedDialog();
      }
    } catch (e) {
      print('Error checking permissions: $e');
    } finally {
      if (!hasPermission) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Permisos necesarios'),
        content: const Text(
            'Para encontrar tus archivos M4A, necesitamos acceder al almacenamiento. '
            'Por favor, concede todos los permisos solicitados en la siguiente pantalla.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Abrir Configuración'),
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
          ),
          TextButton(
            child: const Text('Intentar de nuevo'),
            onPressed: () {
              Navigator.of(context).pop();
              checkAndRequestPermissions();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadAudioFiles() async {
    print('Iniciando búsqueda de archivos M4A...');
    final List<FileSystemEntity> files = [];
    
    try {
      final List<String> musicDirectories = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Sounds',
        '/storage/emulated/0/Audio',
        '/storage/emulated/0/media/audio',
        '/storage/emulated/0/HIOS/Downloads',
        '/storage/emulated/0/HiOS',
        '/storage/emulated/0/snaptube',
      ];

      try {
        final externalDirs = await getExternalStorageDirectories();
        if (externalDirs != null) {
          for (var dir in externalDirs) {
            String path = dir.path.split('Android')[0];
            musicDirectories.add(path);
            print('Añadiendo directorio externo: $path');
          }
        }
      } catch (e) {
        print('Error obteniendo directorios externos: $e');
      }

      for (String path in musicDirectories) {
        final dir = Directory(path);
        try {
          if (await dir.exists()) {
            print('Buscando en: $path');
            final List<FileSystemEntity> dirContents = await dir.list().toList();
            print('Contenido del directorio $path: ${dirContents.length} elementos');
            await _scanDirectory(dir, files);
          } else {
            print('Directorio no encontrado: $path');
          }
        } catch (e) {
          print('Error accediendo a $path: $e');
        }
      }

      print('Búsqueda completada. Archivos encontrados: ${files.length}');
      
      if (mounted) {
        setState(() {
          audioFiles = files;
          isLoading = false;
        });

        for (var file in files) {
          print('Archivo encontrado: ${file.path}');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(files.isEmpty 
              ? 'No se encontraron archivos M4A. Intenta copiar algunos archivos M4A a la carpeta Música.' 
              : 'Se encontraron ${files.length} archivos M4A'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error durante la búsqueda: $e');
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar archivos: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _scanDirectory(Directory directory, List<FileSystemEntity> files) async {
    try {
      print('Escaneando contenidos de: ${directory.path}');
      final List<FileSystemEntity> entities = await directory.list(recursive: true).toList();
      print('Encontrados ${entities.length} elementos en ${directory.path}');
      
      for (var entity in entities) {
        try {
          if (entity is File && entity.path.toLowerCase().endsWith('.m4a')) {
            print('Archivo M4A encontrado: ${entity.path}');
            files.add(entity);
          }
        } catch (e) {
          print('Error procesando ${entity.path}: $e');
        }
      }
    } catch (e) {
      print('Error escaneando ${directory.path}: $e');
    }
  }

  Future<void> _playPause(String filePath) async {
    try {
      if (currentlyPlayingPath == filePath) {
        if (player.playing) {
          await player.pause();
        } else {
          await player.play();
        }
      } else {
        await player.stop();
        await player.setFilePath(filePath);
        await player.play();
        setState(() {
          currentlyPlayingPath = filePath;
          position = Duration.zero;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al reproducir: $e')),
      );
    }
  }

  Widget _buildNowPlayingCard() {
    if (currentlyPlayingPath == null) return const SizedBox.shrink();

    final currentFile = audioFiles.firstWhere(
      (file) => file.path == currentlyPlayingPath,
      orElse: () => audioFiles.first,
    );
    final fileName = currentFile.path.split('/').last;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Miniatura y título
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_note, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Barra de progreso
            ProgressBar(
              progress: position,
              total: duration ?? Duration.zero,
              buffered: duration ?? Duration.zero,
              onSeek: (duration) {
                player.seek(duration);
              },
              timeLabelTextStyle: const TextStyle(
                fontSize: 14,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 8),

            // Controles
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Control de volumen
                Expanded(
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(volume == 0 
                          ? Icons.volume_off 
                          : Icons.volume_up),
                        onPressed: () {
                          setState(() {
                            volume = volume == 0 ? 1.0 : 0.0;
                            player.setVolume(volume);
                          });
                        },
                      ),
                      Expanded(
                        child: Slider(
                          value: volume,
                          onChanged: (newValue) {
                            setState(() {
                              volume = newValue;
                              player.setVolume(newValue);
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Botones de control
                IconButton(
                  icon: Icon(
                    player.playing 
                      ? Icons.pause_circle_filled 
                      : Icons.play_circle_filled,
                    size: 40,
                    color: Colors.blue,
                  ),
                  onPressed: () => _playPause(currentlyPlayingPath!),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorador M4A'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: checkAndRequestPermissions,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Buscando archivos M4A...'),
                      ],
                    ),
                  )
                : !hasPermission
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.folder_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Se requieren permisos de almacenamiento',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: checkAndRequestPermissions,
                              child: const Text('Conceder Permisos'),
                            ),
                          ],
                        ),
                      )
                    : audioFiles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.music_off,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No se encontraron archivos M4A',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadAudioFiles,
                                  child: const Text('Buscar archivos'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: audioFiles.length,
                            itemBuilder: (context, index) {
                              final file = audioFiles[index];
                              final fileName = file.path.split('/').last;
                              final isPlaying = currentlyPlayingPath == file.path;

                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.music_note, color: Colors.blue),
                                ),
                                title: Text(
                                  fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  file.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing:isPlaying
                                  ? const Icon(Icons.equalizer, color: Colors.blue)
                                  : null,
                                onTap: () => _playPause(file.path),
                              );
                            },
                          ),
          ),
          if (currentlyPlayingPath != null) _buildNowPlayingCard(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
                                