/// design/system.md 1章の `quiz_questions` テーブルに対応するクイズ問題モデル。
///
/// `payload` jsonbは `{"question": "...", "choices": ["...", ...]}` 形式を前提とする。
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.questionText,
    required this.choices,
    required this.correctAnswer,
    required this.timeLimitSeconds,
  });

  final String id;
  final String questionText;
  final List<String> choices;
  final String correctAnswer;
  final int timeLimitSeconds;

  factory QuizQuestion.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return QuizQuestion(
      id: map['id'] as String,
      questionText: payload['question'] as String,
      choices: (payload['choices'] as List).map((e) => e as String).toList(),
      correctAnswer: map['correct_answer'] as String,
      timeLimitSeconds: map['time_limit_seconds'] as int? ?? 15,
    );
  }
}
