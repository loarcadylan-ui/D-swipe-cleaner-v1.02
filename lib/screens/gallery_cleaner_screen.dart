import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAppName = 'D Swipe Cleaner';

/// Guarda en el teléfono qué fotos ya decidiste, para continuar donde te quedaste.
class _ProgressStore {
  static const String _keptKey = 'kept_ids';
  static const String _trashKey = 'trash_entries'; // formato "id|bytes"

  late SharedPreferences _prefs;

  /// Fotos que decidiste conservar.
  final Set<String> keptIds = {};

  /// Fotos marcadas para borrar (id -> tamaño en bytes), aún sin borrar.
  final Map<String, int> trashSizes = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    keptIds
      ..clear()
      ..addAll(_prefs.getStringList(_keptKey) ?? const <String>[]);
    trashSizes.clear();
    for (final entry in _prefs.getStringList(_trashKey) ?? const <String>[]) {
      final i = entry.lastIndexOf('|');
      if (i <= 0) continue;
      trashSizes[entry.substring(0, i)] = int.tryParse(entry.substring(i + 1)) ?? 0;
    }
  }

  Future<void> save() async {
    await _prefs.setStringList(_keptKey, keptIds.toList());
    await _prefs.setStringList(
      _trashKey,
      trashSizes.entries.map((e) => '${e.key}|${e.value}').toList(),
    );
  }
}

class GalleryCleanerScreen extends StatefulWidget {
  const GalleryCleanerScreen({super.key});

  @override
  State<GalleryCleanerScreen> createState() => _GalleryCleanerScreenState();
}

class _GalleryCleanerScreenState extends State<GalleryCleanerScreen> {
  static const int _batchSize = 100;

  final _ProgressStore _store = _ProgressStore();

  bool _isLoading = true;
  bool _hasPermission = false;
  bool _busy = false;
  bool _exhausted = false; // ya no quedan fotos sin revisar

  AssetPathEntity? _album;
  int _totalCount = 0;

  List<AssetEntity> _assets = []; // lote actual (hasta 100 fotos sin revisar)
  int _currentIndex = 0;
  final List<AssetEntity> _trashAssets = []; // marcadas para borrar (todas las sesiones)

  // Offset para animación visual del swipe
  Offset _dragOffset = Offset.zero;

  int get _bytesMarked => _store.trashSizes.values.fold<int>(0, (sum, b) => sum + b);

  int get _remaining {
    final decided = _store.keptIds.length + _store.trashSizes.length;
    final r = _totalCount - decided;
    return r < 0 ? 0 : r;
  }

