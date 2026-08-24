import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:uuid/uuid.dart';

void main() {
  const validBaseUrl = "https://example.com/configurations/user1/filename.yaml";
  const validExtendedUrl = "https://example.com/configurations/user1/filename.yaml?test#b";
  const validSupportUrl = "https://example.com/support";

  group("parse", () {
    test("Should use filename in url with no headers and fragment", () {
      final profile = ProfileParser.parse(
        content: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validBaseUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("filename"));
            expect(rp.url, equals(validBaseUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use fragment in url with no headers", () {
      final profile = ProfileParser.parse(
        content: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validExtendedUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("b"));
            expect(rp.url, equals(validExtendedUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use base64 title in headers", () {
      final headers = <String, List<String>>{
        "profile-title": ["base64:ZXhhbXBsZVRpdGxl"],
        "profile-update-interval": ["1"],
        "connection-test-url": [validBaseUrl],
        "remote-dns-address": [validBaseUrl],
        "subscription-userinfo": ["upload=0;download=1024;total=10240.5;expire=1704054600.55"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          content: '',
          profile: ProfileEntity.remote(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validExtendedUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.name, equals("exampleTitle"));
              expect(rp.url, equals(validExtendedUrl));
              expect(rp.options, equals(const ProfileOptions(updateInterval: Duration(hours: 1))));
              expect(
                rp.subInfo,
                equals(
                  SubscriptionInfo(
                    upload: 0,
                    download: 1024,
                    total: 10240,
                    expire: DateTime.fromMillisecondsSinceEpoch(1704054600 * 1000),
                    webPageUrl: validBaseUrl,
                    supportUrl: validSupportUrl,
                  ),
                ),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    test("Should use infinite when given 0 for subscription properties", () {
      final headers = <String, List<String>>{
        "profile-title": ["title"],
        "profile-update-interval": ["1"],
        "subscription-userinfo": ["upload=0;download=1024;total=0;expire=0"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          content: '',
          profile: RemoteProfileEntity(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validBaseUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.subInfo, isNotNull);
              expect(rp.subInfo!.total, equals(ProfileParser.infiniteTrafficThreshold + 1));
              expect(
                rp.subInfo!.expire,
                equals(DateTime.fromMillisecondsSinceEpoch(ProfileParser.infiniteTimeThreshold * 1000)),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    test("Should parse subscription-refill-date into refillDate", () {
      final headers = <String, List<String>>{
        "profile-title": ["title"],
        "subscription-userinfo": ["upload=0;download=1024;total=10240;expire=1704054600"],
        "subscription-refill-date": ["1782864600"],
      };
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          content: '',
          profile: RemoteProfileEntity(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validBaseUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          r.map(
            remote: (rp) {
              expect(rp.subInfo, isNotNull);
              expect(
                rp.subInfo!.refillDate,
                equals(DateTime.fromMillisecondsSinceEpoch(1782864600 * 1000)),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    test("Should leave refillDate null when subscription-refill-date is 0 or absent", () {
      for (final refill in <String?>["0", null]) {
        final headers = <String, List<String>>{
          "profile-title": ["title"],
          "subscription-userinfo": ["upload=0;download=1024;total=10240;expire=1704054600"],
          if (refill != null) "subscription-refill-date": [refill],
        };
        final fixedHeaders = headers.map((key, value) {
          if (value.length == 1) return MapEntry(key, value.first);
          return MapEntry(key, value);
        });
        final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
        allHeaders.match((l) {}, (r) {
          final profile = ProfileParser.parse(
            content: '',
            profile: RemoteProfileEntity(
              id: const Uuid().v4(),
              active: true,
              name: '',
              url: validBaseUrl,
              lastUpdate: DateTime.now(),
              populatedHeaders: r,
            ),
          );
          profile.match((l) {}, (r) {
            r.map(
              remote: (rp) {
                expect(rp.subInfo, isNotNull);
                expect(rp.subInfo!.refillDate, isNull);
              },
              local: (lp) {},
            );
          });
        });
      }
    });
  });

  group("hub tier headers", () {
    // The middleware decides the tier and emits only that tier's outbounds; the
    // client's whole job is to carry these two headers through to the UI and the
    // reconnect. They ride populatedHeaders rather than a Drift column, so they
    // have to be on the allowlist or they are silently dropped here.
    test("Should keep subscription-hub-tier and subscription-hub-tier-until", () {
      final headers = ProfileParser.populateHeaders(
        content: '',
        remoteHeaders: {
          'subscription-hub-tier': 'standby',
          'subscription-hub-tier-until': '1790000000',
        },
      );
      expect(headers.isRight(), true);
      headers.match((l) {}, (r) {
        expect(r['subscription-hub-tier'], equals('standby'));
        expect(r['subscription-hub-tier-until'], equals('1790000000'));
      });
    });

    test("Should still drop headers that are not on the allowlist", () {
      final headers = ProfileParser.populateHeaders(
        content: '',
        remoteHeaders: {'subscription-hub-tier': 'standby', 'x-rayn-internal': 'leak'},
      );
      headers.match((l) {}, (r) {
        expect(r.containsKey('subscription-hub-tier'), true);
        expect(r.containsKey('x-rayn-internal'), false);
      });
    });
  });
}
