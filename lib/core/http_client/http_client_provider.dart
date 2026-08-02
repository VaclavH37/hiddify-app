import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'http_client_provider.g.dart';

@Riverpod(keepAlive: true)
DioHttpClient httpClient(Ref ref) {
  final client = DioHttpClient(
    timeout: const Duration(seconds: 15),
    userAgent: ref.watch(appInfoProvider).requireValue.userAgent,
    debug: kDebugMode,
  );

  // The mixed port is a compile-time constant now that it is not user-editable, so
  // this no longer needs to be a subscription. That is the point: the listener used
  // to fire the instant the preference changed, while the core kept its old listener
  // until restart — leaving this client pointed at a closed port, where it fell back
  // to DIRECT and sent subscription/API traffic outside the tunnel.
  client.setProxyPort(ConfigOptions.kMixedPort);
  return client;
}
