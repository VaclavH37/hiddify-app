import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/config_slot.dart';

void main() {
  group('configSlotStorageId', () {
    const id = '6f9619ff-8b86-d011-b42d-00c04fc964ff';

    test('the primary slot is the bare profile id', () {
      // Load-bearing: every config sealed before the standby slot existed was
      // written under the bare id, and must keep opening after this change.
      expect(configSlotStorageId(id, ConfigSlot.primary), id);
    });

    test('the standby slot appends the suffix the native readers will derive', () {
      // ConfigCipher.kt and ConfigCipher.swift both compute the AAD by stripping
      // `.enc` off the file's base name, so `<id>.standby.enc` must yield
      // exactly `<id>.standby` or the native decrypt fails on a
      // system-initiated start.
      expect(configSlotStorageId(id, ConfigSlot.standby), '$id.standby');
    });

    test('the two slots never collide', () {
      expect(configSlotStorageId(id, ConfigSlot.primary), isNot(configSlotStorageId(id, ConfigSlot.standby)));
    });
  });

  group('standbyRefreshDue', () {
    final now = DateTime(2026, 8, 28, 12);

    test('fetches when there is no cache at all', () {
      expect(standbyRefreshDue(null, null, now), isTrue);
    });

    test('does not fetch a cache younger than the max age', () {
      expect(standbyRefreshDue(now.subtract(const Duration(hours: 23)), null, now), isFalse);
    });

    test('fetches once the cache reaches the max age', () {
      expect(standbyRefreshDue(now.subtract(standbyCacheMaxAge), null, now), isTrue);
      expect(standbyRefreshDue(now.subtract(const Duration(days: 9)), null, now), isTrue);
    });

    test('backs off after a recent attempt, even with no cache', () {
      // The case that matters: a middleware that does not serve the standby
      // tier fails every time, and without this it would retry every cycle.
      expect(standbyRefreshDue(null, now.subtract(const Duration(minutes: 5)), now), isFalse);
    });

    test('retries once the attempt floor has passed', () {
      expect(standbyRefreshDue(null, now.subtract(standbyRetryFloor), now), isTrue);
    });

    test('an old attempt does not by itself force a fetch of a fresh cache', () {
      expect(
        standbyRefreshDue(now.subtract(const Duration(hours: 2)), now.subtract(const Duration(hours: 2)), now),
        isFalse,
      );
    });

    test('a cache timestamped in the future is refetched, not trusted forever', () {
      // The device clock is user-settable. Treating a future stamp as fresh
      // would freeze the cache with no way back short of a reinstall.
      expect(standbyRefreshDue(now.add(const Duration(days: 365)), null, now), isTrue);
    });

    test('an attempt timestamped in the future does not suppress the fetch', () {
      expect(standbyRefreshDue(null, now.add(const Duration(days: 365)), now), isTrue);
    });
  });

  group('configSlotOf', () {
    test('reads the standby slot', () {
      expect(configSlotOf('standby'), ConfigSlot.standby);
    });

    test('tolerates casing and surrounding whitespace', () {
      expect(configSlotOf('  Standby '), ConfigSlot.standby);
      expect(configSlotOf('STANDBY'), ConfigSlot.standby);
    });

    test('defaults to primary for absent, blank and unrecognised values', () {
      // Defaulting the other way would let one unreadable preference strand a
      // healthy subscriber on the inferior link, invisibly.
      for (final raw in [null, '', '   ', 'primary', 'garbage', 'standby-ish', '0']) {
        expect(configSlotOf(raw), ConfigSlot.primary, reason: 'input: ${raw ?? "null"}');
      }
    });

    test('round-trips the name it is persisted under', () {
      for (final slot in ConfigSlot.values) {
        expect(configSlotOf(slot.name), slot);
      }
    });
  });
}
