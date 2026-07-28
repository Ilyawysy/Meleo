import 'dart:async';
import 'dart:developer' show log;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/analytics_service.dart';
import 'core/env.dart';
import 'core/preferences/onboarding_preferences.dart';
import 'core/providers/inner_scope.dart';
import 'core/providers/session_scope.dart';
import 'core/providers/theme_provider.dart';
import 'core/sentry_config.dart';
import 'core/sync/first_sync_settled_provider.dart';
import 'core/sync/sync_orchestrator.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/data/token_manager.dart';
import 'features/auth/ui/auth_loading_screen.dart';
import 'features/auth/ui/auth_screen.dart';
import 'features/onboarding/ui/onboarding_screen.dart';
import 'features/shell/ui/shell_scaffold.dart';

Future<void> _logEnvironment() async {
  // Visible only in console logs; do not use in production logging
  log('ENV: API_BASE_URL = ${Env.apiBase}');
  log('ENV: AGENT_URL = ${Env.apiBase}/api/v1/agent');
  log('ENV: SUPABASE_URL_SET = ${Env.supabaseUrl.isNotEmpty}');
  final isAuth = await TokenManager.isAuthenticated;
  log('AUTH: TOKEN_SET = $isAuth');
  final token = await TokenManager.token;
  if (token != null) {
    log('AUTH: TOKEN_LENGTH = ${token.length}');
    final userId = await TokenManager.userId;
    log('AUTH: USER_ID = $userId');
  }
}

Future<void> main() async {
  // Initialize Sentry if enabled (release mode only)
  if (SentryConfig.shouldEnable()) {
    await SentryFlutter.init(
      (options) => SentryConfig.configureOptions(options),
      appRunner: () => _initializeAndRunApp(),
    );
  } else {
    await _initializeAndRunApp();
  }
}

