import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'constants/app_colors.dart';
import 'screens/home/home_screen.dart';

// ─── 앱 루트 위젯 ─────────────────────────────────────────────────────────────
class NfcAlarmApp extends ConsumerWidget {
    const NfcAlarmApp({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref) {
        return MaterialApp(
            title: 'NFC 알람',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: AppColors.primary,
                    brightness: Brightness.dark,
                ),
                useMaterial3: true,
            ),
            home: const HomeScreen(),
        );
    }
}
