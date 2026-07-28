import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../lesson/unit_lesson_screen.dart';

/// "Sessão de Estudo" — jumps straight into the next incomplete unit, at the
/// first lesson not yet marked done, so studying never requires manually
/// picking a unit.
class StudySessionScreen extends StatefulWidget {
  const StudySessionScreen({super.key});

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends State<StudySessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  void _resume() {
    final app = context.read<AppStateProvider>();
    for (final unit in app.curriculum.units) {
      if (app.curriculumProgress.isUnitComplete(unit.id)) continue;
      final completedLessons = app.curriculumProgress.completedLessonsForUnit(unit.id);
      var lessonIndex = 0;
      for (var i = 0; i < unit.lessons.length; i++) {
        if (!completedLessons.contains(i)) {
          lessonIndex = i;
          break;
        }
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => UnitLessonScreen(unit: unit, initialIndex: lessonIndex)),
      );
      return;
    }
    setState(() => _allDone = true);
  }

  bool _allDone = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessão de Estudo')),
      body: Center(
        child: _allDone
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('🎉 Você concluiu todo o currículo disponível!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Sora', fontSize: 16, color: AppTheme.textMainDark)),
              )
            : const CircularProgressIndicator(color: AppTheme.accentBright),
      ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}
