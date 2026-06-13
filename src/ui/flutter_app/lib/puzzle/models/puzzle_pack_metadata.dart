// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_pack_metadata.dart

part of 'puzzle_models.dart';

/// Metadata for a puzzle pack/collection
///
/// Provides information about a collection of puzzles, such as
/// official puzzle packs, community-created sets, or thematic collections.
@HiveType(typeId: 38)
class PuzzlePackMetadata {
  const PuzzlePackMetadata({
    required this.id,
    required this.name,
    required this.description,
    this.author,
    this.version,
    this.createdDate,
    this.updatedDate,
    this.tags = const <String>[],
    this.isOfficial = false,
    this.requiredAppVersion,
    this.ruleVariantId = 'standard_9mm',
    this.coverImage,
    this.website,
  });

  /// Create from JSON
  factory PuzzlePackMetadata.fromJson(Map<String, dynamic> json) {
    return PuzzlePackMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      author: json['author'] as String?,
      version: json['version'] as String?,
      createdDate: json['createdDate'] != null
          ? DateTime.parse(json['createdDate'] as String)
          : null,
      updatedDate: json['updatedDate'] != null
          ? DateTime.parse(json['updatedDate'] as String)
          : null,
      tags:
          (json['tags'] as List<dynamic>?)
              ?.map((dynamic e) => e as String)
              .toList() ??
          const <String>[],
      isOfficial: json['isOfficial'] as bool? ?? false,
      requiredAppVersion: json['requiredAppVersion'] as String?,
      ruleVariantId: json['ruleVariantId'] as String? ?? 'standard_9mm',
      coverImage: json['coverImage'] as String?,
      website: json['website'] as String?,
    );
  }

  /// Unique identifier for the puzzle pack
  @HiveField(0)
  final String id;

  /// Display name of the puzzle pack
  /// Example: "Beginner Tactics", "Advanced Endgames"
  @HiveField(1)
  final String name;

  /// Description of the puzzle pack's content and purpose
  @HiveField(2)
  final String description;

  /// Author/creator of the puzzle pack
  @HiveField(3)
  final String? author;

  /// Version string (e.g., "1.2.0")
  /// Useful for tracking pack updates
  @HiveField(4)
  final String? version;

  /// When the pack was created
  @HiveField(5)
  final DateTime? createdDate;

  /// When the pack was last updated
  @HiveField(6)
  final DateTime? updatedDate;

  /// Tags for categorization and filtering
  /// Example: ["beginner", "tactics", "mill-formation"]
  @HiveField(7)
  final List<String> tags;

  /// Whether this is an official Sanmill puzzle pack
  @HiveField(8)
  final bool isOfficial;

  /// Minimum app version required to use this pack
  /// Format: "7.1.0" (semantic versioning)
  @HiveField(9)
  final String? requiredAppVersion;

  /// Rule variant this pack is designed for
  @HiveField(10)
  final String ruleVariantId;

  /// Optional cover image path or URL
  @HiveField(11)
  final String? coverImage;

  /// Optional website or source URL
  @HiveField(12)
  final String? website;

  /// Create a copy with updated fields
  PuzzlePackMetadata copyWith({
    String? id,
    String? name,
    String? description,
    String? author,
    String? version,
    DateTime? createdDate,
    DateTime? updatedDate,
    List<String>? tags,
    bool? isOfficial,
    String? requiredAppVersion,
    String? ruleVariantId,
    String? coverImage,
    String? website,
  }) {
    return PuzzlePackMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      version: version ?? this.version,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
      tags: tags ?? this.tags,
      isOfficial: isOfficial ?? this.isOfficial,
      requiredAppVersion: requiredAppVersion ?? this.requiredAppVersion,
      ruleVariantId: ruleVariantId ?? this.ruleVariantId,
      coverImage: coverImage ?? this.coverImage,
      website: website ?? this.website,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      if (author != null) 'author': author,
      if (version != null) 'version': version,
      if (createdDate != null) 'createdDate': createdDate!.toIso8601String(),
      if (updatedDate != null) 'updatedDate': updatedDate!.toIso8601String(),
      if (tags.isNotEmpty) 'tags': tags,
      'isOfficial': isOfficial,
      if (requiredAppVersion != null) 'requiredAppVersion': requiredAppVersion,
      'ruleVariantId': ruleVariantId,
      if (coverImage != null) 'coverImage': coverImage,
      if (website != null) 'website': website,
    };
  }

  @override
  String toString() => 'PuzzlePackMetadata($name v$version)';
}
