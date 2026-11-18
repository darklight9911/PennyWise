import '../../features/auth/application/auth_controller.dart';

/// Route paths, so screens never hard-code strings.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  static const dashboard = '/';
  static const transactions = '/transactions';
  static const reports = '/reports';
  static const export = '/export';
  static const setPin = '/settings/app-lock';
  static const settings = '/settings';

  static const categories = '/categories';
  static const budgets = '/budgets';
  static const goals = '/goals';
  static const newGoal = '/goals/new';
  static String goal(String id) => '/goals/$id';
  static String editGoal(String id) => '/goals/$id/edit';
  static const recurring = '/recurring';
  static const newRecurring = '/recurring/new';
  static String editRecurring(String id) => '/recurring/$id';
  static const newBudget = '/budgets/new';
  static String editBudget(String id) => '/budgets/$id';
  static const accounts = '/accounts';
  static const newAccount = '/accounts/new';
  static String editAccount(String id) => '/accounts/$id';

  static const _transactionPrefix = '/transaction';
  static String newTransaction([String kind = 'expense']) =>
      '$_transactionPrefix/new?kind=$kind';
  static String editTransaction(String id) => '$_transactionPrefix/$id';
  static const transactionNewPath = '$_transactionPrefix/new';
  static const transactionEditPath = '$_transactionPrefix/:id';

  static String resetPasswordWith(String token) =>
      Uri(path: resetPassword, queryParameters: {'token': token}).toString();
}

/// Screens for people who are not logged in.
const _signedOutOnly = {Routes.login, Routes.register, Routes.forgotPassword};

/// Open to everyone: a reset link must work whether or not you are logged in.
const _public = {Routes.resetPassword};

/// Decides where the user may go. Returns a new location, or null to stay.
String? authRedirect(AuthState auth, String location) {
  if (_public.contains(location)) return null;
  return switch (auth) {
    AuthLoading() => location == Routes.splash ? null : Routes.splash,
    SignedOut() => _signedOutOnly.contains(location) ? null : Routes.login,
    SignedIn() =>
      _signedOutOnly.contains(location) || location == Routes.splash
          ? Routes.dashboard
          : null,
  };
}
