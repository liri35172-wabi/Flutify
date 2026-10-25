/// 应用信息（设置页「关于」、开源许可页使用）。
///
/// 版本号必须与 pubspec.yaml 的 `version` 一致，`test/core/app_info_test.dart` 会校验。
class AppInfo {
  AppInfo._();

  static const String name = 'Flutify';
  static const String version = '0.16.2';

  /// Android CI overrides this with the exact versionCode passed to `flutter build`.
  static const int build = int.fromEnvironment(
    'FLUTIFY_BUILD_NUMBER',
    defaultValue: 16,
  );

  /// CI run and commit label, supplied by artifact-producing workflows.
  static const String buildId = String.fromEnvironment('FLUTIFY_BUILD_ID');
  static const String _buildReleaseTag = String.fromEnvironment(
    'FLUTIFY_RELEASE_TAG',
    defaultValue: 'v0.16.2',
  );
  static const String releaseTag = _buildReleaseTag == ''
      ? 'v0.16.2'
      : _buildReleaseTag;

  /// 「0.16.2 (16)」
  static String get displayVersion => '$version ($build)';
}
