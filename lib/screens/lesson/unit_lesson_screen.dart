import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/course_language.dart';
import '../../data/models/lesson_content.dart';
import '../../data/models/lesson_unit.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import 'can_do_card.dart';
import 'milestone_celebration.dart';
import 'views/convo_lesson_view.dart';
import 'views/grammar_lesson_view.dart';
import 'views/practice_lesson_view.dart';
import 'views/pronunc_lesson_view.dart';
import 'views/strategy_lesson_view.dart';
import 'views/vocab_lesson_view.dart';

/// Lesson-track navigation for a unit: dots + prev/next, dispatching to one
/// of the 6 per-type views (`renderSection`/`lessonNav`/`jumpSection` in the
/// source app). Awards +50 XP and shows CanDoCard/MilestoneCelebration on
/// finishing the last lesson (`markUnitDone`).
class UnitLessonScreen extends StatefulWidget {
  final LessonUnit unit;
  final int initialIndex;
  const UnitLessonScreen({super.key, required this.unit, this.initialIndex = 0});

  @override
  State<UnitLessonScreen> createState() => _UnitLessonScreenState();
}

class _UnitLessonScreenState extends State<UnitLessonScreen> {
  late final AppStateProvider _app;
  late int _index;
  late bool _canComplete;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    _index = widget.initialIndex.clamp(0, widget.unit.lessons.length - 1);
    _canComplete = widget.unit.lessons[_index].type != LessonType.practice;
  }

  @override
  void dispose() {
    _app.cloudTts.stop();
    super.dispose();
  }

  Lesson get _lesson => widget.unit.lessons[_index].forPair(_app.courseLanguage, _app.nativeLanguage);

  void _speak(String text) {
    _app.cloudTts.speak(text, rate: 0.5, voiceGender: _app.voiceGender, language: resolveLocale(_app.courseLanguage));
  }

  void _jumpTo(int i) {
    setState(() {
      _index = i;
      _canComplete = widget.unit.lessons[i].type != LessonType.practice;
    });
  }

  Future<void> _onNext() async {
    await _app.curriculumProgress.markLessonComplete(widget.unit.id, _index);
    if (_index < widget.unit.lessons.length - 1) {
      _jumpTo(_index + 1);
    } else {
      await _finishUnit();
    }
  }

  Future<void> _finishUnit() async {
    await _app.curriculumProgress.markUnitComplete(widget.unit.id);
    await _app.addXp(50);
    final meta = _app.curriculum.progressionFor(widget.unit.id);
    if (!mounted) return;
    if (meta != null && meta.progression.milestone) {
      await showMilestoneCelebration(context, meta);
    } else if (meta != null) {
      await showCanDoCard(context, meta);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lessons = widget.unit.lessons;
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      appBar: AppBar(
        title: Text(widget.unit.title, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          _LessonDots(count: lessons.length, index: _index, onTap: _jumpTo),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(_lesson.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_lesson.name,
                          style: const TextStyle(
                              fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                      if (_lesson.desc.isNotEmpty)
                        Text(_lesson.desc, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_index > 0)
                    OutlinedButton(
                      onPressed: () => _jumpTo(_index - 1),
                      child: Text(AppLocalizations.of(context)!.unitLessonPrevious),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _canComplete ? _onNext : null,
                    child: Text(_index < lessons.length - 1
                        ? AppLocalizations.of(context)!.unitLessonContinue
                        : AppLocalizations.of(context)!.unitLessonFinishUnit),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }

  Widget _buildContent() {
    final lesson = _lesson;
    final unit = widget.unit.unit;
    return switch (lesson.content) {
      VocabLessonContent c => VocabLessonView(unit: unit, blockIndex: _index, items: c.items, onSpeak: _speak),
      ConvoLessonContent c =>
        ConvoLessonView(unit: unit, blockIndex: _index, dialogues: c.dialogues, onSpeak: _speak),
      GrammarLessonContent c => GrammarLessonView(unit: unit, blockIndex: _index, content: c),
      PracticeLessonContent c => PracticeLessonView(
          unit: unit,
          blockIndex: _index,
          questions: c.questions,
          onCanCompleteChanged: (v) => setState(() => _canComplete = v),
          onCorrectAnswer: (xp) => _app.addXp(xp),
        ),
      PronuncLessonContent c => PronuncLessonView(unit: unit, blockIndex: _index, items: c.items, onSpeak: _speak),
      StrategyLessonContent c =>
        StrategyLessonView(unit: unit, blockIndex: _index, items: c.items, onSpeak: _speak),
      UnknownLessonContent _ => Center(
          child: Text(AppLocalizations.of(context)!.unitLessonUnsupportedType,
              style: const TextStyle(color: AppTheme.textSubDark)),
        ),
    };
  }
}

class _LessonDots extends StatelessWidget {
  final int count;
  final int index;
  final ValueChanged<int> onTap;
  const _LessonDots({required this.count, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Semantics(
                button: true,
                label: AppLocalizations.of(context)!.unitLessonStepSemanticsLabel(i + 1, count),
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= index ? AppTheme.accentBright : AppTheme.borderDark,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
