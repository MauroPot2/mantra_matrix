# Runtime dependencies

Core runtime dependencies remain intentionally small: Firebase Core/Auth/Firestore, Riverpod, Google Sign-In and `file_selector` for user-selected dataset imports.

The import parser itself is implemented in the application and does not require a provider-specific SDK.
