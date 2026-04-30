import 'package:flutter/material.dart';

/// Global theme mode notifier
/// (true = dark, false = light)
final ValueNotifier<bool> isDarkMode = ValueNotifier(true);

Color get scaffoldBackgroundColor => isDarkMode.value ? const Color(0xFF0D0D0D) : const Color(0xFFFFFFFF);
Color get primaryColor => isDarkMode.value ? const Color(0xFFF6F6F6) : const Color(0xFF0D0D0D);
