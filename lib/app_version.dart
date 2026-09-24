/// App identity stamped by CI before release builds.
/// Local/dev builds keep these defaults; CI overwrites [kBuildNumber]
/// with `github.run_number` so GitHub release tags (`build-N`) match.
library;

const String kAppVersion = '1.0.0';

/// Overwritten by `.github/workflows/build.yml` → `lib/app_version.dart`.
const int kBuildNumber = 51;

const String kSupportEmail = 'securedviewvpn@protonmail.com';
const String kGitHubRepo = 'eclipsedew/SecuredView';

String get kVersionLabel => '$kAppVersion ($kBuildNumber)';
