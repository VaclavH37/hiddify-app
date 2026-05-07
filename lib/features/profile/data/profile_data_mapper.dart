import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

extension ProfileEntityMapper on ProfileEntity {
  ProfileEntriesCompanion toInsertEntry() => map(
    remote: (rp) => ProfileEntriesCompanion.insert(
      id: rp.id,
      type: ProfileType.remote,
      active: rp.active,
      name: rp.name,
      url: Value(rp.url),
      lastUpdate: rp.lastUpdate,
      updateInterval: Value(rp.options?.updateInterval),
      populatedHeaders: Value(jsonEncode(rp.populatedHeaders)),
      profileOverride: Value(rp.profileOverride),
      userOverride: Value(rp.userOverride?.toStr()),
      upload: Value(rp.subInfo?.upload),
      download: Value(rp.subInfo?.download),
      total: Value(rp.subInfo?.total),
      expire: Value(rp.subInfo?.expire),
      webPageUrl: Value(rp.subInfo?.webPageUrl),
      supportUrl: Value(rp.subInfo?.supportUrl),
      sourceToken: Value(rp.sourceToken),
      fallbackUrl: Value(rp.fallbackUrl),
      fallbackSourceToken: Value(rp.fallbackSourceToken),
    ),
    local: (lp) => ProfileEntriesCompanion.insert(
      id: lp.id,
      type: ProfileType.local,
      active: lp.active,
      name: lp.name,
      lastUpdate: lp.lastUpdate,
      populatedHeaders: Value(jsonEncode(lp.populatedHeaders)),
      profileOverride: Value(lp.profileOverride),
      userOverride: Value(lp.userOverride?.toStr()),
    ),
  );

  ProfileEntriesCompanion toUpdateEntry() => map(
    remote: (rp) => ProfileEntriesCompanion(
      name: Value(rp.name),
      lastUpdate: Value(rp.lastUpdate),
      updateInterval: Value(rp.options?.updateInterval),
      populatedHeaders: Value(jsonEncode(rp.populatedHeaders)),
      profileOverride: Value(rp.profileOverride),
      userOverride: Value(rp.userOverride?.toStr()),
      upload: Value(rp.subInfo?.upload),
      download: Value(rp.subInfo?.download),
      total: Value(rp.subInfo?.total),
      expire: Value(rp.subInfo?.expire),
      webPageUrl: Value(rp.subInfo?.webPageUrl),
      supportUrl: Value(rp.subInfo?.supportUrl),
      // url + sourceToken persist any backend-driven token rotation
      // (`new-url` response header). fallbackUrl + fallbackSourceToken
      // persist the optional `fallback-url` header. When neither header
      // is present (or matches the existing value), the writes are
      // benign no-ops.
      url: Value(rp.url),
      sourceToken: Value(rp.sourceToken),
      fallbackUrl: Value(rp.fallbackUrl),
      fallbackSourceToken: Value(rp.fallbackSourceToken),
    ),
    local: (lp) => ProfileEntriesCompanion(
      name: Value(lp.name),
      lastUpdate: Value(lp.lastUpdate),
      populatedHeaders: Value(jsonEncode(lp.populatedHeaders)),
      profileOverride: Value(lp.profileOverride),
      userOverride: Value(lp.userOverride?.toStr()),
    ),
  );
}

extension ProfileEntryMapper on ProfileEntry {
  ProfileEntity toEntity() {
    ProfileOptions? options;
    if (updateInterval != null) {
      options = ProfileOptions(updateInterval: updateInterval!);
    }

    SubscriptionInfo? subInfo;
    if (upload != null && download != null && total != null && expire != null) {
      subInfo = SubscriptionInfo(
        upload: upload!,
        download: download!,
        total: total!,
        expire: expire!,
        webPageUrl: webPageUrl,
        supportUrl: supportUrl,
      );
    }
    Map<String, dynamic>? mPopulatedHeaders;

    if (populatedHeaders != null) {
      final m = jsonDecode(populatedHeaders!) as Map;
      mPopulatedHeaders = m.cast<String, dynamic>();
    }

    return switch (type) {
      ProfileType.remote => RemoteProfileEntity(
        id: id,
        active: active,
        name: name,
        url: url!,
        lastUpdate: lastUpdate,
        options: options,
        subInfo: subInfo,
        populatedHeaders: mPopulatedHeaders,
        profileOverride: profileOverride,
        userOverride: UserOverride.fromStr(userOverride),
        sourceToken: sourceToken,
        fallbackUrl: fallbackUrl,
        fallbackSourceToken: fallbackSourceToken,
      ),
      ProfileType.local => LocalProfileEntity(
        id: id,
        active: active,
        name: name,
        lastUpdate: lastUpdate,
        populatedHeaders: mPopulatedHeaders,
        profileOverride: profileOverride,
        userOverride: UserOverride.fromStr(userOverride),
      ),
    };
  }
}
