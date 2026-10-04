import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';

/// The subscription User-Agent names the platform so the MW can count
/// installs per device type. It must keep the `Rayn` prefix the MW checks
/// first, and carry the platform only: no OS version, model or locale.
void main() {
  AppInfoEntity info(String os) => AppInfoEntity(
    name: 'Rayn VPN',
    version: '1.6.1',
    buildNumber: '10601',
    release: Release.general,
    operatingSystem: os,
    operatingSystemVersion: 'Version 18.2 (Build 22C152)',
    environment: Environment.prod,
  );

  test('names the platform in brackets after the version', () {
    expect(info('ios').subscriptionUserAgent, 'Rayn/1.6.1 (ios)');
    expect(info('android').subscriptionUserAgent, 'Rayn/1.6.1 (android)');
    expect(info('windows').subscriptionUserAgent, 'Rayn/1.6.1 (windows)');
    expect(info('macos').subscriptionUserAgent, 'Rayn/1.6.1 (macos)');
    expect(info('linux').subscriptionUserAgent, 'Rayn/1.6.1 (linux)');
  });

  test('keeps the prefix the MW accepts, and leaves out the OS version and build', () {
    final agent = info('ios').subscriptionUserAgent;
    expect(agent.toLowerCase(), startsWith('rayn/'));
    expect(agent, isNot(contains('18.2')));
    expect(agent, isNot(contains('10601')));
  });

  test('uses the same platform names as the backend User-Agent', () {
    final app = info('macos');
    expect(app.userAgent, 'RaynVPN/1.6.1 (macos)');
    expect(app.subscriptionUserAgent, 'Rayn/1.6.1 (macos)');
  });
}
