import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/utils/ip_utils.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

/// URL-test delays at or above this are the core's "no answer" sentinel.
const int _delayTimeout = 65000;

/// What a long-press on a server shows: where it is, how it is doing, and
/// how much has gone through it. Presented as a bottom sheet on a phone and
/// a small dialog on desktop by `DialogNotifier.showProxyInfo`.
///
/// This replaced a dialog that listed every field of the outbound message,
/// booleans as tick and cross emoji included. Two kinds of row are gone on
/// purpose. The flags (is selected, is group, is secure) said nothing a
/// person would act on. The tag, type, host, port and ASN describe the
/// fleet rather than the user's connection; the middleware withholds that
/// shape of information elsewhere, so a details panel should not hand it
/// out either. A debug build still shows them, at the bottom.
class ProxyDetailsSheet extends HookConsumerWidget {
  const ProxyDetailsSheet({super.key, required this.outboundInfo});

  final OutboundInfo outboundInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final revealIp = useState(false);

    final ip = outboundInfo.ipinfo;
    final location = [ip.city, ip.region, ip.countryCode].where((part) => part.isNotEmpty).join(', ');
    final delay = outboundInfo.urlTestDelay;
    final latency = switch (delay) {
      <= 0 => t.pages.proxies.delay.measuring,
      >= _delayTimeout => t.pages.proxies.delay.noResponse,
      _ => '$delay ms',
    };
    final lastTested = outboundInfo.hasUrlTestTime()
        ? DateFormat('yyyy-MM-dd HH:mm').format(outboundInfo.urlTestTime.toDateTime().toLocal())
        : null;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.lg, RaynSpacing.xl, RaynSpacing.sm),
            // The resolved exit, the way the location card names it: "Tokyo,
            // JP" for an auto-select group too, not "Lowest -> EXIT-Tokyo, JP".
            child: Text(
              activeProxyDisplay(outboundInfo, t).name,
              style: RaynTypography.title.copyWith(color: palette.textPrimary),
            ),
          ),
          if (location.isNotEmpty) _DetailRow(label: t.dialogs.proxyInfo.location, value: location),
          if (ip.ip.isNotEmpty)
            _DetailRow(
              label: t.dialogs.proxyInfo.ipAddress,
              value: revealIp.value ? ip.ip : obscureIp(ip.ip),
              semanticsValue: revealIp.value ? ip.ip : t.common.hidden,
              trailing: Icon(revealIp.value ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onTap: () => revealIp.value = !revealIp.value,
            ),
          if (ip.org.isNotEmpty) _DetailRow(label: t.dialogs.proxyInfo.organization, value: ip.org),
          _DetailRow(label: t.dialogs.proxyInfo.latency, value: latency),
          if (lastTested != null) _DetailRow(label: t.dialogs.proxyInfo.lastTested, value: lastTested),
          _DetailRow(label: t.dialogs.proxyInfo.downloaded, value: outboundInfo.download.toInt().size()),
          _DetailRow(label: t.dialogs.proxyInfo.uploaded, value: outboundInfo.upload.toInt().size()),
          if (kDebugMode) ...[
            const Divider(indent: RaynSpacing.xl, endIndent: RaynSpacing.xl),
            _DetailRow(label: t.dialogs.proxyInfo.tag, value: outboundInfo.tag),
            _DetailRow(label: t.dialogs.proxyInfo.type, value: outboundInfo.type),
            if (outboundInfo.host.isNotEmpty) _DetailRow(label: t.dialogs.proxyInfo.host, value: outboundInfo.host),
            if (outboundInfo.port != 0) _DetailRow(label: t.dialogs.proxyInfo.port, value: '${outboundInfo.port}'),
            if (ip.asn != 0) _DetailRow(label: t.dialogs.proxyInfo.asn, value: 'AS${ip.asn}'),
            if (ip.latitude != 0 || ip.longitude != 0)
              _DetailRow(label: t.dialogs.proxyInfo.coordinates, value: '${ip.latitude}, ${ip.longitude}'),
          ],
          const SizedBox(height: RaynSpacing.sm),
        ],
      ),
    );
  }
}

/// A label on the left, its value on the right, in the app's type.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.semanticsValue, this.trailing, this.onTap});

  final String label;
  final String value;
  final String? semanticsValue;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl, vertical: RaynSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: RaynTypography.label.copyWith(color: palette.textSecondary)),
          ),
          const SizedBox(width: RaynSpacing.md),
          Expanded(
            child: Text(
              value,
              semanticsLabel: semanticsValue,
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              style: RaynTypography.body.copyWith(
                fontWeight: FontWeight.w400,
                color: palette.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: RaynSpacing.sm),
            IconTheme.merge(
              data: IconThemeData(color: palette.textSecondary),
              child: trailing!,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
