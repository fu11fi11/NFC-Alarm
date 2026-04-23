import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_data.dart';
import '../models/alarm_chain.dart';
import '../models/nfc_tag_data.dart';

// ─── 스토리지 로드 결과 ────────────────────────────────────────────────────────
class StorageData {
    final List<NfcTagData> tags;
    final int nextTagId;
    final List<AlarmData> alarms;
    final int nextAlarmId;
    final List<AlarmChain> chains;
    final int nextChainId;

    const StorageData({
        required this.tags, required this.nextTagId,
        required this.alarms, required this.nextAlarmId,
        required this.chains, required this.nextChainId,
    });
}

// ─── 스토리지 서비스 ───────────────────────────────────────────────────────────
class StorageService {
    static final StorageService instance = StorageService._();
    StorageService._();

    // 앱 최초 실행 시 모든 데이터를 한 번에 로드 (구버전 마이그레이션 포함)
    Future<StorageData> loadAll() async {
        final prefs = await SharedPreferences.getInstance();

        final tags = await _loadTags(prefs);
        final alarms = await _loadAlarms(prefs, tags.list);
        final chains = await _loadChains(prefs);

        return StorageData(
            tags: tags.list, nextTagId: tags.nextId,
            alarms: alarms.list, nextAlarmId: alarms.nextId,
            chains: chains.list, nextChainId: chains.nextId,
        );
    }

    // ─── NFC 태그 ─────────────────────────────────────────────────────────────

    Future<({List<NfcTagData> list, int nextId})> _loadTags(SharedPreferences prefs) async {
        final json = prefs.getString('nfc_tags');
        if (json != null) {
            final list = (jsonDecode(json) as List)
                .map((e) => NfcTagData.fromJson(e as Map<String, dynamic>))
                .toList();
            final nextId = prefs.getInt('nfc_tag_next_id') ??
                list.fold<int>(0, (m, t) => t.id >= m ? t.id + 1 : m);
            return (list: list, nextId: nextId);
        }
        // 구버전 단일 태그 마이그레이션
        final oldUid = prefs.getString('nfc_uid');
        if (oldUid != null) {
            final list = [NfcTagData(id: 0, name: '기본 태그', uid: oldUid)];
            await saveNfcTags(list, 1);
            return (list: list, nextId: 1);
        }
        return (list: <NfcTagData>[], nextId: 0);
    }

    Future<void> saveNfcTags(List<NfcTagData> tags, int nextId) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('nfc_tags', jsonEncode(tags.map((t) => t.toJson()).toList()));
        await prefs.setInt('nfc_tag_next_id', nextId);
    }

    // ─── 알람 ─────────────────────────────────────────────────────────────────

    Future<({List<AlarmData> list, int nextId})> _loadAlarms(
        SharedPreferences prefs, List<NfcTagData> tags) async {
        final json = prefs.getString('alarms');
        if (json != null) {
            final list = (jsonDecode(json) as List)
                .map((e) => AlarmData.fromJson(e as Map<String, dynamic>))
                .toList();
            final nextId = prefs.getInt('alarm_next_id') ??
                list.fold<int>(0, (m, a) => a.id >= m ? a.id + 1 : m);
            return (list: list, nextId: nextId);
        }
        // 구버전 단일 알람 마이그레이션
        final hour = prefs.getInt('alarm_hour');
        if (hour != null) {
            final minute = prefs.getInt('alarm_minute') ?? 0;
            final daysStr = prefs.getString('alarm_days') ?? '';
            final enabled = prefs.getBool('alarm_enabled') ?? false;
            final days = daysStr.isEmpty ? <int>[] : daysStr.split(',').map(int.parse).toList();
            final list = [AlarmData(
                id: 0, hour: hour, minute: minute, days: days, enabled: enabled,
                nfcTagIds: tags.isEmpty ? [] : [tags.first.id],
            )];
            await saveAlarms(list, 1);
            return (list: list, nextId: 1);
        }
        return (list: <AlarmData>[], nextId: 0);
    }

    Future<void> saveAlarms(List<AlarmData> alarms, int nextId) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('alarms', jsonEncode(alarms.map((a) => a.toJson()).toList()));
        await prefs.setInt('alarm_next_id', nextId);
    }

    // ─── 체인 ─────────────────────────────────────────────────────────────────

    Future<({List<AlarmChain> list, int nextId})> _loadChains(SharedPreferences prefs) async {
        final json = prefs.getString('chains');
        if (json != null) {
            final list = (jsonDecode(json) as List)
                .map((e) => AlarmChain.fromJson(e as Map<String, dynamic>))
                .toList();
            final nextId = prefs.getInt('chain_next_id') ??
                list.fold<int>(0, (m, c) => c.id >= m ? c.id + 1 : m);
            return (list: list, nextId: nextId);
        }
        return (list: <AlarmChain>[], nextId: 0);
    }

    Future<void> saveChains(List<AlarmChain> chains, int nextId) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('chains', jsonEncode(chains.map((c) => c.toJson()).toList()));
        await prefs.setInt('chain_next_id', nextId);
    }
}
