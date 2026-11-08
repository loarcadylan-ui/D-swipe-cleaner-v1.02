import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class GalleryCleanerScreen extends StatefulWidget {
  const GalleryCleanerScreen({super.key});

  @override
  State<GalleryCleanerScreen> createState() => _GalleryCleanerScreenState();
}

class _GalleryCleanerScreenState extends State<GalleryCleanerScreen> {
  bool _isLoading = true;
  bool _hasPermission = false;
  List<AssetEntity> _assets = [];
  int _currentIndex = 0;
  final List<AssetEntity> _trashedAssets = [];
  final List<AssetEntity> _keptAssets = [];
  int _bytesFreed = 0;
  final Map<String, int> _sizes = {}; // id de foto -> bytes
  bool _busy = false;

  // Offset para animación visual del swipe
  Offset _dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoad();
  }

  Future<void> _requestPermissionAndLoad() async {
    setState(() => _isLoading = true);

    // 1. Solicitar permisos de almacenamiento/fotos en Android (API 33+ READ_MEDIA_IMAGES y versiones anteriores)
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!(ps.isAuth || ps == PermissionState.limited)) {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
      return;
    }

    setState(() => _hasPermission = true);

    // 2. Obtener álbumes (Cámara y Screenshots)
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isNotEmpty) {
      final List<AssetEntity> photos = await albums.first.getAssetListRange(
        start: 0,
        end: 100, // Primer lote de 100 fotos
      );
      setState(() {
        _assets = photos;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
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
      _trashedAssets.add(current);
      _sizes[current.id] = size;
      _bytesFreed += size;
      _currentIndex++;
      _dragOffset = Offset.zero;
    });
    _busy = false;
  }

  void _swipeRightKeep() {
    if (_currentIndex >= _assets.length) return;
    final current = _assets[_currentIndex];
    setState(() {
      _keptAssets.add(current);
      _currentIndex++;
      _dragOffset = Offset.zero;
    });
  }

  void _undo() {
    if (_currentIndex <= 0) return;
    setState(() {
      _currentIndex--;
      final undone = _assets[_currentIndex];
      if (_trashedAssets.remove(undone)) {
        _bytesFreed -= _sizes.remove(undone.id) ?? 0;
        if (_bytesFreed < 0) _bytesFreed = 0;
      }
      _keptAssets.remove(undone);
      _dragOffset = Offset.zero;
    });
  }

  // Borra de verdad las fotos marcadas (Android pide confirmación al usuario)
  Future<void> _deleteTrashed(BuildContext sheetContext) async {
    final ids = _trashedAssets.map((e) => e.id).toList();
    if (ids.isEmpty) {
      Navigator.pop(sheetContext);
      return;
    }
    final deletedIds = await PhotoManager.editor.deleteWithIds(ids);
    if (!mounted) return;
    final deleted = deletedIds.toSet();

    setState(() {
      // Solo quitamos las que Android realmente borró (si cancelas, se conservan)
      _assets.removeWhere((a) => deleted.contains(a.id));
      _trashedAssets.removeWhere((a) => deleted.contains(a.id));
      for (final id in deleted) {
        _sizes.remove(id);
      }
      _bytesFreed = _trashedAssets.fold<int>(0, (sum, a) => sum + (_sizes[a.id] ?? 0));
      // Volvemos a la primera foto que aún no hayas decidido
      final pending = _assets.indexWhere(
        (a) => !_trashedAssets.contains(a) && !_keptAssets.contains(a),
      );
      _currentIndex = pending == -1 ? _assets.length : pending;
      _dragOffset = Offset.zero;
    });
    Navigator.pop(sheetContext);
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
                  'SwipeClean necesita acceso a fotos y capturas para poder analizarlas y ayudarte a liberar espacio.',
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
        title: const Text('SwipeClean', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Badge(
              label: Text('${_trashedAssets.length}'),
              child: const Icon(Icons.delete_outline),
            ),
            onPressed: () => _showTrashDialog(),
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
                        Text(
                          'Foto ${_currentIndex + 1} de ${_assets.length}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        Text(
                          '${(_bytesFreed / (1024 * 1024)).toStringAsFixed(1)} MB marcados',
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

              // Sello visual "ELIMINAR" al deslizar a la izquierda
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
            const Text(
              '¡Lote Limpiado!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Marcaste ${(_bytesFreed / (1024 * 1024)).toStringAsFixed(1)} MB (${_trashedAssets.length} fotos) para borrar. Abre la papelera (arriba a la derecha) para eliminarlas.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentIndex = 0;
                  _trashedAssets.clear();
                  _keptAssets.clear();
                  _bytesFreed = 0;
                  _sizes.clear();
                });
              },
              child: const Text('Reiniciar Limpieza'),
            ),
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
              'Papelera (${_trashedAssets.length} elementos)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Las fotos marcadas pueden ser borradas definitivamente del almacenamiento de tu teléfono con confirmación de Android.',
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
