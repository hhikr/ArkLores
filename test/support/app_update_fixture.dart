Map<String, Object?> appReleaseJson(
  String version, {
  bool prerelease = false,
}) =>
    {
      'tag_name': 'v$version',
      'prerelease': prerelease,
      'draft': false,
      'body': '## Changes\n- Faster reading',
      'assets': [
        {
          'name': 'ArkLores-$version.apk',
          'size': 10485760,
          'browser_download_url': 'https://example.test/app.apk',
        },
        {
          'name': 'ArkLores-$version.apk.sha256',
          'browser_download_url': 'https://example.test/app.sha256',
        },
      ],
    };
