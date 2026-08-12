/// Ruoli tattici attualmente supportati dal motore d'asta.
///
/// Il nome del tipo resta invariato durante la migrazione per non rompere il
/// motore esistente; in una fase successiva verrà reso completamente neutrale.
enum MantraRole { por, dc, b, dd, ds, e, m, c, t, w, a, pc }

/// Provenienza dei dati del calciatore.
///
/// Serve a distinguere chiaramente dati prodotti da Matrix, dati importati
/// dall'utente e record provenienti dal vecchio catalogo durante la transizione.
enum PlayerDataOrigin { matrix, userImport, legacyCatalog }

/// Stato del calciatore all'interno della sessione d'asta.
enum DraftStatus { available, drafted, unavailable }

const _unset = Object();

class PlayerEntity {
  final String id;
  final String name;
  final String team;
  final List<MantraRole> roles;
  final int basePrice;

  /// Traccia la provenienza del record senza legare il dominio a un provider.
  final PlayerDataOrigin dataOrigin;

  /// Etichetta opzionale definita da Matrix o dall'utente, mai necessaria al
  /// funzionamento del motore.
  final String? sourceLabel;

  final double expectedGoals;
  final double expectedAssists;
  final double expectedGoals90;
  final double expectedAssists90;
  final double expectedYellowCards;
  final int historicalMinutes;

  final double expectedGoalsConceded;
  final double expectedCleanSheets;

  final bool isPenaltyTaker;
  final bool isFreeKickTaker;

  final bool isInjured;
  final bool isSuspended;

  final double expectedPoints;
  final double polyvalenceMultiplier;
  final double vorp;

  final DraftStatus status;
  final String? draftedByTeamId;
  final int? purchasePrice;

  const PlayerEntity({
    required this.id,
    required this.name,
    required this.team,
    required this.roles,
    required this.basePrice,
    this.dataOrigin = PlayerDataOrigin.matrix,
    this.sourceLabel,
    required this.expectedGoals,
    required this.expectedAssists,
    required this.expectedGoals90,
    required this.expectedAssists90,
    required this.expectedYellowCards,
    required this.historicalMinutes,
    this.expectedGoalsConceded = 0.0,
    this.expectedCleanSheets = 0.0,
    this.isPenaltyTaker = false,
    this.isFreeKickTaker = false,
    this.isInjured = false,
    this.isSuspended = false,
    this.expectedPoints = 0.0,
    this.polyvalenceMultiplier = 1.0,
    this.vorp = 0.0,
    this.status = DraftStatus.available,
    this.draftedByTeamId,
    this.purchasePrice,
  }) : assert(roles.length > 0, 'Un giocatore deve avere almeno un ruolo'),
       assert(basePrice >= 0),
       assert(historicalMinutes >= 0);

  /// [draftedByTeamId], [purchasePrice] e [sourceLabel] usano un sentinel per
  /// consentire anche l'azzeramento esplicito dei valori nullable.
  PlayerEntity copyWith({
    String? id,
    String? name,
    String? team,
    List<MantraRole>? roles,
    int? basePrice,
    PlayerDataOrigin? dataOrigin,
    Object? sourceLabel = _unset,
    double? expectedGoals,
    double? expectedAssists,
    double? expectedGoals90,
    double? expectedAssists90,
    double? expectedYellowCards,
    int? historicalMinutes,
    double? expectedGoalsConceded,
    double? expectedCleanSheets,
    bool? isPenaltyTaker,
    bool? isFreeKickTaker,
    bool? isInjured,
    bool? isSuspended,
    double? expectedPoints,
    double? polyvalenceMultiplier,
    double? vorp,
    DraftStatus? status,
    Object? draftedByTeamId = _unset,
    Object? purchasePrice = _unset,
  }) {
    return PlayerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      team: team ?? this.team,
      roles: roles ?? this.roles,
      basePrice: basePrice ?? this.basePrice,
      dataOrigin: dataOrigin ?? this.dataOrigin,
      sourceLabel: identical(sourceLabel, _unset)
          ? this.sourceLabel
          : sourceLabel as String?,
      expectedGoals: expectedGoals ?? this.expectedGoals,
      expectedAssists: expectedAssists ?? this.expectedAssists,
      expectedGoals90: expectedGoals90 ?? this.expectedGoals90,
      expectedAssists90: expectedAssists90 ?? this.expectedAssists90,
      expectedYellowCards: expectedYellowCards ?? this.expectedYellowCards,
      historicalMinutes: historicalMinutes ?? this.historicalMinutes,
      expectedGoalsConceded:
          expectedGoalsConceded ?? this.expectedGoalsConceded,
      expectedCleanSheets: expectedCleanSheets ?? this.expectedCleanSheets,
      isPenaltyTaker: isPenaltyTaker ?? this.isPenaltyTaker,
      isFreeKickTaker: isFreeKickTaker ?? this.isFreeKickTaker,
      isInjured: isInjured ?? this.isInjured,
      isSuspended: isSuspended ?? this.isSuspended,
      expectedPoints: expectedPoints ?? this.expectedPoints,
      polyvalenceMultiplier:
          polyvalenceMultiplier ?? this.polyvalenceMultiplier,
      vorp: vorp ?? this.vorp,
      status: status ?? this.status,
      draftedByTeamId: identical(draftedByTeamId, _unset)
          ? this.draftedByTeamId
          : draftedByTeamId as String?,
      purchasePrice: identical(purchasePrice, _unset)
          ? this.purchasePrice
          : purchasePrice as int?,
    );
  }
}
