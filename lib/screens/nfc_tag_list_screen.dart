import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../models/nfc_tag_data.dart';
import '../providers/nfc_tag_provider.dart';
import '../services/nfc_service.dart';

// ─── NFC 태그 관리 화면 ───────────────────────────────────────────────────────
class NfcTagListScreen extends ConsumerWidget {
    const NfcTagListScreen({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref) {
        final tags = ref.watch(nfcTagProvider).tags;
        return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
                backgroundColor: Colors.transparent,
                title: const Text('NFC 태그 관리', style: TextStyle(color: Colors.white)),
                iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: tags.isEmpty
                ? const Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(Icons.nfc, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('등록된 태그가 없습니다',
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                        SizedBox(height: 8),
                        Text('+ 버튼으로 태그를 추가하세요',
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                ))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: tags.length,
                    itemBuilder: (_, i) {
                        final tag = tags[i];
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                                decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white12),
                                ),
                                child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 8),
                                    leading: const Icon(Icons.nfc, color: Colors.lightBlueAccent),
                                    title: Text(tag.name, style: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.bold)),
                                    subtitle: Text(tag.uid,
                                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                        IconButton(
                                            icon: const Icon(Icons.sensors,
                                                color: Colors.greenAccent, size: 20),
                                            tooltip: '태그 테스트',
                                            onPressed: () => _testTag(context, tag)),
                                        IconButton(
                                            icon: const Icon(Icons.edit_outlined,
                                                color: Colors.white54, size: 20),
                                            onPressed: () => _openSheet(context, ref, tag)),
                                        IconButton(
                                            icon: const Icon(Icons.delete_outline,
                                                color: Colors.red, size: 20),
                                            onPressed: () => _delete(context, ref, tag)),
                                    ]),
                                ),
                            ),
                        );
                    },
                ),
            floatingActionButton: FloatingActionButton(
                onPressed: () => _openSheet(context, ref, null),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: Colors.white),
            ),
        );
    }

    Future<void> _testTag(BuildContext context, NfcTagData tag) async {
        final isAvailable = await NfcService.instance.isAvailable();
        if (!isAvailable) {
            if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('NFC를 사용할 수 없습니다')));
            }
            return;
        }
        if (context.mounted) {
            await showDialog(
                context: context,
                builder: (_) => _NfcTagTestDialog(tag: tag),
            );
        }
    }

    Future<void> _openSheet(BuildContext context, WidgetRef ref, NfcTagData? tag) async {
        await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (_) => _NfcTagEditSheet(
                tag: tag,
                onSave: (name, uid) async {
                    if (tag == null) {
                        await ref.read(nfcTagProvider.notifier).add(name, uid);
                    } else {
                        await ref.read(nfcTagProvider.notifier).update(tag.id, name, uid);
                    }
                    if (context.mounted) Navigator.pop(context);
                },
            ),
        );
    }

    Future<void> _delete(BuildContext context, WidgetRef ref, NfcTagData tag) async {
        final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                title: const Text('태그 삭제'),
                content: Text('"${tag.name}" 태그를 삭제할까요?'),
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
            await ref.read(nfcTagProvider.notifier).delete(tag.id);
        }
    }
}

// ─── NFC 태그 테스트 다이얼로그 ───────────────────────────────────────────────
class _NfcTagTestDialog extends StatefulWidget {
    final NfcTagData tag;
    const _NfcTagTestDialog({required this.tag});
    @override
    State<_NfcTagTestDialog> createState() => _NfcTagTestDialogState();
}

class _NfcTagTestDialogState extends State<_NfcTagTestDialog> {
    String _status = 'scanning';
    String? _scannedUid;

    @override
    void initState() { super.initState(); _startScan(); }

    Future<void> _startScan() async {
        NfcService.instance.startSession(onDiscovered: (tag) async {
            final uid = NfcService.instance.extractUid(tag);
            await NfcService.instance.stopSession();
            if (uid != null && mounted) {
                setState(() {
                    _scannedUid = uid;
                    _status = uid == widget.tag.uid ? 'matched' : 'mismatch';
                });
            }
        });
    }

