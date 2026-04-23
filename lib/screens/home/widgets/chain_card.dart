import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/app_constants.dart';
import '../../../models/alarm_chain.dart';
import '../../../models/chain_step.dart';
import '../../../models/nfc_tag_data.dart';

// ─── 알람 체인 카드 ───────────────────────────────────────────────────────────
class ChainCard extends StatelessWidget {
    final AlarmChain chain;
    final List<NfcTagData> nfcTags;
    final String countdown;
    final (bool, String?) checkInStatus;
    final VoidCallback onTap;
    final VoidCallback onCheckIn;

    const ChainCard({
        super.key,
        required this.chain,
        required this.nfcTags,
        required this.countdown,
        required this.checkInStatus,
        required this.onTap,
        required this.onCheckIn,
    });

    String _stepTagSummary(ChainStep step) {
        if (step.nfcTagIds.isEmpty) return '태그 없음';
        final names = step.nfcTagIds.map((id) {
            for (final t in nfcTags) { if (t.id == id) return t.name; }
            return null;
        }).whereType<String>().toList();
        if (names.isEmpty) return '태그 없음';
        if (names.length == 1) return names.first;
        return '${names.first} 외 ${names.length - 1}개';
    }

    @override
    Widget build(BuildContext context) {
        final (canCheckIn, blockReason) = checkInStatus;
        final daysText = chain.days.isEmpty
            ? '요일 미설정'
            : chain.days.map((d) => AppConstants.dayLabels[d - 1]).join(' ');

        return GestureDetector(
            onTap: onTap,
            child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.chainCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                        const Icon(Icons.link, color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(chain.name, style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
                        GestureDetector(
                            onTap: onCheckIn,
                            child: Tooltip(
                                message: canCheckIn ? '체인 체크인' : (blockReason ?? ''),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: canCheckIn
                                            ? Colors.green.withValues(alpha: 0.2)
                                            : Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: canCheckIn ? Colors.green : Colors.grey.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.location_on, size: 13,
                                            color: canCheckIn ? Colors.green : Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('체크인', style: TextStyle(
                                            fontSize: 11,
                                            color: canCheckIn ? Colors.green : Colors.grey,
                                            fontWeight: FontWeight.w600)),
                                    ]),
                                ),
                            ),
                        ),
                    ]),
                    const SizedBox(height: 14),
                    if (chain.steps.isEmpty)
                        const Text('단계 없음', style: TextStyle(color: Colors.grey, fontSize: 12))
                    else
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                                children: List.generate(chain.steps.length * 2 - 1, (i) {
                                    if (i.isOdd) {
                                        return const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 6),
                                            child: Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
                                        );
                                    }
                                    final step = chain.steps[i ~/ 2];
                                    final h = step.hour.toString().padLeft(2, '0');
                                    final m = step.minute.toString().padLeft(2, '0');
                                    return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.white12),
                                        ),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                            Text('$h:$m', style: const TextStyle(
                                                color: Colors.white, fontSize: 18,
                                                fontWeight: FontWeight.bold)),
                                            if (step.label.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(step.label, style: const TextStyle(
                                                    color: Colors.white70, fontSize: 10)),
                                            ],
                                            const SizedBox(height: 3),
                                            Row(mainAxisSize: MainAxisSize.min, children: [
                                                Icon(Icons.nfc, size: 10,
                                                    color: step.nfcTagIds.isNotEmpty
                                                        ? Colors.lightBlueAccent : Colors.grey),
                                                const SizedBox(width: 2),
                                                Text(_stepTagSummary(step), style: TextStyle(
                                                    fontSize: 9,
                                                    color: step.nfcTagIds.isNotEmpty
                                                        ? Colors.lightBlueAccent : Colors.grey)),
                                            ]),
                                        ]),
                                    );
                                }),
                            ),
                        ),
                    const SizedBox(height: 10),
                    Row(children: [
                        Text(daysText, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        const Spacer(),
                        if (countdown.isNotEmpty)
                            Text(countdown, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ]),
                ]),
            ),
        );
    }
}
