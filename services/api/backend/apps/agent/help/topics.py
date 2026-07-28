from __future__ import annotations

TOPICS_DATA: list[dict] = [
    {
        "id": "phone",
        "label": "Телефон / отвлечения",
        "intent": "Пользователь застрял в быстром облегчении, ленте, переключении внимания или цифровом шуме.",
        "subtopics": [
            {"id": "stuck_after_scroll", "label": "Залип и не могу переключиться"},
            {"id": "one_more_minute", "label": "Ещё чуть-чуть затягивает"},
            {"id": "focus_feels_gray", "label": "После ленты всё серое"},
            {"id": "phone_hides_tension", "label": "Телефон прячет напряжение"},
        ],
    },
    {
        "id": "energy",
        "label": "Нет сил / плохо",
        "intent": "Пользователь может быть в усталости, перегрузе, плохом состоянии или близко к честному выходу.",
        "subtopics": [
            {"id": "physically_tired", "label": "Физически устал"},
            {"id": "head_full", "label": "Голова забита"},
            {"id": "dont_want_to_explain", "label": "Не хочу объяснять"},
            {"id": "afraid_of_another_attempt", "label": "Боюсь ещё одной попытки"},
        ],
    },
    {
        "id": "task_aversion",
        "label": "Не хочу задачу",
        "intent": "Пользователь сопротивляется самой задаче: она неприятная, скучная, бессмысленная или эмоционально токсичная.",
        "subtopics": [
            {"id": "unpleasant_to_look", "label": "Неприятно смотреть"},
            {"id": "boring_turn_away", "label": "Скучно и тянет отвернуться"},
            {"id": "no_meaning", "label": "Не вижу смысла"},
            {"id": "task_itself_annoys", "label": "Бесит сама задача"},
        ],
    },
    {
        "id": "unclear_start",
        "label": "Не понимаю, с чего начать",
        "intent": "Пользователь не видит вход: первый шаг мутный, вариантов много, чек-лист не превращается в действие.",
        "subtopics": [
            {"id": "no_first_step", "label": "Нет первого шага"},
            {"id": "checklist_blurry", "label": "Чек-лист мутный"},
            {"id": "too_many_options", "label": "Слишком много вариантов"},
            {"id": "need_room_entry", "label": "Нужен вход из комнаты"},
        ],
    },
    {
        "id": "too_much_fear",
        "label": "Слишком много / страшно",
        "intent": "Пользователь видит задачу или план как слишком большой, оценочный или опасный для самоощущения.",
        "subtopics": [
            {"id": "plan_huge", "label": "План выглядит огромным"},
            {"id": "afraid_to_fail", "label": "Боюсь провалиться"},
            {"id": "want_perfect_start", "label": "Хочу начать идеально"},
            {"id": "afraid_to_see_result", "label": "Страшно увидеть результат"},
        ],
    },
    {
        "id": "day_broken",
        "label": "Уже сорвал день",
        "intent": "Пользователь в стыде, сожалении, позднем старте или желании дождаться нового чистого дня.",
        "subtopics": [
            {"id": "too_late", "label": "Кажется, уже поздно"},
            {"id": "ashamed_of_zero", "label": "Стыдно смотреть на ноль"},
            {"id": "failed_again", "label": "Опять не смог"},
            {"id": "wait_for_tomorrow", "label": "Хочу дождаться завтра"},
        ],
    },
    {
        "id": "pressure_reactance",
        "label": "Давит / сопротивляюсь",
        "intent": "Пользователь реагирует не на задачу, а на ощущение давления, контроля, таймера или уговоров.",
        "subtopics": [
            {"id": "hate_being_pushed", "label": "Бесит, когда уговаривают"},
            {"id": "my_own_way", "label": "Хочу сделать по-своему"},
            {"id": "no_timer", "label": "Не хочу таймер"},
            {"id": "became_obligation", "label": "Всё стало обязанностью"},
        ],
    },
    {
        "id": "unknown",
        "label": "Не понимаю, что со мной",
        "intent": "Пользователь не может выбрать причину или чувствует несколько слоёв сразу.",
        "subtopics": [
            {"id": "cant_name_reason", "label": "Не могу назвать причину"},
            {"id": "many_things_mixed", "label": "Смешалось сразу несколько"},
            {"id": "honest_exit", "label": "Хочу просто честно выйти"},
            {"id": "let_question_clarify", "label": "Пусть вопрос уточнит"},
        ],
    },
]

TOPIC_BY_ID: dict[str, dict] = {t["id"]: t for t in TOPICS_DATA}

SUBTOPIC_BY_ID: dict[tuple[str, str], dict] = {
    (t["id"], s["id"]): s for t in TOPICS_DATA for s in t["subtopics"]
}


def validate_topic_subtopic(topic_id: str, subtopic_id: str) -> tuple[str, str]:
    topic = TOPIC_BY_ID.get(topic_id)
    if topic is None:
        raise ValueError(f"Unknown topic_id: {topic_id!r}")
    subtopic = SUBTOPIC_BY_ID.get((topic_id, subtopic_id))
    if subtopic is None:
        raise ValueError(f"Unknown subtopic_id: {subtopic_id!r} for topic {topic_id!r}")
    return topic["label"], subtopic["label"]
