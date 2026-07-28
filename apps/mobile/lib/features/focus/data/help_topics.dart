class HelpSubtopic {
  final String id;
  final String label;

  const HelpSubtopic({required this.id, required this.label});
}

class HelpTopic {
  final String id;
  final String label;
  final List<HelpSubtopic> subtopics;

  const HelpTopic({
    required this.id,
    required this.label,
    required this.subtopics,
  });
}

const List<HelpTopic> kHelpTopics = [
  HelpTopic(
    id: 'phone',
    label: 'Телефон / отвлечения',
    subtopics: [
      HelpSubtopic(id: 'stuck_after_scroll', label: 'Залип и не могу переключиться'),
      HelpSubtopic(id: 'one_more_minute', label: 'Ещё чуть-чуть затягивает'),
      HelpSubtopic(id: 'focus_feels_gray', label: 'После ленты всё серое'),
      HelpSubtopic(id: 'phone_hides_tension', label: 'Телефон прячет напряжение'),
    ],
  ),
  HelpTopic(
    id: 'energy',
    label: 'Нет сил / плохо',
    subtopics: [
      HelpSubtopic(id: 'physically_tired', label: 'Физически устал'),
      HelpSubtopic(id: 'head_full', label: 'Голова забита'),
      HelpSubtopic(id: 'dont_want_to_explain', label: 'Не хочу объяснять'),
      HelpSubtopic(id: 'afraid_of_another_attempt', label: 'Боюсь ещё одной попытки'),
    ],
  ),
  HelpTopic(
    id: 'task_aversion',
    label: 'Не хочу задачу',
    subtopics: [
      HelpSubtopic(id: 'unpleasant_to_look', label: 'Неприятно смотреть'),
      HelpSubtopic(id: 'boring_turn_away', label: 'Скучно и тянет отвернуться'),
      HelpSubtopic(id: 'no_meaning', label: 'Не вижу смысла'),
      HelpSubtopic(id: 'task_itself_annoys', label: 'Бесит сама задача'),
    ],
  ),
  HelpTopic(
    id: 'unclear_start',
    label: 'Не понимаю, с чего начать',
    subtopics: [
      HelpSubtopic(id: 'no_first_step', label: 'Нет первого шага'),
      HelpSubtopic(id: 'checklist_blurry', label: 'Чек-лист мутный'),
      HelpSubtopic(id: 'too_many_options', label: 'Слишком много вариантов'),
      HelpSubtopic(id: 'need_room_entry', label: 'Нужен вход из комнаты'),
    ],
  ),
  HelpTopic(
    id: 'too_much_fear',
    label: 'Слишком много / страшно',
    subtopics: [
      HelpSubtopic(id: 'plan_huge', label: 'План выглядит огромным'),
      HelpSubtopic(id: 'afraid_to_fail', label: 'Боюсь провалиться'),
      HelpSubtopic(id: 'want_perfect_start', label: 'Хочу начать идеально'),
      HelpSubtopic(id: 'afraid_to_see_result', label: 'Страшно увидеть результат'),
    ],
  ),
  HelpTopic(
    id: 'day_broken',
    label: 'Уже сорвал день',
    subtopics: [
      HelpSubtopic(id: 'too_late', label: 'Кажется, уже поздно'),
      HelpSubtopic(id: 'ashamed_of_zero', label: 'Стыдно смотреть на ноль'),
      HelpSubtopic(id: 'failed_again', label: 'Опять не смог'),
      HelpSubtopic(id: 'wait_for_tomorrow', label: 'Хочу дождаться завтра'),
    ],
  ),
  HelpTopic(
    id: 'pressure_reactance',
    label: 'Давит / сопротивляюсь',
    subtopics: [
      HelpSubtopic(id: 'hate_being_pushed', label: 'Бесит, когда уговаривают'),
      HelpSubtopic(id: 'my_own_way', label: 'Хочу сделать по-своему'),
      HelpSubtopic(id: 'no_timer', label: 'Не хочу таймер'),
      HelpSubtopic(id: 'became_obligation', label: 'Всё стало обязанностью'),
    ],
  ),
  HelpTopic(
    id: 'unknown',
    label: 'Не понимаю, что со мной',
    subtopics: [
      HelpSubtopic(id: 'cant_name_reason', label: 'Не могу назвать причину'),
      HelpSubtopic(id: 'many_things_mixed', label: 'Смешалось сразу несколько'),
      HelpSubtopic(id: 'honest_exit', label: 'Хочу просто честно выйти'),
      HelpSubtopic(id: 'let_question_clarify', label: 'Пусть вопрос уточнит'),
    ],
  ),
];
