import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';

/// The one line a failed post-purchase import writes to the log. It names the
/// step that failed and never the subscription URL, which is the credential.
void main() {
  final options = RequestOptions(path: 'https://sub.example.com/s/secret-state');

  test('a covert 404 reads as the status code, without the url', () {
    final failure = ProfileFailure.unexpected(
      DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
        type: DioExceptionType.badResponse,
      ),
    );
    expect(failure.logSummary, 'HTTP 404');
  });

  test('a transport failure reads as its kind, without the url', () {
    final failure = ProfileFailure.unexpected(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'https://sub.example.com/s/secret-state timed out',
      ),
    );
    expect(failure.logSummary, 'transport connectionTimeout');
    expect(failure.logSummary, isNot(contains('secret-state')));
  });

  test('the verdicts read by kind and code', () {
    expect(const ProfileFailure.subscriptionExpired().logSummary, 'subscription expired verdict');
    expect(
      const ProfileFailure.accountUnavailable('ACCOUNT_SUSPENDED').logSummary,
      'account unavailable (ACCOUNT_SUSPENDED)',
    );
    expect(
      const ProfileFailure.accountUnavailable('ACCOUNT_PENDING', Duration(minutes: 5)).logSummary,
      'account unavailable (ACCOUNT_PENDING, retry after 300s)',
    );
  });

  test("a rejected config carries the core's reason, clipped", () {
    const reason = 'cannot reach the local core to validate the configuration: x';
    expect(const ProfileFailure.invalidConfig(reason).logSummary, 'config rejected: $reason');
    expect(const ProfileFailure.invalidConfig().logSummary, 'config rejected: no reason given');
    expect(ProfileFailure.invalidConfig('a' * 500).logSummary.length, lessThan(200));
  });

  test('the local failures read by kind', () {
    expect(const ProfileFailure.configUnreadable().logSummary, 'sealed config unreadable');
    expect(const ProfileFailure.notFound().logSummary, 'profile row not found');
    expect(const ProfileFailure.unexpected(FormatException('bad')).logSummary, 'unexpected FormatException');
    expect(const ProfileFailure.unexpected().logSummary, 'unexpected');
  });
}
