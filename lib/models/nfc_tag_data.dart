// ─── NFC 태그 모델 ────────────────────────────────────────────────────────────
class NfcTagData {
    final int id;
    final String name;
    final String uid;

    const NfcTagData({required this.id, required this.name, required this.uid});

    NfcTagData copyWith({String? name, String? uid}) =>
        NfcTagData(id: id, name: name ?? this.name, uid: uid ?? this.uid);

    Map<String, dynamic> toJson() => {'id': id, 'name': name, 'uid': uid};

    factory NfcTagData.fromJson(Map<String, dynamic> j) =>
        NfcTagData(id: j['id'] as int, name: j['name'] as String, uid: j['uid'] as String);
}
