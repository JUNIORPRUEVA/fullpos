import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/color_utils.dart';
import '../../models/product_model.dart';

/// Miniatura reusable para productos (imagen o placeholder por color).
class ProductThumbnail extends StatelessWidget {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final normalizedType = placeholderType.toLowerCase();
    final prefersImage = normalizedType != 'color';
    final normalizedImagePath = imagePath?.trim() ?? '';
    final normalizedImageUrl = imageUrl?.trim() ?? '';
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

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: showBorder
            ? Border.all(color: Colors.grey.shade300, width: 1)
            : null,
        color: shouldShowImage ? Colors.grey.shade100 : bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white24,
            blurRadius: 6,
            offset: const Offset(-1, -1),
            spreadRadius: -2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shouldShowImage)
            _buildImage(normalizedImagePath, normalizedImageUrl)
          else
            _buildPlaceholder(bgColor),
          if (overlay != null) overlay!,
        ],
      ),
    );
  }

  Widget _buildImage(String path, String url) {
    if (path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(
          ColorUtils.colorFromHex(
            placeholderColorHex,
            fallback: const Color(0xFF546E7A),
          ),
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildPlaceholder(
          ColorUtils.colorFromHex(
            placeholderColorHex,
            fallback: const Color(0xFF546E7A),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(
        ColorUtils.colorFromHex(
          placeholderColorHex,
          fallback: const Color(0xFF546E7A),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(Color color) {
    final initials = _getInitials(name);
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _getInitials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
