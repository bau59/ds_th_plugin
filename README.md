# Author Topic Bump Button (Discourse Theme Component)

Добавляет кнопку/таймер поднятия темы в меню действий первого поста для автора темы.

## Что делает
- Показывает элемент только:
  - в **первом посте темы**;
  - если текущий пользователь — **автор темы**;
  - если тема не закрыта;
  - если у пользователя есть право `canManageTopic`.
- При нажатии пробует endpoint'ы в таком порядке:
  1. `POST /t/:topic_id/timer` с `status_type=bump` и `time=now+1m`;
  2. `PUT /t/:topic_id/bump` (если есть на инстансе/в плагине);
  3. `PUT /t/:topic_id/reset-bump-date` как fallback.
- После успешного запроса:
  - показывается inline feedback у кнопки;
  - дополнительно показывается модалка с подтверждением (можно выключить настройкой).

## Интервал между поднятиями
- Если cooldown активен, вместо активной кнопки показывается **таймер** до следующего доступного поднятия.
- Таймер считается от `topic.bumped_at`.
- Настройки компонента:
  - `bump_interval_hours_default` — интервал по умолчанию (часы);
  - `group_bump_intervals` — интервалы по группам в формате:
    - `group_or_id:hours|group2:hours`
    - поддерживаются ключи `trust_level_0..4`, `moderators`, `admins`, а также id/slug/name группы
    - приоритет: `admins` → `moderators` → `trust_level_N` → default
    - пример: `trust_level_0:72|trust_level_1:48|trust_level_2:24|trust_level_3:12|trust_level_4:6|moderators:1|admins:12`
  - `show_success_modal` — показывать ли модалку после успеха.

## Важно
- Для `POST /t/:topic_id/timer` параметр `time` должен быть строго в будущем.


## Примечание по надежности таймера
- В topic-view не всегда приходит `bumped_at`, поэтому компонент использует `last_posted_at` как fallback и локально запоминает время последнего успешного поднятия для текущего топика (в `localStorage`), чтобы cooldown/таймер срабатывал сразу.
