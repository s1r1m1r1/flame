library flame_texturepacker;

import 'package:collection/collection.dart';
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
import 'package:flame_texturepacker/src/texture_packer_parser.dart';
import 'package:flame_texturepacker/src/texture_packer_sprite.dart';

/// A texture atlas that contains a collection of [TexturePackerSprite]s.
///
/// This class provides methods to load and query sprites from a texture atlas
/// created by TexturePacker or similar tools.
class TexturePackerAtlas {
  /// List of all sprites contained in this atlas.
  final List<TexturePackerSprite> sprites;

  late final Map<String, List<TexturePackerSprite>> _spriteMap;

  /// Creates a new [TexturePackerAtlas] with the given [sprites].
  TexturePackerAtlas(this.sprites) {
    _initCache();
  }

  /// sort sprites by name and index
  /// init cache for O(1) sprite lookup
  void _initCache() {
    _spriteMap = {};
    final fuzzyPattern = RegExp(r'^(.+?)(_?\d+)$');

    for (final sprite in sprites) {
      final name = sprite.region.name;

      // 1. Exact match
      (_spriteMap[name] ??= []).add(sprite);

      // 2. Fuzzy match (base name)
      final match = fuzzyPattern.firstMatch(name);
      if (match != null) {
        final baseName = match.group(1)!;
        if (baseName != name) {
          (_spriteMap[baseName] ??= []).add(sprite);
        }
      }
    }

    // Sort all groups by index
    for (final group in _spriteMap.values) {
      group.sort((a, b) => a.region.index.compareTo(b.region.index));
    }
  }

  /// Creates a [TexturePackerAtlas] from parsed atlas data.
  ///
  /// [atlasData] - The parsed atlas data containing pages and regions
  /// [whiteList] - Optional list of sprite names to include.
  ///               If empty, all sprites are included
  /// [useOriginalSize] - Use original sprite dimensions before packing or not.
  factory TexturePackerAtlas.fromAtlas(
    TextureAtlasData atlasData, {
    List<String> whiteList = const [],
    bool useOriginalSize = true,
  }) {
    final List<TexturePackerSprite> sprites = [];
    for (final e in atlasData.regions) {
      if (whiteList.isEmpty || whiteList.any((key) => e.name.contains(key))) {
        sprites.add(
          TexturePackerSprite(
            e,
            useOriginalSize: useOriginalSize,
          ),
        );
      }
    }
    return TexturePackerAtlas(sprites);
  }

  /// Loads a texture atlas from a file path.
  ///
  /// [path] - The path to the atlas file
  /// [fromStorage] - Load from device storage (true) or assets (false)
  /// [useOriginalSize] - Use original sprite dimensions before packing or not.
  /// [images] - Optional Images cache to use for loading textures
  /// [assetsPrefix] - Prefix for asset paths (default: 'images')
  /// [assets] - Optional AssetsCache to use for loading assets
  /// [whiteList] - Optional list of sprite names to include.
  ///               If empty, all sprites are included
  ///
  /// Returns a [Future] that completes with the loaded [TexturePackerAtlas].
  static Future<TexturePackerAtlas> load(
    String path, {
    bool fromStorage = false,
    bool useOriginalSize = true,
    Images? images,
    String assetsPrefix = 'images',
    AssetsCache? assets,
    List<String> whiteList = const [],
    String? package,
  }) async {
    final atlasData = await loadAtlas(
      path,
      fromStorage: fromStorage,
      images: images,
      assets: assets,
      assetsPrefix: assetsPrefix,
      package: package,
    );

    return TexturePackerAtlas.fromAtlas(
      atlasData,
      whiteList: whiteList,
      useOriginalSize: useOriginalSize,
    );
  }

  /// Loads atlas data without creating a [TexturePackerAtlas] instance.
  ///
  /// [path] - The path to the atlas file
  /// [fromStorage] - Load from device storage (true) or assets (false)
  /// [images] - Optional Images cache to use for loading textures
  /// [assetsPrefix] - Prefix for asset paths (default: 'images')
  /// [assets] - Optional AssetsCache to use for loading assets
  /// [loadImages] - Whether to load images (default: true)
  ///
  /// Returns a [Future] that completes with the raw [TextureAtlasData].
  static Future<TextureAtlasData> loadAtlas(
    String path, {
    bool fromStorage = false,
    Images? images,
    AssetsCache? assets,
    String assetsPrefix = 'images',
    String? package,
    bool loadImages = true,
  }) async {
    try {
      final atlasData = await TexturePackerParser.parseAtlasMetadata(
        path,
        fromStorage: fromStorage,
        assets: assets,
        assetsPrefix: assetsPrefix,
        package: package,
      );

      if (loadImages) {
        await TexturePackerParser.loadAtlasDataImages(
          atlasData,
          path,
          fromStorage: fromStorage,
          images: images,
          package: package,
        );
      }
      return atlasData;
    } on Exception catch (e, stack) {
      final source = fromStorage ? 'storage' : 'assets';
      Error.throwWithStackTrace(
        Exception('Error loading $path from $source: $e'),
        stack,
      );
    }
  }

  /// Finds a sprite by its name.
  ///
  /// [name] - The name of the sprite to find
  ///
  /// Returns the first [TexturePackerSprite] with the given name
  /// or null if not found.
  TexturePackerSprite? findSpriteByName(String name) {
    return _spriteMap[name]?.firstOrNull;
  }

  /// Finds a sprite by its name and index.
  ///
  /// [name] - The name of the sprite to find
  /// [index] - The index of the sprite to find
  ///
  /// Returns the [TexturePackerSprite] with the given name and index
  /// or null if not found.
  TexturePackerSprite? findSpriteByNameIndex(String name, int index) {
    return _spriteMap[name]?.firstWhereOrNull(
      (sprite) => sprite.region.index == index,
    );
  }

  /// Finds all sprites with the given name.
  ///
  /// [name] - The name of the sprites to find
  ///
  /// Returns a list of all [TexturePackerSprite]s with the given name.
  /// If no exact match is found, it attempts to find sprites that look like
  /// indexed animation frames (e.g., "walk1", "walk_2") for that name.
  /// get sprites immediately (no search), O(1)
  List<TexturePackerSprite> findSpritesByName(String name) {
    return _spriteMap[name] ?? [];
  }

  /// [name] - The name of the sprites to use for the animation
  ///
  /// [stepTime] - The duration to display each frame, in seconds
  ///
  /// [loop] - Whether the animation should loop
  ///
  /// [useIndexedSpritesOnly] - Whether to use only indexed sprites
  /// for the animation. If true, sprites with index -1 will be ignored.
  SpriteAnimation getAnimation(
    String name, {
    double stepTime = 0.1,
    bool loop = true,
    bool useIndexedSpritesOnly = true,
  }) {
    var animationSprites = findSpritesByName(name);
    if (animationSprites.isEmpty) {
      throw Exception('No sprites found with name "$name" in atlas');
    }
    if (useIndexedSpritesOnly) {
      animationSprites = animationSprites
          .where((s) => s.region.index >= 0)
          .toList();
    }

    return SpriteAnimation.spriteList(
      animationSprites,
      stepTime: stepTime,
      loop: loop,
    );
  }
}
