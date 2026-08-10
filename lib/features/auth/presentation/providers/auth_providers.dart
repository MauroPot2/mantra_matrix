import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/core/providers/firebase_providers.dart';
import 'package:mantra_matrix/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:mantra_matrix/features/auth/domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firebaseFirestoreProvider),
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value;
});

final currentUserUidProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.uid;
});
