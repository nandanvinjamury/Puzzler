import 'package:flutter/material.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';

/// chess.com-inspired dark palette.
class AppColors {
  static const bg = Color(0xFF302E2B);
  static const surface = Color(0xFF3A3835);
  static const surfaceHigh = Color(0xFF454340);
  static const green = Color(0xFF81B64C);
  static const greenDark = Color(0xFF5D8A37);
  static const text = Color(0xFFEDEDED);
  static const textMuted = Color(0xFF9E9C99);
  static const fire = Color(0xFFFF7A29);
  static const fireHot = Color(0xFFFFC23D);
  static const gold = Color(0xFFE2B53C);
  static const boardLight = Color(0xFFEBECD0);
  static const boardDark = Color(0xFF739552);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.green,
    surface: AppColors.surface,
    onSurface: AppColors.text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        // Horizontal padding too, so content-sized buttons (dialog actions)
        // aren't cramped against their edges.
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.text,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.bg,
      side: BorderSide(color: Color(0xFF4A4744)),
      labelStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
    ),
  );
}

/// chess.com-style green board.
const ChessboardColorScheme chesscomBoard = ChessboardColorScheme(
  lightSquare: AppColors.boardLight,
  darkSquare: AppColors.boardDark,
  background: SolidColorChessboardBackground(
    lightSquare: AppColors.boardLight,
    darkSquare: AppColors.boardDark,
  ),
  whiteCoordBackground: SolidColorChessboardBackground(
    lightSquare: AppColors.boardLight,
    darkSquare: AppColors.boardDark,
    coordinates: true,
  ),
  blackCoordBackground: SolidColorChessboardBackground(
    lightSquare: AppColors.boardLight,
    darkSquare: AppColors.boardDark,
    coordinates: true,
    orientation: Side.black,
  ),
  lastMove: HighlightDetails(solidColor: Color.fromRGBO(255, 235, 59, 0.45)),
  selected: HighlightDetails(solidColor: Color.fromRGBO(255, 235, 59, 0.40)),
  validMoves: Color.fromRGBO(0, 0, 0, 0.18),
  validPremoves: Color.fromRGBO(255, 122, 41, 0.40),
);
