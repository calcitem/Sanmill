// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

const Set<String> _pacificCenteredLanguageCodes = <String>{
  'bn',
  'bo',
  'gu',
  'hi',
  'id',
  'ja',
  'km',
  'kn',
  'ko',
  'ms',
  'my',
  'si',
  'ta',
  'te',
  'th',
  'ur',
  'uz',
  'vi',
  'zh',
};

/// Returns the central longitude used for the locale's world-map convention.
double millVariantMapCenterLongitudeForLocale(Locale locale) {
  final String languageCode = locale.languageCode.toLowerCase();
  return _pacificCenteredLanguageCodes.contains(languageCode) ? 150 : 0;
}

/// Returns the bundled popularity mask for a stable Mill variant identifier.
String millVariantPopularityMaskAssetById(String variantId) {
  return switch (variantId) {
    'standard_9mm' => 'assets/maps/mill_variant_standard_9mm.png',
    'twelve_mens_morris' => 'assets/maps/mill_variant_twelve_mens_morris.png',
    'morabaraba' => 'assets/maps/mill_variant_morabaraba.png',
    'dooz' => 'assets/maps/mill_variant_dooz.png',
    'lasker_morris' => 'assets/maps/mill_variant_lasker_morris.png',
    'russian_mill' => 'assets/maps/mill_variant_russian_mill.png',
    'cham_gonu' => 'assets/maps/mill_variant_cham_gonu.png',
    'zhi_qi' => 'assets/maps/mill_variant_zhi_qi.png',
    'cheng_san_qi' => 'assets/maps/mill_variant_cheng_san_qi.png',
    'da_san_qi' => 'assets/maps/mill_variant_da_san_qi.png',
    'mul_mulan' => 'assets/maps/mill_variant_mul_mulan.png',
    'nerenchi' => 'assets/maps/mill_variant_nerenchi.png',
    'el_filja' => 'assets/maps/mill_variant_el_filja.png',
    _ => throw StateError('Unsupported Mill variant: $variantId'),
  };
}

/// An offline world map showing the broad regions where a variant is popular.
class MillVariantPopularityMap extends StatelessWidget {
  const MillVariantPopularityMap({
    super.key,
    required this.variantId,
    required this.semanticsLabel,
  });

  static const String _landAsset = 'assets/maps/world_land.png';
  static const double _aspectRatio = 2;
  static const double _maximumWidth = 640;

  final String variantId;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double centerLongitude = millVariantMapCenterLongitudeForLocale(
      Localizations.localeOf(context),
    );
    final String maskAsset = millVariantPopularityMaskAssetById(variantId);

    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Directionality(
          key: const Key('mill_variant_popularity_geography'),
          textDirection: TextDirection.ltr,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maximumWidth),
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints bounds) {
                        final double mapWidth = bounds.maxWidth;
                        final double mapHeight = bounds.maxHeight;
                        final double sourceLeft =
                            -centerLongitude / 360 * mapWidth;

                        return Stack(
                          clipBehavior: Clip.hardEdge,
                          children: <Widget>[
                            for (int tile = -1; tile <= 1; tile++)
                              _MapTile(
                                key: tile == 0
                                    ? const Key(
                                        'mill_variant_popularity_land_center',
                                      )
                                    : null,
                                asset: _landAsset,
                                left: sourceLeft + tile * mapWidth,
                                width: mapWidth,
                                height: mapHeight,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.34,
                                ),
                              ),
                            for (int tile = -1; tile <= 1; tile++)
                              _MapTile(
                                key: tile == 0
                                    ? const Key(
                                        'mill_variant_popularity_mask_center',
                                      )
                                    : null,
                                asset: maskAsset,
                                left: sourceLeft + tile * mapWidth,
                                width: mapWidth,
                                height: mapHeight,
                                color: colorScheme.primary.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapTile extends StatelessWidget {
  const _MapTile({
    super.key,
    required this.asset,
    required this.left,
    required this.width,
    required this.height,
    required this.color,
  });

  final String asset;
  final double left;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: 0,
      width: width,
      height: height,
      child: Image.asset(
        asset,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        color: color,
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }
}
