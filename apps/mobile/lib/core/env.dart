class Env {
  // Будем прокидывать значение через --dart-define
  static const apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8001',
  );
  // Supabase
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const supabaseRedirectUrl = String.fromEnvironment(
    'SUPABASE_REDIRECT_URL',
    defaultValue: 'com.meleo.mobile.supabase://oauthredirect',
  );

  // Registration flow flags

  // Sentry Configuration
  static const sentryDsnDev = String.fromEnvironment(
    'SENTRY_DSN_DEV',
    defaultValue: '',
  );
  static const sentryDsnProd = String.fromEnvironment(
    'SENTRY_DSN_PROD',
    defaultValue: '',
  );
  static const environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'dev', // dev or prod
  );

  // PostHog Analytics
  static const posthogApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
    defaultValue: '',
  );
  static const posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );

  static bool get isProd => environment.toLowerCase() == 'prod';
}
