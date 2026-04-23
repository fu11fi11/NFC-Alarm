import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../models/alarm_chain.dart';
import '../models/chain_step.dart';
import '../providers/chain_provider.dart';
import '../providers/nfc_tag_provider.dart';
import '../services/app_logger.dart';
import '../widgets/day_selector.dart';
import 'chain_step_edit_screen.dart';

// ─── 알람 체인 편집 / 생성 화면 ───────────────────────────────────────────────
class ChainEditScreen extends ConsumerStatefulWidget {
    final AlarmChain? chain;
    const ChainEditScreen({super.key, this.chain});

    @override
    ConsumerState<ChainEditScreen> createState() => _ChainEditScreenState();
}

class _ChainEditScreenState extends ConsumerState<ChainEditScreen> {
    late TextEditingController _nameCtrl;
    late List<int> _days;
    late List<ChainStep> _steps;
    bool _saving = false;

    @override
    void initState() {
        super.initState();
        _nameCtrl = TextEditingController(text: widget.chain?.name ?? '');
        _days = List.from(widget.chain?.days ?? [1, 2, 3, 4, 5]);
        _steps = List.from(widget.chain?.steps ?? []);
    }

    @override
    void dispose() { _nameCtrl.dispose(); super.dispose(); }

    Future<void> _openStepEdit(ChainStep? step, int? index) async {
        final nfcTags = ref.read(nfcTagProvider).tags;
        final usedTagIds = <int>{};
        for (int i = 0; i < _steps.length; i++) {
            if (i != index) usedTagIds.addAll(_steps[i].nfcTagIds);
        }
        final result = await Navigator.push<ChainStep>(
            context,
            MaterialPageRoute(builder: (_) => ChainStepEditScreen(
                step: step,
                nfcTags: nfcTags,
                excludedTagIds: usedTagIds,
            )),
        );
        if (result != null) {
            setState(() {
                if (index == null) { _steps.add(result); }
                else { _steps[index] = result; }
            });
        }
    }

    Future<void> _save() async {
        if (_nameCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('체인 이름을 입력하세요')));
            return;
        }
        if (_days.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('요일을 하나 이상 선택하세요')));
            return;
        }
        if (_steps.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('단계를 하나 이상 추가하세요')));
            return;
        }
        setState(() => _saving = true);
        final tags = ref.read(nfcTagProvider).tags;
        if (widget.chain == null) {
            appLog(LogTag.chain, '체인 생성 — 이름: ${_nameCtrl.text.trim()}');
            await ref.read(chainProvider.notifier).add(
                name: _nameCtrl.text.trim(), days: _days,
                steps: _steps, allTags: tags,
            );
        } else {
            appLog(LogTag.chain, '체인 수정 — ID: ${widget.chain!.id}');
            await ref.read(chainProvider.notifier).update(
                widget.chain!,
                name: _nameCtrl.text.trim(), days: _days,
                steps: _steps, allTags: tags,
            );
        }
        if (mounted) Navigator.pop(context);
    }

    Future<void> _confirmDelete() async {
        final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                title: const Text('체인 삭제'),
                content: const Text('이 체인을 삭제할까요?'),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('삭제', style: TextStyle(color: Colors.red))),
                ],
            ),
        );
        if (confirm == true) {
            final tags = ref.read(nfcTagProvider).tags;
            await ref.read(chainProvider.notifier).delete(widget.chain!, tags);
            if (mounted) Navigator.pop(context);
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
                backgroundColor: Colors.transparent,
                title: Text(widget.chain == null ? '새 체인' : '체인 편집',
                    style: const TextStyle(color: Colors.white)),
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                    if (widget.chain != null)
                        IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: _confirmDelete),
                ],
            ),
            body: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: TextField(
                        controller: _nameCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        decoration: InputDecoration(
                            labelText: '체인 이름 (예: 아침 루틴)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.blue)),
                        ),
                    ),
                ),
                const SizedBox(height: 16),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('반복 요일', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 10),
                        DaySelector(
                            selectedDays: _days,
                            onChanged: (days) => setState(() => _days = days),
                        ),
                    ]),
                ),
                const SizedBox(height: 16),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                        const Text('단계', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const Spacer(),
                        TextButton.icon(
                            onPressed: () => _openStepEdit(null, null),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('단계 추가'),
                            style: TextButton.styleFrom(foregroundColor: Colors.blue),
                        ),
                    ]),
                ),
                Expanded(
                    child: _steps.isEmpty
                        ? const Center(child: Text('단계를 추가하세요',
                            style: TextStyle(color: Colors.grey)))
                        : ReorderableListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                            onReorder: (o, n) {
                                setState(() {
                                    if (n > o) n--;
                                    final item = _steps.removeAt(o);
                                    _steps.insert(n, item);
                                });
                            },
                            children: List.generate(_steps.length, (i) {
                                final step = _steps[i];
                                final h = step.hour.toString().padLeft(2, '0');
                                final m = step.minute.toString().padLeft(2, '0');
                                return Padding(
                                    key: ValueKey('step_$i'),
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Container(
                                        decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white12),
                                        ),
                                        child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 4),
                                            leading: Container(
                                                width: 28, height: 28,
                                                decoration: const BoxDecoration(
                                                    color: AppColors.primary,
                                                    shape: BoxShape.circle),
                                                child: Center(child: Text('${i + 1}',
                                                    style: const TextStyle(
                                                        color: Colors.white, fontSize: 12,
                                                        fontWeight: FontWeight.bold))),
                                            ),
                                            title: Text(
                                                '$h:$m${step.label.isNotEmpty ? "  ·  ${step.label}" : ""}',
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 14)),
                                            subtitle: Text(
                                                step.nfcTagIds.isEmpty
                                                    ? '아무 태그나'
                                                    : '태그 ${step.nfcTagIds.length}개',
                                                style: const TextStyle(
                                                    color: Colors.white38, fontSize: 11)),
                                            trailing: Row(mainAxisSize: MainAxisSize.min,
                                                children: [
                                                    IconButton(
                                                        icon: const Icon(Icons.edit_outlined,
                                                            color: Colors.white54, size: 18),
                                                        onPressed: () => _openStepEdit(step, i)),
                                                    IconButton(
                                                        icon: const Icon(Icons.close,
                                                            color: Colors.red, size: 18),
                                                        onPressed: () => setState(
                                                            () => _steps.removeAt(i))),
                                                    const Icon(Icons.drag_handle,
                                                        color: Colors.white38, size: 20),
                                                ]),
                                        ),
                                    ),
                                );
                            }),
                        ),
                ),
            ]),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: _saving ? null : _save,
                backgroundColor: AppColors.primary,
                icon: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, color: Colors.white),
                label: const Text('저장', style: TextStyle(color: Colors.white)),
            ),
        );
    }
}