    @override
    void dispose() { NfcService.instance.stopSession(); super.dispose(); }

    @override
    Widget build(BuildContext context) {
        return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('"${widget.tag.name}" 테스트',
                style: const TextStyle(color: Colors.white)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                if (_status == 'scanning') ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('태그를 폰에 갖다 대세요',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 8),
                ] else if (_status == 'matched') ...[
                    const Icon(Icons.check_circle, color: Colors.green, size: 72),
                    const SizedBox(height: 12),
                    const Text('일치!', style: TextStyle(
                        color: Colors.green, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_scannedUid ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ] else ...[
                    const Icon(Icons.cancel, color: Colors.red, size: 72),
                    const SizedBox(height: 12),
                    const Text('불일치', style: TextStyle(
                        color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('스캔: $_scannedUid', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('등록: ${widget.tag.uid}',
                        style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
            ]),
            actions: [
                if (_status != 'scanning')
                    TextButton(
                        onPressed: () {
                            setState(() { _status = 'scanning'; _scannedUid = null; });
                            _startScan();
                        },
                        child: const Text('다시 테스트')),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기')),
            ],
        );
    }
}

// ─── NFC 태그 편집 바텀 시트 ──────────────────────────────────────────────────
class _NfcTagEditSheet extends StatefulWidget {
    final NfcTagData? tag;
    final Future<void> Function(String name, String uid) onSave;

    const _NfcTagEditSheet({required this.tag, required this.onSave});

    @override
    State<_NfcTagEditSheet> createState() => _NfcTagEditSheetState();
}

class _NfcTagEditSheetState extends State<_NfcTagEditSheet> {
    late TextEditingController _nameCtrl;
    String? _scannedUid;
    bool _scanning = false, _saving = false;

    @override
    void initState() {
        super.initState();
        _nameCtrl = TextEditingController(text: widget.tag?.name ?? '');
        _scannedUid = widget.tag?.uid;
    }

    @override
    void dispose() { _nameCtrl.dispose(); NfcService.instance.stopSession(); super.dispose(); }

    Future<void> _startScan() async {
        if (!await NfcService.instance.isAvailable()) return;
        setState(() => _scanning = true);
        NfcService.instance.startSession(onDiscovered: (tag) async {
            final uid = NfcService.instance.extractUid(tag);
            NfcService.instance.stopSession();
            if (uid != null && mounted) {
                setState(() { _scannedUid = uid; _scanning = false; });
            }
        });
    }

    Future<void> _save() async {
        if (_nameCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('태그 이름을 입력하세요')));
            return;
        }
        if (_scannedUid == null) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('NFC 태그를 스캔하세요')));
            return;
        }
        setState(() => _saving = true);
        await widget.onSave(_nameCtrl.text.trim(), _scannedUid!);
    }

    @override
    Widget build(BuildContext context) {
        return Padding(
            padding: EdgeInsets.only(
                left: 24, right: 24, top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    Text(widget.tag == null ? 'NFC 태그 추가' : 'NFC 태그 편집',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    TextField(
                        controller: _nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                            labelText: '태그 이름 (예: 집 문앞)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Colors.blue)),
                        ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                        onPressed: _scanning ? null : _startScan,
                        icon: _scanning
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.nfc),
                        label: Text(_scanning
                            ? '태그를 갖다 대세요...'
                            : _scannedUid == null ? 'NFC 스캔' : '다시 스캔'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.lightBlueAccent,
                            side: const BorderSide(color: Colors.lightBlueAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                    if (_scannedUid != null) ...[
                        const SizedBox(height: 8),
                        Text('스캔됨: $_scannedUid',
                            style: const TextStyle(color: Colors.green, fontSize: 12),
                            textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: _saving
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('저장', style: TextStyle(color: Colors.white)),
                    ),
                ],
            ),
        );
    }
}
