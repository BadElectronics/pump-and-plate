import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';

void main() {
  test('dark hours, including across midnight', () {
    DateTime at(int h, int m) => DateTime(2026, 10, 4, h, m);
    const eightPm = 20 * 60, sevenAm = 7 * 60;
    expect(isNightTime(at(21, 0), eightPm, sevenAm), isTrue);
    expect(isNightTime(at(3, 0), eightPm, sevenAm), isTrue);
    expect(isNightTime(at(7, 0), eightPm, sevenAm), isFalse); // light from 7:00
    expect(isNightTime(at(19, 59), eightPm, sevenAm), isFalse);
    expect(isNightTime(at(20, 0), eightPm, sevenAm), isTrue);
    expect(isNightTime(at(13, 0), 12 * 60, 14 * 60), isTrue); // a daytime range
    expect(isNightTime(at(13, 0), 600, 600), isFalse); // same times: never
  });

  test('the next switch', () {
    expect(nextThemeFlip(DateTime(2026, 10, 4, 15, 0), 20 * 60, 7 * 60), DateTime(2026, 10, 4, 20, 0));
    expect(nextThemeFlip(DateTime(2026, 10, 4, 22, 0), 20 * 60, 7 * 60), DateTime(2026, 10, 5, 7, 0));
    expect(nextThemeFlip(DateTime(2026, 10, 4, 20, 0), 20 * 60, 7 * 60), DateTime(2026, 10, 5, 7, 0)); // strictly after
  });

  test('the settings are saved', () {
    final a = const AppSettings().copyWith(darkSchedule: true, darkFrom: 1290, darkTo: 390, darkThemeId: 'emerald');
    final b = AppSettings.fromRow(a.toRow());
    expect([b.darkSchedule, b.darkFrom, b.darkTo, b.darkThemeId], [true, 1290, 390, 'emerald']);
    final d = AppSettings.fromRow(const AppSettings().toRow());
    expect([d.darkSchedule, d.darkFrom, d.darkTo, d.darkThemeId], [false, 1200, 420, 'night']);
  });

  testWidgets('the app goes dark during the set hours', (tester) async {
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    // Dark from an hour ago until an hour from now (wrapping past midnight is fine).
    final settings = const AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, themeId: 'earth')
        .copyWith(darkSchedule: true, darkFrom: (m - 60) % 1440, darkTo: (m + 60) % 1440);
    await tester.pumpWidget(FitApp(store: MemoryStore(StoredData(settings: settings)), reminders: NoopReminders()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.dark);
  });

  testWidgets('and stays light outside them', (tester) async {
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    final settings = const AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, themeId: 'earth')
        .copyWith(darkSchedule: true, darkFrom: (m + 120) % 1440, darkTo: (m + 180) % 1440);
    await tester.pumpWidget(FitApp(store: MemoryStore(StoredData(settings: settings)), reminders: NoopReminders()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.light);
  });

  testWidgets('a dark main theme still turns light when dark hours end', (tester) async {
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    // The main theme was set to Night before dark hours were turned on.
    final settings = const AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, themeId: 'night')
        .copyWith(darkSchedule: true, darkFrom: (m + 120) % 1440, darkTo: (m + 180) % 1440);
    await tester.pumpWidget(FitApp(store: MemoryStore(StoredData(settings: settings)), reminders: NoopReminders()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness, Brightness.light);
  });
}
