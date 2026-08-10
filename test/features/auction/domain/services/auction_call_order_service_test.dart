import 'package:flutter_test/flutter_test.dart';
import 'package:mantra_matrix/features/auction/domain/entities/auction_call_order.dart';
import 'package:mantra_matrix/features/auction/domain/services/auction_call_order_service.dart';
import 'package:mantra_matrix/features/player_database/domain/entities/player_entities.dart';

void main() {
  const service = AuctionCallOrderService();
  final players = [
    player('z', 'Zaccagni', MantraRole.w),
    player('a', 'Acerbi', MantraRole.dc),
    player('b', 'Bastoni', MantraRole.dc),
    player('p', 'Provedel', MantraRole.por),
  ];

  test('ordine alfabetico raggruppa per ruolo principale', () {
    final order = service.build(
      players: players,
      mode: AuctionCallOrderMode.alphabeticalByRole,
      seed: 1,
    );

    expect(order, ['p', 'a', 'b', 'z']);
  });

  test('random totale è deterministico con lo stesso seed', () {
    final first = service.build(
      players: players,
      mode: AuctionCallOrderMode.randomAll,
      seed: 42,
    );
    final second = service.build(
      players: players,
      mode: AuctionCallOrderMode.randomAll,
      seed: 42,
    );

    expect(first, second);
    expect(first.toSet(), players.map((item) => item.id).toSet());
  });

  test('random per ruolo mantiene contigui i gruppi Mantra', () {
    final order = service.build(
      players: players,
      mode: AuctionCallOrderMode.randomByRole,
      seed: 7,
    );

    expect(order.first, 'p');
    expect(order.sublist(1, 3).toSet(), {'a', 'b'});
    expect(order.last, 'z');
  });
}

PlayerEntity player(String id, String name, MantraRole role) {
  return PlayerEntity(
    id: id,
    name: name,
    team: 'TEST',
    roles: [role],
    basePrice: 1,
    expectedGoals: 0,
    expectedAssists: 0,
    expectedGoals90: 0,
    expectedAssists90: 0,
    expectedYellowCards: 0,
    historicalMinutes: 0,
  );
}
