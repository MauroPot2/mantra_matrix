import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mantra_matrix/features/auth/domain/repositories/auth_repository.dart';
import 'package:mantra_matrix/features/auth/presentation/providers/auth_providers.dart';

enum AuthOperation {
  googleSignIn,
  emailSignIn,
  registration,
  passwordReset,
  signOut,
}

class AuthUiState {
  final AuthOperation? activeOperation;
  final String? errorMessage;
  final String? successMessage;

  const AuthUiState({
    this.activeOperation,
    this.errorMessage,
    this.successMessage,
  });

  bool get isLoading => activeOperation != null;

  bool isRunning(AuthOperation operation) => activeOperation == operation;

  AuthUiState copyWith({
    Object? activeOperation = _unset,
    Object? errorMessage = _unset,
    Object? successMessage = _unset,
  }) {
    return AuthUiState(
      activeOperation: identical(activeOperation, _unset)
          ? this.activeOperation
          : activeOperation as AuthOperation?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      successMessage: identical(successMessage, _unset)
          ? this.successMessage
          : successMessage as String?,
    );
  }
}

const _unset = Object();

final authControllerProvider =
    NotifierProvider<AuthController, AuthUiState>(AuthController.new);

class AuthController extends Notifier<AuthUiState> {
  @override
  AuthUiState build() => const AuthUiState();

  Future<void> signInWithGoogle() async {
    if (state.isLoading) return;

    state = const AuthUiState(activeOperation: AuthOperation.googleSignIn);

    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      state = const AuthUiState();
    } on AuthCancelledException {
      state = const AuthUiState();
    } on AuthOperationException catch (error) {
      state = AuthUiState(errorMessage: error.message);
    } catch (error) {
      state = AuthUiState(errorMessage: 'Accesso non riuscito: $error');
    }
  }

  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (state.isLoading) return;

    state = const AuthUiState(activeOperation: AuthOperation.emailSignIn);

    try {
      await ref.read(authRepositoryProvider).signInWithEmailAndPassword(
            email: email,
            password: password,
          );
      state = const AuthUiState();
    } on AuthOperationException catch (error) {
      state = AuthUiState(errorMessage: error.message);
    } catch (error) {
      state = AuthUiState(errorMessage: 'Accesso non riuscito: $error');
    }
  }

  Future<void> registerWithEmailAndPassword({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (state.isLoading) return;

    state = const AuthUiState(activeOperation: AuthOperation.registration);

    try {
      await ref.read(authRepositoryProvider).registerWithEmailAndPassword(
            displayName: displayName,
            email: email,
            password: password,
          );
      state = const AuthUiState();
    } on AuthOperationException catch (error) {
      state = AuthUiState(errorMessage: error.message);
    } catch (error) {
      state = AuthUiState(errorMessage: 'Registrazione non riuscita: $error');
    }
  }

  Future<bool> sendPasswordResetEmail({required String email}) async {
    if (state.isLoading) return false;

    state = const AuthUiState(activeOperation: AuthOperation.passwordReset);

    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(email: email);
      state = const AuthUiState(
        successMessage:
            'Se l’indirizzo è registrato, riceverai un’email per reimpostare la password.',
      );
      return true;
    } on AuthOperationException catch (error) {
      state = AuthUiState(errorMessage: error.message);
      return false;
    } catch (error) {
      state = AuthUiState(
        errorMessage: 'Recupero password non riuscito: $error',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    if (state.isLoading) return;

    state = const AuthUiState(activeOperation: AuthOperation.signOut);
    try {
      await ref.read(authRepositoryProvider).signOut();
      state = const AuthUiState();
    } on AuthOperationException catch (error) {
      state = AuthUiState(errorMessage: error.message);
    } catch (error) {
      state = AuthUiState(errorMessage: 'Logout non riuscito: $error');
    }
  }

  void clearFeedback() {
    if (state.errorMessage != null || state.successMessage != null) {
      state = state.copyWith(
        errorMessage: null,
        successMessage: null,
      );
    }
  }
}
