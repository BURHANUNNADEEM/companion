import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Family contacts and the "Ask my family" helper. Stored ONLY on this phone; never sent to the server.
class FamilyContact {
  FamilyContact(this.name, this.phone, this.relation);
  final String name;
  final String phone;
  final String relation; // son, daughter, family, doctor, wife, husband, brother, sister

  Map<String, String> toJson() => {'name': name, 'phone': phone, 'relation': relation};
  factory FamilyContact.fromJson(Map<String, dynamic> j) =>
      FamilyContact(j['name'] as String? ?? '', j['phone'] as String? ?? '', j['relation'] as String? ?? 'family');
}

const kRelations = {
  'son': ['Son', 'بیٹا'],
  'daughter': ['Daughter', 'بیٹی'],
  'wife': ['Wife', 'بیوی'],
  'husband': ['Husband', 'شوہر'],
  'brother': ['Brother', 'بھائی'],
  'sister': ['Sister', 'بہن'],
  'doctor': ['Doctor', 'ڈاکٹر'],
  'family': ['Family', 'گھر والے'],
};

class ContactsStore {
  static const _key = 'family_contacts_v1';
  List<FamilyContact> contacts = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return;
    contacts = (jsonDecode(raw) as List).map((e) => FamilyContact.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(contacts.map((c) => c.toJson()).toList()));
  }

  FamilyContact? get helper => contacts.isEmpty ? null : contacts.first;

  /// Resolve a spoken contact ("son", "Ali", "علی") to a saved phone number, on device.
  String? resolve({String? contact, String? relation}) {
    if (contact == '__device_helper__') return helper?.phone;
    final c = (contact ?? '').trim().toLowerCase();
    if (relation != null) {
      for (final x in contacts) {
        if (x.relation == relation) return x.phone;
      }
    }
    if (c.isEmpty) return null;
    for (final x in contacts) {
      if (x.relation == c || x.name.toLowerCase() == c) return x.phone;
    }
    for (final x in contacts) {
      if (x.name.toLowerCase().contains(c) || c.contains(x.name.toLowerCase())) return x.phone;
    }
    return null;
  }
}
