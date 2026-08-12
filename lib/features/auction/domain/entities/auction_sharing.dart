enum AuctionJoinRequestStatus { pending, approved, rejected }

class AuctionShareInvite {
  final String sessionId;
  final String ownerUid;
  final String token;
  final String entryCode;

  const AuctionShareInvite({
    required this.sessionId,
    required this.ownerUid,
    required this.token,
    required this.entryCode,
  });

  String get formattedEntryCode {
    if (entryCode.length != 8) return entryCode;
    return '${entryCode.substring(0, 4)}-${entryCode.substring(4)}';
  }

  Uri toUri() {
    return Uri(
      scheme: 'astamatrix',
      host: 'join',
      queryParameters: {
        'session': sessionId,
        'owner': ownerUid,
        'token': token,
        'code': entryCode,
      },
    );
  }

  static String normalizeEntryCode(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static AuctionShareInvite? tryParse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'astamatrix' || uri.host != 'join') {
      return null;
    }

    final sessionId = uri.queryParameters['session']?.trim();
    final ownerUid = uri.queryParameters['owner']?.trim();
    final token = uri.queryParameters['token']?.trim();
    final entryCode = normalizeEntryCode(uri.queryParameters['code'] ?? '');
    if (sessionId == null ||
        sessionId.isEmpty ||
        ownerUid == null ||
        ownerUid.isEmpty ||
        token == null ||
        token.length < 32 ||
        entryCode.length != 8) {
      return null;
    }

    return AuctionShareInvite(
      sessionId: sessionId,
      ownerUid: ownerUid,
      token: token,
      entryCode: entryCode,
    );
  }
}

class AuctionJoinRequest {
  final String id;
  final String sessionId;
  final String ownerUid;
  final String requesterUid;
  final String inviteToken;
  final AuctionJoinRequestStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? assignedTeamId;

  const AuctionJoinRequest({
    required this.id,
    required this.sessionId,
    required this.ownerUid,
    required this.requesterUid,
    required this.inviteToken,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.assignedTeamId,
  });

  bool get isPending => status == AuctionJoinRequestStatus.pending;
  bool get isApproved => status == AuctionJoinRequestStatus.approved;
}
