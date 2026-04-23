import 'package:flutter/services.dart';

class AppConstants {
    static const int    autoOffSeconds       = 300;
    static const int    muteDurationSeconds  = 120;
    static const int    testAlarmId          = 99;
    static const String packageName          = 'com.example.nfc_alarm';
    static const List<String> dayLabels      = ['월', '화', '수', '목', '금', '토', '일'];

    static const overlayChannel = MethodChannel('com.example.nfc_alarm/overlay');
}