Future<void> _initializeAndRunApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    if (Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty)
      Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
        authOptions: FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
      )
    else
      Future(() => log('SUPABASE: Missing SUPABASE_URL or SUPABASE_ANON_KEY')),
    if (AnalyticsService.isEnabled) AnalyticsService().initialize(),
  ]);

  // Wire the token refresh callback to break the circular dependency between
  // TokenManager and AuthService.
  TokenManager.onNeedRefresh = () => AuthService().refreshToken();

  // Log current environment values for diagnostics
  await _logEnvironment();

  runApp(const ProviderScope(child: InnerScope(child: MyApp())));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeProvider);
    final themeMode = themeAsync.valueOrNull ?? ThemeMode.system;
    return MaterialApp(
      title: 'Focus App',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      themeMode: themeMode,
      // Screen tracking handled manually in ShellScaffold for tab navigation
      // No NavigatorObserver needed - prevents tracking dialogs and Material routes
      navigatorObservers: const [],
      home: const AuthGate(),
      routes: {
        '/home': (context) => const ShellScaffold(),
        '/login': (context) => const AuthScreen(),
      },
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

enum _OnboardingState { unknown, completed, notCompleted }

class _AuthGateState extends ConsumerState<AuthGate> {
  final AuthService _authService = AuthService();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Uri>? _linkSubscription;
  bool _isReady = false;
  bool _isAuthenticated = false;
  _OnboardingState _onboardingState = _OnboardingState.unknown;
  VoidCallback? _onboardingCallback;
  VoidCallback? _firstSyncCallback;
  Timer? _firstSyncSafetyTimer;

  /// Redirect URL for Supabase OAuth (e.g. com.meleo.mobile.supabase://oauthredirect)
  static Uri? get _supabaseRedirectUri {
    try {
      return Uri.parse(Env.supabaseRedirectUrl);
    } catch (_) {
      return null;
    }
  }

  bool _isOAuthCallbackUri(Uri uri) {
    final redirect = _supabaseRedirectUri;
    if (redirect == null) return false;
    return uri.scheme == redirect.scheme && uri.host == redirect.host;
  }

  /// [isInitial] true = cold start, мы единственные обрабатываем ссылку.
  /// false = ссылка пришла по stream; Supabase SDK тоже обрабатывает — не вызываем getSessionFromUrl,
  /// иначе код обменивается дважды и второй вызов даёт flow_state_not_found.
  Future<void> _handleOAuthCallbackUri(
    Uri? uri, {
    required bool isInitial,
  }) async {
    if (uri == null || !_isOAuthCallbackUri(uri)) return;
    if (Env.supabaseUrl.isEmpty || Env.supabaseAnonKey.isEmpty) return;
    if (isInitial) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
        log('AUTH: OAuth callback processed from initial link');
      } catch (e, st) {
        log('AUTH: getSessionFromUrl failed: $e', stackTrace: st);
      }
    } else {
      // Stream event: SDK должен обработать сам, но добавляем fallback
      // Если через 3 секунды session == null, пробуем сами
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          log('AUTH: SDK did not process OAuth callback, trying fallback');
          try {
            await Supabase.instance.client.auth.getSessionFromUrl(uri);
            log('AUTH: OAuth callback processed by fallback');
            if (mounted) {
              final newSession = Supabase.instance.client.auth.currentSession;
              if (newSession != null) {
                await _authService.persistSession(newSession, trackLogin: true);
                final userId = newSession.user.id;
                await SentryConfig.setUser(userId);
                SentryConfig.addBreadcrumb(
                  message: 'OAuth callback processed (fallback)',
                  category: 'auth',
                  level: SentryLevel.info,
                  data: {'user_id': userId},
                );
                // Update Riverpod session state
                ref
                    .read(sessionScopeProvider.notifier)
                    .updateAuth(isAuthenticated: true, userId: userId);
                setState(() {
                  _isAuthenticated = true;
                });
              }
            }
          } catch (e, st) {
            log('AUTH: fallback getSessionFromUrl failed: $e', stackTrace: st);
          }
        }
      }
    }
  }

  /// Process initial deep link (e.g. OAuth callback after cold start) before showing UI.
  Future<void> _processInitialLinkAndListen() async {
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null && _isOAuthCallbackUri(initialUri)) {
      log('AUTH: Got initial link (OAuth callback)');
      await _handleOAuthCallbackUri(initialUri, isInitial: true);
      if (mounted) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          await _authService.persistSession(session, trackLogin: true);
          final userId = session.user.id;
          await SentryConfig.setUser(userId);
          SentryConfig.addBreadcrumb(
            message: 'OAuth callback processed (initial link)',
            category: 'auth',
            level: SentryLevel.info,
            data: {'user_id': userId},
          );
          // Update Riverpod session state
          ref
              .read(sessionScopeProvider.notifier)
              .updateAuth(isAuthenticated: true, userId: userId);
          _isAuthenticated = true;
        }
      }
    }
    if (mounted) {
      _linkSubscription = appLinks.uriLinkStream.listen(
        (uri) => _handleOAuthCallbackUri(uri, isInitial: false),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    if (Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await _authService.persistSession(session);
        _isAuthenticated = true;
        // Set Sentry user context
        final userId = session.user.id;
        await SentryConfig.setUser(userId);
        SentryConfig.addBreadcrumb(
          message: 'User authenticated on app start',
          category: 'auth',
          level: SentryLevel.info,
          data: {'user_id': userId},
        );
        // Update Riverpod session state
        ref
            .read(sessionScopeProvider.notifier)
            .updateAuth(isAuthenticated: true, userId: userId);
      } else {
        await TokenManager.clearToken();
        await SentryConfig.clearUser();
        _isAuthenticated = false;
        // Update Riverpod session state
        ref
            .read(sessionScopeProvider.notifier)
            .updateAuth(isAuthenticated: false, userId: null);
      }

      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
        data,
      ) async {
        final event = data.event;
        log('AUTH: onAuthStateChange event=$event mounted=$mounted');
        if (!mounted) {
          log('AUTH: onAuthStateChange early return (!mounted)');
          return;
        }
        final session = data.session;
        if (event == AuthChangeEvent.signedOut) {
          log(
            'AUTH: signedOut -> clearing token, setState(_isAuthenticated=false)',
          );
          await TokenManager.clearToken();
          await SentryConfig.clearUser();
          SentryConfig.addBreadcrumb(
            message: 'User signed out',
            category: 'auth',
            level: SentryLevel.info,
            data: {'event': event.toString()},
          );
          // Cancel safety timer and clear callbacks so next login starts fresh.
          _firstSyncSafetyTimer?.cancel();
          _firstSyncSafetyTimer = null;
          if (SyncOrchestrator.instance.onFirstSyncSettled ==
              _firstSyncCallback) {
            SyncOrchestrator.instance.onFirstSyncSettled = null;
          }
          _firstSyncCallback = null;
          if (SyncOrchestrator.instance.onOnboardingCompleted ==
              _onboardingCallback) {
            SyncOrchestrator.instance.onOnboardingCompleted = null;
          }
          _onboardingCallback = null;
          _onboardingState = _OnboardingState.unknown;
          ref.read(firstSyncSettledProvider.notifier).reset();
          // Update Riverpod session state
          ref
              .read(sessionScopeProvider.notifier)
              .updateAuth(isAuthenticated: false, userId: null);
          if (mounted) {
            setState(() {
              _isAuthenticated = false;
            });
            log('AUTH: setState done, AuthGate will rebuild');
            // Track return to auth screen
            AnalyticsService().trackScreen('Auth');
          }
          return;
        }
        if ((event == AuthChangeEvent.signedIn ||
                event == AuthChangeEvent.tokenRefreshed) &&
            session != null) {
          // Track login only for new sign-ins, not token refreshes
          final isNewLogin = event == AuthChangeEvent.signedIn;
          await _authService.persistSession(session, trackLogin: isNewLogin);
          final userId = session.user.id;
          await SentryConfig.setUser(userId);
          SentryConfig.addBreadcrumb(
            message: event == AuthChangeEvent.signedIn
                ? 'User signed in'
                : 'Token refreshed',
            category: 'auth',
            level: SentryLevel.info,
            data: {'event': event.toString(), 'user_id': userId},
          );
          // Update Riverpod session state
          ref
              .read(sessionScopeProvider.notifier)
              .updateAuth(isAuthenticated: true, userId: userId);
          if (isNewLogin) {
            await _resolveOnboardingState(userId);
          }
          if (mounted) {
            setState(() {
              _isAuthenticated = true;
            });
          }
        }
      });
    } else {
      _isAuthenticated = await TokenManager.isAuthenticated;
      if (_isAuthenticated) {
        final userId = await TokenManager.userId;
        // Update Riverpod session state
        ref
            .read(sessionScopeProvider.notifier)
            .updateAuth(isAuthenticated: true, userId: userId);
      } else {
        // Update Riverpod session state
        ref
            .read(sessionScopeProvider.notifier)
            .updateAuth(isAuthenticated: false, userId: null);
      }
    }

    if (mounted &&
        Env.supabaseUrl.isNotEmpty &&
        Env.supabaseAnonKey.isNotEmpty) {
      await _processInitialLinkAndListen();
    }

    if (mounted && _isAuthenticated) {
      final userId =
          Supabase.instance.client.auth.currentSession?.user.id ??
          await TokenManager.userId;
      if (userId != null) {
        await _resolveOnboardingState(userId);
      } else {
        _onboardingState = _OnboardingState.completed;
      }
    } else if (!_isAuthenticated) {
      _onboardingState = _OnboardingState.completed;
    }

    if (mounted) {
      setState(() {
        _isReady = true;
      });
    }
  }

  /// Determines onboarding state for [userId]:
  /// - Local cache true → completed immediately (no network wait)
  /// - Local cache false → unknown (wait for sync to resolve)
  Future<void> _resolveOnboardingState(String userId) async {
    final cachedDone = await OnboardingPreferences.isCompletedForUser(userId);
    if (cachedDone) {
      _onboardingState = _OnboardingState.completed;
      return;
    }
    // Not cached as done — wait for sync to confirm. Wire up the callback.
    _onboardingState = _OnboardingState.unknown;
    // Clear previous onboarding callback if it's still ours (guard against user switch).
    if (_onboardingCallback != null &&
        SyncOrchestrator.instance.onOnboardingCompleted ==
            _onboardingCallback) {
      SyncOrchestrator.instance.onOnboardingCompleted = null;
    }
    _onboardingCallback = () {
      if (mounted) {
        setState(() {
          _onboardingState = _OnboardingState.completed;
        });
      }
    };
    SyncOrchestrator.instance.onOnboardingCompleted = _onboardingCallback;

    // Resolve notCompleted only after sync returns an authoritative false.
    if (_firstSyncCallback != null &&
        SyncOrchestrator.instance.onFirstSyncSettled == _firstSyncCallback) {
      SyncOrchestrator.instance.onFirstSyncSettled = null;
    }
    _firstSyncCallback = () {
      if (mounted) {
        ref.read(firstSyncSettledProvider.notifier).markSettled();
        if (_onboardingState == _OnboardingState.unknown) {
          setState(() {
            _onboardingState = _OnboardingState.notCompleted;
          });
        }
      }
    };
    SyncOrchestrator.instance.onFirstSyncSettled = _firstSyncCallback;

    // Safety-net: request another attempt if the authoritative state is still
    // unavailable after 30 seconds. Network/server failures keep the UI unknown.
    _firstSyncSafetyTimer?.cancel();
    _firstSyncSafetyTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _onboardingState == _OnboardingState.unknown) {
        SyncOrchestrator.instance.syncNow();
      }
    });

    // Bootstrap sync immediately so onFirstSyncSettled fires as soon as the
    // first pull completes — without waiting for ShellScaffold to mount.
    // startAll() is idempotent: if SyncBridge already called it, this is a no-op.
    final session = ref.read(sessionScopeProvider);
    SyncOrchestrator.instance.startAll(
      userId: userId,
      sessionEpoch: session.sessionEpoch,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _linkSubscription?.cancel();
    _firstSyncSafetyTimer?.cancel();
    if (SyncOrchestrator.instance.onOnboardingCompleted ==
        _onboardingCallback) {
      SyncOrchestrator.instance.onOnboardingCompleted = null;
    }
    if (SyncOrchestrator.instance.onFirstSyncSettled == _firstSyncCallback) {
      SyncOrchestrator.instance.onFirstSyncSettled = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = ref.watch(sessionScopeProvider);
    if (session.logoutInProgress) {
      return const AuthLoadingScreen();
    }

    if (_isAuthenticated) {
      if (_onboardingState == _OnboardingState.unknown) {
        return const AuthLoadingScreen();
      }
      if (_onboardingState == _OnboardingState.notCompleted) {
        return OnboardingScreen(
          onComplete: () {
            setState(() {
              _onboardingState = _OnboardingState.completed;
            });
          },
        );
      }
      // Note: ShellScaffold tracks its own screen views (Tasks/Chat/Focus/etc)
      return const ShellScaffold();
    }

    log('AUTH: AuthGate.build returning AuthScreen (_isAuthenticated=false)');
    return const AuthScreen();
  }
}
