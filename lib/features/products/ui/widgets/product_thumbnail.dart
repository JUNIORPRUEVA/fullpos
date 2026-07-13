import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/color_utils.dart';
import '../../models/product_model.dart';

/// Miniatura reusable para productos (imagen o placeholder limpio con icono).
class ProductThumbnail extends StatelessWidget {
  static const Set<String> _blockedRemoteImageUrls = {
    'https://images.unsplash.com/photo-1454991727061-2868c0807f7f?auto=format&fit=crop&w=800&q=80&sig=7',
  };

  final String name;
  final String? imagePath;
  final String? imageUrl;
  final String? placeholderColorHex;
  final String placeholderType;
  final int? categoryId;
  final double size;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final bool showBorder;
  final bool showShadow;
  final Color? placeholderBackgroundColor;
  final Widget? overlay;

  const ProductThumbnail({
    super.key,
    required this.name,
    this.imagePath,
    this.imageUrl,
    this.placeholderColorHex,
    this.placeholderType = 'image',
    this.categoryId,
    this.size = 64,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.showBorder = true,
    this.showShadow = true,
    this.placeholderBackgroundColor,
    this.overlay,
  });

  factory ProductThumbnail.fromProduct(
    ProductModel product, {
    double size = 64,
    double? width,
    double? height,
    BorderRadius? borderRadius,
    String? imagePathOverride,
    String? placeholderColorOverride,
    String? placeholderTypeOverride,
    bool showBorder = true,
    bool showShadow = true,
    Color? placeholderBackgroundColor,
  }) {
    return ProductThumbnail(
      name: product.name,
      imagePath: imagePathOverride ?? product.imagePath,
      imageUrl: product.imageUrl,
      placeholderColorHex:
          placeholderColorOverride ?? product.placeholderColorHex,
      placeholderType: placeholderTypeOverride ?? product.placeholderType,
      categoryId: product.categoryId,
      size: size,
      width: width,
      height: height,
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(8)),
      showBorder: showBorder,
      showShadow: showShadow,
      placeholderBackgroundColor: placeholderBackgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final normalizedType = placeholderType.toLowerCase();
    final prefersImage = normalizedType != 'color';
    final normalizedImagePath = imagePath?.trim() ?? '';
    final normalizedImageUrl = _normalizeRemoteImageUrl(imageUrl);
    final hasLocalImage =
        prefersImage &&
        normalizedImagePath.isNotEmpty &&
        File(normalizedImagePath).existsSync();
    final hasRemoteImage = prefersImage && normalizedImageUrl.isNotEmpty;
    final shouldShowImage = hasLocalImage || hasRemoteImage;
    final effectiveHex = (placeholderColorHex?.trim().isNotEmpty ?? false)
        ? placeholderColorHex!.trim()
        : ColorUtils.generateDeterministicColorHex(
            name.trim().isEmpty ? 'PRODUCT' : name,
            categoryId: categoryId,
          );
    final bgColor = ColorUtils.colorFromHex(
      effectiveHex,
      fallback: const Color(0xFF546E7A),
    );
    final placeholderSurface = placeholderBackgroundColor ?? Colors.white;

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: showBorder
            ? Border.all(color: const Color(0xFFDDE6F0), width: 1)
            : null,
        color: shouldShowImage ? const Color(0xFFF8FAFC) : Colors.white,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.055),
                  blurRadius: 8,
                  spreadRadius: -3,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shouldShowImage)
            _buildImage(normalizedImagePath, normalizedImageUrl)
          else
            _buildPlaceholder(bgColor, placeholderSurface),
          if (overlay != null) ...<Widget>[overlay!],
        ],
      ),
    );
  }

  Widget _buildImage(String path, String url) {
    if (path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(
          ColorUtils.colorFromHex(
            placeholderColorHex,
            fallback: const Color(0xFF546E7A),
          ),
          placeholderBackgroundColor ?? Colors.transparent,
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildPlaceholder(
          ColorUtils.colorFromHex(
            placeholderColorHex,
            fallback: const Color(0xFF546E7A),
          ),
          placeholderBackgroundColor ?? Colors.transparent,
        );
      },
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(
        ColorUtils.colorFromHex(
          placeholderColorHex,
          fallback: const Color(0xFF546E7A),
        ),
        placeholderBackgroundColor ?? Colors.transparent,
      ),
    );
  }

  String _normalizeRemoteImageUrl(String? rawUrl) {
    final normalized = rawUrl?.trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }
    if (_blockedRemoteImageUrls.contains(normalized)) {
      return '';
    }
    return normalized;
  }

  Widget _buildPlaceholder(Color color, Color surface) {
    final effectiveSize = width ?? size;
    final iconSize = (effectiveSize * 0.48).clamp(18.0, 64.0);
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Icon(
          Icons.sell_outlined,
          color: const Color(0xFFCBD5E1),
          size: iconSize,
        ),
      ),
    );
  }
}
