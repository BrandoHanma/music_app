import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'dart:io';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'MusicApp',
          theme: themeProvider.themeData,
          home: const AudioExplorerPage(),
        );
      },
    );
  }
}

class AudioExplorerPage extends StatefulWidget {
  const AudioExplorerPage({Key? key}) : super(key: key);

  @override
  _AudioExplorerPageState createState() => _AudioExplorerPageState();
}

class _AudioExplorerPageState extends State<AudioExplorerPage> with SingleTickerProviderStateMixin {
  List<FileSystemEntity> audioFiles = [];
  bool isLoading = false;
  final player = AudioPlayer();
  String? currentlyPlayingPath;
  bool hasPermission = false;
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  Duration? duration;
  Duration position = Duration.zero;
  double volume = 1.0;
  String searchQuery = '';
  late AnimationController _searchAnimationController;
  bool isSearching = false;

  List<FileSystemEntity> get filteredAudioFiles => audioFiles.where((file) {
    final fileName = file.path.split('/').last.toLowerCase();
    final path = file.path.toLowerCase();
    final query = searchQuery.toLowerCase();
    return fileName.contains(query) || path.contains(query);
  }).toList();

  @override
  void initState() {
    super.initState();
    _initializePermissions();
    _setupAudioHandlers();
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  void _toggleSearch() {
    setState(() {
      isSearching = !isSearching;
      if (isSearching) {
        _searchAnimationController.forward();
      } else {
        _searchAnimationController.reverse();
        searchQuery = '';
      }
    });
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

    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });
  }

  void _playNext() {
    if (audioFiles.isEmpty) return;
    
    int currentIndex = audioFiles.indexWhere((file) => file.path == currentlyPlayingPath);
    if (currentIndex == -1) return;
    
    int nextIndex = (currentIndex + 1) % audioFiles.length;
    _playPause(audioFiles[nextIndex].path);
  }

  void _playPrevious() {
    if (audioFiles.isEmpty) return;
    
    int currentIndex = audioFiles.indexWhere((file) => file.path == currentlyPlayingPath);
    if (currentIndex == -1) return;
    
    int previousIndex = currentIndex - 1;
    if (previousIndex < 0) previousIndex = audioFiles.length - 1;
    _playPause(audioFiles[previousIndex].path);
  }

  Widget _buildSearchBar() {
    return SizeTransition(
      axisAlignment: -1.0,
      sizeFactor: _searchAnimationController,
      child: Container(
        height: 60,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Buscar canciones...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      searchQuery = '';
                    });
                  },
                )
              : null,
          ),
          onChanged: (value) {
            setState(() {
              searchQuery = value;
            });
          },
        ),
      ),
      ),
    );
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
        final audioPermission = await Permission.audio.request();
        final mediaPermission = await Permission.mediaLibrary.request();
        
        print('Audio permission: $audioPermission');
        print('Media permission: $mediaPermission');
        
        hasPermission = audioPermission.isGranted || mediaPermission.isGranted;
      } else {
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
            await _scanDirectory(dir, files);
          }
        } catch (e) {
          print('Error accediendo a $path: $e');
        }
      }

      if (mounted) {
        setState(() {
          audioFiles = files..sort((a, b) => 
            a.path.split('/').last.toLowerCase().compareTo(b.path.split('/').last.toLowerCase())
          );
          isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(files.isEmpty 
              ? 'No se encontraron archivos M4A' 
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
      final List<FileSystemEntity> entities = await directory.list(recursive: true).toList();
      
      for (var entity in entities) {
        try {
          if (entity is File && entity.path.toLowerCase().endsWith('.m4a')) {
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
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.music_note, color: Theme.of(context).primaryColor),
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
            ProgressBar(
              progress: position,
              total: duration ?? Duration.zero,
              buffered: duration ?? Duration.zero,
              onSeek: (duration) async {
                await player.seek(duration);
                setState(() {
                  position = duration;
                });
              },
              barHeight: 8,
              thumbRadius: 8,
              thumbGlowRadius: 16,
              baseBarColor: Colors.grey[300],
              progressBarColor: Theme.of(context).primaryColor,
              bufferedBarColor: Theme.of(context).primaryColor.withOpacity(0.2),
              timeLabelTextStyle: const TextStyle(
                fontSize: 14,
                color: Colors.black,
              ),
              thumbCanPaintOutsideBar: false,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(volume == 0 
                          ? Icons.volume_off 
                          : Icons.volume_up,
                          color: Theme.of(context).primaryColor),
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
                          activeColor: Theme.of(context).primaryColor,
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
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _playPrevious,
                  color: Theme.of(context).primaryColor,
                  iconSize: 32,
                ),
                IconButton(
                  icon: Icon(
                    player.playing 
                      ? Icons.pause_circle_filled 
                      : Icons.play_circle_filled,
                    size: 40,
                    color: Theme.of(context).primaryColor,
                  ),
                  onPressed: () => _playPause(currentlyPlayingPath!),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _playNext,
                  color: Theme.of(context).primaryColor,
                  iconSize: 32,
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
        title: const Text('Explorador de música'),
        elevation: 4,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          // Botón para cambiar tema
         PopupMenuButton<ThemeData>(
  icon: const Icon(Icons.palette),
  tooltip: 'Cambiar tema',
  onSelected: (ThemeData theme) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.setTheme(theme);
  },
  itemBuilder: (BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return [
      PopupMenuItem(
        value: themeProvider.themes[0],
        child: Row(
          children: const [
            Icon(Icons.circle, color: Colors.blue),
            SizedBox(width: 10),
            Text('Tema Azul'),
          ],
        ),
      ),
      PopupMenuItem(
        value: themeProvider.themes[1],
        child: Row(
          children: const [
            Icon(Icons.circle, color: Colors.purple),
            SizedBox(width: 10),
            Text('Tema Morado'),
          ],
        ),
      ),
      PopupMenuItem(
        value: themeProvider.themes[2],
        child: Row(
          children: const [
            Icon(Icons.circle, color: Colors.green),
            SizedBox(width: 10),
            Text('Tema Verde'),
          ],
        ),
      ),
      PopupMenuItem(
        value: themeProvider.themes[3],
        child: Row(
          children: const [
            Icon(Icons.circle, color: Colors.red),
            SizedBox(width: 10),
            Text('Tema Rojo'),
          ],
        ),
      ),
      // Nueva opción para el tema oscuro
      PopupMenuItem(
        value: themeProvider.themes[4],
        child: Row(
          children: const [
            Icon(Icons.dark_mode),
            SizedBox(width: 10),
            Text('Tema Oscuro'),
          ],
        ),
      ),
    ];
  },
),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar canciones',
            onPressed: _toggleSearch,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordenar canciones',
            onSelected: (String value) {
              switch (value) {
                case 'name':
                  setState(() {
                    audioFiles.sort((a, b) => a.path.split('/').last
                        .toLowerCase()
                        .compareTo(b.path.split('/').last.toLowerCase()));
                  });
                  break;
                case 'date':
                  setState(() {
                    audioFiles.sort((a, b) => File(b.path)
                        .lastModifiedSync()
                        .compareTo(File(a.path).lastModifiedSync()));
                  });
                  break;
                case 'size':
                  setState(() {
                    audioFiles.sort((a, b) => File(b.path)
                        .lengthSync()
                        .compareTo(File(a.path).lengthSync()));
                  });
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(Icons.sort_by_alpha),
                    SizedBox(width: 10),
                    Text('Por nombre'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(Icons.access_time),
                    SizedBox(width: 10),
                    Text('Por fecha'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'size',
                child: Row(
                  children: [
                    Icon(Icons.data_usage),
                    SizedBox(width: 10),
                    Text('Por tamaño'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar lista',
            onPressed: checkAndRequestPermissions,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Buscando archivos canciones...'),
                      ],
                    ),
                  )
                : !hasPermission
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_off,
                              size: 64,
                              color: Theme.of(context).primaryColor.withOpacity(0.5),
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
                                Icon(
                                  Icons.music_off,
                                  size: 64,
                                  color: Theme.of(context).primaryColor.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No se encontraron canciones',
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
                            itemCount: filteredAudioFiles.length,
                            itemBuilder: (context, index) {
                              final file = filteredAudioFiles[index];
                              final fileName = file.path.split('/').last;
                              final isPlaying = currentlyPlayingPath == file.path;

                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(Icons.music_note, color: Theme.of(context).primaryColor),
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
                                trailing: isPlaying
                                  ? Icon(Icons.equalizer, color: Theme.of(context).primaryColor)
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
    _searchAnimationController.dispose();
    super.dispose();
  }
}