  String get _markedMb => (_bytesMarked / (1024 * 1024)).toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoad();
  }

  Future<void> _requestPermissionAndLoad() async {
    setState(() => _isLoading = true);

    // 1. Permisos de fotos en Android (READ_MEDIA_IMAGES en API 33+ y anteriores)
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!(ps.isAuth || ps == PermissionState.limited)) {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
      return;
    }
    _hasPermission = true;

    // 2. Recuperar el progreso guardado, la papelera y el siguiente lote
    await _store.load();
    await _loadAlbum();
    await _restoreTrash();
    await _loadNextBatch();
  }

  Future<void> _loadAlbum() async {
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      _album = null;
      _totalCount = 0;
      return;
    }
    _album = albums.first;
    _totalCount = await albums.first.assetCountAsync;
  }

  /// Vuelve a cargar las fotos que estaban marcadas para borrar en sesiones anteriores.
  Future<void> _restoreTrash() async {
    _trashAssets.clear();
    final List<String> missing = [];
    for (final id in _store.trashSizes.keys.toList()) {
      final asset = await AssetEntity.fromId(id);
      if (asset == null) {
        missing.add(id); // ya no existe (la borraste desde otra app)
      } else {
        _trashAssets.add(asset);
      }
    }
    if (missing.isNotEmpty) {
      for (final id in missing) {
        _store.trashSizes.remove(id);
      }
      await _store.save();
    }
  }

  /// Carga las siguientes [_batchSize] fotos que todavía no has revisado.
  Future<void> _loadNextBatch() async {
    setState(() => _isLoading = true);

    final album = _album;
    final List<AssetEntity> batch = [];

    if (album != null) {
      final Set<String> decided = {..._store.keptIds, ..._store.trashSizes.keys};
      const int page = 200;
      int start = 0;
      while (batch.length < _batchSize) {
        final List<AssetEntity> chunk = await album.getAssetListRange(
          start: start,
          end: start + page,
        );
        if (chunk.isEmpty) break;
        for (final a in chunk) {
          if (!decided.contains(a.id)) {
            batch.add(a);
            if (batch.length >= _batchSize) break;
          }
        }
        if (chunk.length < page) break;
        start += page;
      }
    }

    if (!mounted) return;
    setState(() {
      _assets = batch;
      _currentIndex = 0;
      _dragOffset = Offset.zero;
      _exhausted = batch.length < _batchSize;
      _isLoading = false;
    });
  }

  Future<void> _swipeLeftTrash() async {
    if (_busy || _currentIndex >= _assets.length) return;
    _busy = true;
    final current = _assets[_currentIndex];
    int size = 0;
    try {
      final file = await current.file;
      size = file != null ? await file.length() : 0;
    } catch (_) {}
    if (!mounted) return;

    setState(() {
      _trashAssets.add(current);
      _store.trashSizes[current.id] = size;
      _currentIndex++;
      _dragOffset = Offset.zero;
    });
    _busy = false;
    _store.save();
  }

  void _swipeRightKeep() {
    if (_busy || _currentIndex >= _assets.length) return;
    final current = _assets[_currentIndex];
    setState(() {
      _store.keptIds.add(current.id);
      _currentIndex++;
      _dragOffset = Offset.zero;
    });
    _store.save();
  }

  void _undo() {
    if (_busy || _currentIndex <= 0) return;
    setState(() {
      _currentIndex--;
      final undone = _assets[_currentIndex];
      _store.keptIds.remove(undone.id);
      if (_store.trashSizes.remove(undone.id) != null) {
        _trashAssets.removeWhere((a) => a.id == undone.id);
      }
      _dragOffset = Offset.zero;
    });
    _store.save();
  }

  /// Borra de verdad las fotos marcadas (Android pide confirmación al usuario).
  Future<void> _deleteTrashed(BuildContext sheetContext) async {
    final ids = _store.trashSizes.keys.toList();
    if (ids.isEmpty) {
      Navigator.pop(sheetContext);
      return;
    }
    final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(ids);
    if (!mounted) return;
    final deleted = deletedIds.toSet();

    final removedBeforeCursor =
        _assets.take(_currentIndex).where((a) => deleted.contains(a.id)).length;

    setState(() {
      // Solo quitamos las que Android realmente borró (si cancelas, se conservan)
      _assets.removeWhere((a) => deleted.contains(a.id));
      int newIndex = _currentIndex - removedBeforeCursor;
      if (newIndex < 0) newIndex = 0;
      if (newIndex > _assets.length) newIndex = _assets.length;
      _currentIndex = newIndex;

      _trashAssets.removeWhere((a) => deleted.contains(a.id));
      for (final id in deleted) {
        _store.trashSizes.remove(id);
      }
      _dragOffset = Offset.zero;
    });
    await _store.save();
    await _loadAlbum();
    if (!mounted) return;
    setState(() {});
    if (sheetContext.mounted) Navigator.pop(sheetContext);
  }

  Future<void> _resetProgress() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Reiniciar progreso?'),
        content: const Text(
          'Volverás a ver todas las fotos desde el principio y se quitarán las marcas de la papelera. No se borra ninguna foto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    _store.keptIds.clear();
    _store.trashSizes.clear();
    _trashAssets.clear();
    await _store.save();
    await _loadNextBatch();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6366F1)),
        ),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_shared_outlined, size: 64, color: Colors.indigoAccent),
                const SizedBox(height: 16),
                const Text(
                  'Permiso de Galería Requerido',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '$kAppName necesita acceso a tus fotos para poder mostrarlas y ayudarte a liberar espacio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _requestPermissionAndLoad,
                  icon: const Icon(Icons.security),
                  label: const Text('Conceder Permisos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bool isDone = _currentIndex >= _assets.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName, style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Badge(
              label: Text('${_trashAssets.length}'),
              child: const Icon(Icons.delete_outline),
            ),
            onPressed: () => _showTrashDialog(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reset') _resetProgress();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'reset',
                child: Text('Reiniciar progreso'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: isDone
            ? _buildFinishedView()
            : Column(
                children: [
                  // Barra de progreso y contador
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Foto ${_currentIndex + 1} de ${_assets.length} · $_remaining sin revisar',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_markedMb MB marcados',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  // Tarjeta deslizable central estilo Tinder
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _dragOffset += details.delta;
                          });
                        },
                        onPanEnd: (details) {
                          if (_dragOffset.dx < -120) {
                            _swipeLeftTrash();
                          } else if (_dragOffset.dx > 120) {
                            _swipeRightKeep();
                          } else {
                            setState(() => _dragOffset = Offset.zero);
                          }
                        },
                        child: _buildSwipeCard(_assets[_currentIndex]),
                      ),
                    ),
                  ),

                  // Botones flotantes de apoyo inferiores
                  _buildFloatingControls(),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }

  Widget _buildSwipeCard(AssetEntity asset) {
    final double rotation = _dragOffset.dx / 400;

    return Transform.translate(
      offset: _dragOffset,
      child: Transform.rotate(
        angle: rotation,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          height: MediaQuery.of(context).size.height * 0.62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Imagen thumbnail de alta calidad
              _AssetThumb(key: ValueKey(asset.id), asset: asset),

              // Degradado oscuro para lectura de información
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black26, Colors.transparent, Colors.black87],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),

              // Sello visual "PAPELERA" al deslizar a la izquierda
              if (_dragOffset.dx < -30)
                Positioned(
                  top: 30,
                  right: 24,
                  child: Opacity(
                    opacity: (-_dragOffset.dx / 120).clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.redAccent, width: 3),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.red.withOpacity(0.2),
                      ),
                      child: const Text(
                        'PAPELERA',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),

              // Sello visual "CONSERVAR" al deslizar a la derecha
              if (_dragOffset.dx > 30)
                Positioned(
                  top: 30,
                  left: 24,
                  child: Opacity(
                    opacity: (_dragOffset.dx / 120).clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.greenAccent, width: 3),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.green.withOpacity(0.2),
                      ),
                      child: const Text(
                        'CONSERVAR',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),

              // Datos del archivo en la parte inferior
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.title ?? 'Captura/Foto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${asset.width}x${asset.height} · ${asset.createDateTime.toLocal().toString().substring(0, 16)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Botón Deslizar a la izquierda: Eliminar
          FloatingActionButton.large(
            heroTag: 'btn_trash',
            onPressed: _swipeLeftTrash,
            backgroundColor: const Color(0xFFEF4444),
            elevation: 4,
            child: const Icon(Icons.delete_rounded, size: 36, color: Colors.white),
          ),

          // Botón Deshacer
          FloatingActionButton(
            heroTag: 'btn_undo',
            onPressed: _undo,
            backgroundColor: const Color(0xFF334155),
            elevation: 2,
            child: const Icon(Icons.undo_rounded, size: 24, color: Colors.white70),
          ),

          // Botón Deslizar a la derecha: Conservar
          FloatingActionButton.large(
            heroTag: 'btn_keep',
            onPressed: _swipeRightKeep,
            backgroundColor: const Color(0xFF10B981),
            elevation: 4,
            child: const Icon(Icons.favorite_rounded, size: 36, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 80),
            const SizedBox(height: 16),
            Text(
              _exhausted ? '¡Galería completa!' : '¡Lote terminado!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _exhausted
                  ? 'No quedan fotos por revisar.'
                  : 'Quedan unas $_remaining fotos sin revisar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Papelera: ${_trashAssets.length} fotos · $_markedMb MB esperando para borrarse.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (!_exhausted)
              ElevatedButton.icon(
                onPressed: _loadNextBatch,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Siguiente lote de $_batchSize'),
              ),
            if (_trashAssets.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _showTrashDialog,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Abrir papelera'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTrashDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Papelera (${_trashAssets.length} fotos · $_markedMb MB)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Las fotos marcadas se borrarán del almacenamiento de tu teléfono cuando confirmes en el aviso de Android.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Eliminar definitivamente en Android'),
                onPressed: () => _deleteTrashed(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muestra la miniatura de una foto usando solo el paquete photo_manager.
class _AssetThumb extends StatefulWidget {
  const _AssetThumb({super.key, required this.asset});
  final AssetEntity asset;

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  late final Future<Uint8List?> _future =
      widget.asset.thumbnailDataWithSize(const ThumbnailSize.square(800));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const ColoredBox(
            color: Color(0xFF131B2E),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}
