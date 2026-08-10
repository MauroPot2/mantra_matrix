class PlayerCatalogMetadata {
  final String version;
  final int activePlayerCount;
  final String sourceName;
  final DateTime? updatedAt;
  final String? updatedByUid;

  const PlayerCatalogMetadata({
    required this.version,
    required this.activePlayerCount,
    required this.sourceName,
    this.updatedAt,
    this.updatedByUid,
  });
}

class PlayerCatalogUpdateResult {
  final String version;
  final int importedCount;
  final int deactivatedCount;

  const PlayerCatalogUpdateResult({
    required this.version,
    required this.importedCount,
    required this.deactivatedCount,
  });
}
