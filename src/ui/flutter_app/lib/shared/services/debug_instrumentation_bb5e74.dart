// #region agent log
// Temporary debug-session instrumentation (session bb5e74).
// Platform-specific implementation is selected at compile time.

export 'debug_instrumentation_bb5e74_stub.dart'
    if (dart.library.io) 'debug_instrumentation_bb5e74_io.dart';

// #endregion
