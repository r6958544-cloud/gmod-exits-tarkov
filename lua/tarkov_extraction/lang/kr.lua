--[[
    Tarkov Deploy - English Language File
 
    This is a language file for the Tarkov Deploy addon series.
 
    To create a new language:
    1. Copy this entire file
    2. Rename it to your language code (e.g. "jp.lua", "kr.lua", "fr.lua")
    3. Change TarkovLang["en"] to TarkovLang["your_code"]
    4. Change _display_name to your language name (shown in settings)
    5. Translate all the values (right side of = sign)
 
    DO NOT change the keys (left side of = sign)!
    Only translate the values (text in quotes on the right).
]]
 
TarkovLang = TarkovLang or {}
TarkovLang["ru"] = {
    -- Display name shown in language selector
    _display_name = "Русский",
 
    -- Deploy screen
    your_character = "ВАШ ОСНОВНОЙ ПЕРСОНАЖ",
    deploy_ready = "ПРИГОТОВЬТЕСЬ!",
    settings = "НАСТРОЙКИ",
    setting_countdown = "Время Высадки",
 
	-- info
    setting_faction = "Фракция",
    info_battle = "Рейд",
    info_time = "День",
    info_level = "Уровень",
    info_operator = "Оператор",
 
	-- player data
    player_manager_title = "Менеджер Данных Игрока (Только суперадмин)",
    player_manager_superadmin_only = "Только суперадминистраторы могут управлять данными игроков.",
    player_online = "● Онлайн",
    player_offline = "○ Оффлайн",
    player_faction = "Фракция:",
    player_level = "Уровень:",
    player_time = "Время:",
    player_edition = "Издание:",
    player_no_data = "Нет данных игрока",
    player_unknown = "Неизвестно",
    player_manager_btn = "Менеджер Данных Игрока",
    edition_standard = "Стандарт",
    edition_eod = "Edge of Darkness",
    edition_unheard = "The Unheard",
 
    -- settings ui
    title = "НАСТРОЙКИ",
 
	-- global buttons
	btn_save = "Сохранить",
    btn_close = "Закрыть",
    btn_back = "Назад",
 
	-- tab
    tab_global = "Глобальные",
    tab_deploy = "Высадка",
    tab_extraction = "Эвакуация",
    tab_summary = "Общее",
    tab_death_effect = "Эффект смерти",
    tab_inertia = "Инерция",
	tab_about = "О моде",
 
	-- global settings
 
	language_label = "Язык",
    language_support_welcome = "Поддержка языков приветствуется!",
    raid_time = "Время Рейда (Минуты):",
    btn_reset_raid_time = "Сбросить Время Рейда",
    set_raid_time = "Установить Время Рейда (Минуты):",
    btn_set_raid_time = "Установить Время Рейда",
	btn_player_data = "Данные Игрока",	
 
	-- deploy settings
    background = "Фоновое Изображение",
    bg_art1 = "Арт 1",
    bg_art2 = "Арт 2",
    bg_map = "Миниатюра Карты",
    gamename = "Название Игры",
    countdown = "Высадка через:",
    blur = "Сила Размытия:",
    logo_opacity = "Прозрачность Логотипа:",
    overlay = "Оверлей Фона",
    show_on_join = "Показывать при Заходе",
    show_on_respawn = "Показывать при Респавне",
    respawn_on_deploy = "Респавниться после Высадки",
    btn_deploy = "Высадиться",
    btn_deploy_all = "Высадить Всех",	
 
	-- subscribe
    not_subscribed = "Вы не подписаны!",
    subscribe = "Подписаться",
 
	--WIP
    no_settings = "Нет доступных настроек",
    developing = "В разработке!",
 
	--extraction settings
	zone_expand = "Расширить Зону:",
	zone_grace = "Задержка после выхода (x0.1с):",
    extraction_redeploy_delay = "Задержка перед повторной высадкой:",
    btn_set_extract = "Установить Зону",
    btn_tool_settings = "Настройки инстр.",
    btn_zone_list = "Список Зон",
 
 
	-- about
	about_addons_title = "Аддоны из серии Таркова",
    about_body = "Версия: 1.2.0\nАвтор: 滑稽没JJ\nСпасибо за использование аддонов из серии Таркова!",
 
    about_creator_role = "Создатель",
    about_ru_translation_role = "Русский",
    about_tester_role = "Тестирование",
    about_ko_translation_role = "Корейский",
 
	-- settings desc
    desc_language = "Изменяет язык интерфейса используемый серией Таркова. Сохраняется как глобальная настройка языка для поддерживаемых аддонов.",
    desc_raid_time = "Устанавливает общую длительность рейда. При сохранении синхронизируется с сервером; при сбросе таймер рейда возвращается к этому значению.",
    desc_set_raid_time = "Устанавливает текущее оставшееся время рейда. Минимум — 1 минута, максимум — значение общего времени рейда.",
    desc_background = "Выбор фонового изображения экрана высадки. Изменения отображаются сразу и сохраняются в настройках.",
    desc_gamename = "Устанавливает название игры, отображаемое на экране высадки.",
    desc_countdown = "Устанавливает длительность обратного отсчёта перед завершением высадки.",
    desc_blur = "Регулирует силу размытия фона экрана высадки. Чем выше значение, тем сильнее размытие.",
    desc_logo_opacity = "Регулирует прозрачность логотипа на экране высадки. Чем выше значение, тем он более заметен.",
    desc_overlay = "Включает/выключает затемняющий оверлей поверх фона для лучшей читаемости текста.",
    desc_show_on_join = "Автоматически открывает экран высадки при входе игрока на сервер.",
    desc_show_on_respawn = "Автоматически открывает экран высадки после возрождения игрока.",
    desc_respawn_on_deploy = "Респавнит игрока когда высадка завершается. Полезно для серверов которые обновляют состояние игрока при высадке.",
    desc_zone_expand = "Расширяет границы зоны эвакуации. Более высокие значения позволяют засчитывать игроков дальше от исходного края зоны.",
    desc_zone_grace = "Устанавливает короткий льготный период после выхода из зоны эвакуации (в единицах по 0.1 секунды).",
    desc_extraction_redeploy_delay = "Устанавливает время ожидания после успешной эвакуации до повторного открытия экрана высадки.",
 
	-- confirm
    confirm_title = "Подтвердить",
    confirm_unsaved = "Некоторые настройки были изменены. Желаете сохранить их?",
    confirm_yes = "Да [Y]",
    confirm_no = "Нет [N]",
 
	-- extraction hud
	-- DO NOT change %02d and %d 
    hud_find_extraction = "Найти Выход",
    hud_extract_label = "Выход %02d",
    hud_destination_label = "Точк. Назн. %02d",
    hud_extract_countdown = "Выход через:",
    hud_transit_countdown = "Переход через:",
    hud_redeploy_notice = "Вы будете высажены снова через %d секунд. Удачи!",
 
	-- tool tips
    zone_tool_title = "Инструмент Зоны",
    zone_tool_desc_1 = "ЛКМ чтобы установить углы.",
    zone_tool_desc_2 = "Два угла создадут ограничение зоны.",
    zone_tool_switch_type = "Сменить Тип",
    zone_tool_remove_zone = "Удалить Зону",
    zone_tool_place_zone = "Разместить Зону",
    zone_tool_cancel = "Отмена",
    zone_tool_zone_list = "Список Зон",
    zone_tool_settings = "Настройки",
    zone_tool_mode = "Режим:",
    zone_tool_mode_extract = "Точка Эвакуации",
    zone_tool_mode_transit = "Точка Перехода",
 
	-- tool settings
    tool_settings_title = "Настройки инстр.",
    tool_settings_edit_title = "Редактировать Зону",
    zone_list_title = "Список Зон",
    zone_list_empty = "Для этой карты не определены зоны.",
    zone_list_remove = "Удалить",
    zone_list_edit = "Редактировать",
    zone_default_name = "Зона %d",
    destination_default_name = "Точка Назначения %d",
    destination_none = "Нет доступных точек назначения",
 
	-- zone settings
    zone_field_name = "Название Зоны",
    zone_field_mode = "Режим",
    zone_mode_extract = "Точка Эвакуации",
    zone_mode_transit = "Точка Перехода",
    zone_field_is_destination = "Только Точка Назначения",
    zone_field_transfer_to_destination = "Направиться к Точке Назначения",
    zone_field_destination = "Зона Точки Назначения",
    zone_destination_only_notice = "Эта зона ведёт только к точке назначения и не отображается в списке выходов и проверках эвакуации.",
    zone_field_extract_time = "Время Эвакуации (Секунды)",
    zone_field_open_time = "Задержка Открытия (Секунды)",
    zone_field_close_time = "Задержка Закрытия (Секунды)",
    zone_field_usec = "Доступно для USEC",
    zone_field_bear = "Доступно для BEAR",
    zone_field_scav = "Доступно для Диких",
    zone_field_one_time = "Одноразовый Выход",
    zone_field_max_players = "Макс. игроков",
    zone_field_conditions = "Условия Выхода",
    zone_field_coop = "Совместный выход",
    zone_field_health_below = "Здоровье Ниже",
    zone_field_health_above = "Здоровье Выше",
    zone_field_armor_below = "Броня Ниже",
    zone_field_armor_above = "Броня Выше",
    zone_field_level_below = "Уровень Ниже",
    zone_field_level_above = "Уровень Выше",
    zone_field_highlight = "Подсветка",
 
	--zone settings desc
    zone_desc_name = "Задает имя, отображаемое для этой зоны в списках эвакуации и подсказках.",
    zone_desc_mode = "Изменяет тип зоны. Точки эвакуации отображаются в списке эвакуации; точки перехода показываются как точки назначения/перехода.",
    zone_desc_is_destination = "Помечает точку перехода как точку назначения. Она не отображается в списке эвакуации и не запускает эвакуацию или переход.",
    zone_desc_transfer_to_destination = "После завершения этой точки перехода следующая точка появления игрока будет перенесена в выбранную точку назначения.",
    zone_desc_destination = "Выбирает точку перехода, помеченную как «только точка назначения».",
    zone_desc_extract_time = "Время (в секундах), которое игрок должен находиться в зоне для завершения эвакуации.",
    zone_desc_open_time = "Через сколько секунд после начала рейда зона открывается. 0 — открыта сразу.",
    zone_desc_close_time = "Через сколько секунд после начала рейда зона закрывается. 0 — не закрывается автоматически.",
    zone_desc_usec = "Разрешает использование зоны игрокам USEC. Принадлежность к фракции не зависит от основного переключателя условий эвакуации.",
    zone_desc_bear = "Разрешает использование зоны игрокам BEAR. Принадлежность к фракции не зависит от основного переключателя условий эвакуации.",
    zone_desc_scav = "Разрешает использование зоны Диким. Принадлежность к фракции не зависит от основного переключателя условий эвакуации.",
    zone_desc_one_time = "Помечает зону как использованную после успешной эвакуации и включает ограничение на максимальное число игроков.",
    zone_desc_max_players = "Ограничивает количество игроков, которые могут эвакуироваться одновременно из одноразовой зоны. Активно только при включенной одноразовой эвакуации.",
    zone_desc_conditions = "Главный переключатель. При отключении все условия эвакуации ниже игнорируются сервером.",
    zone_desc_coop = "Требует минимум одного ЧВК (USEC или BEAR) и одного Дикого в зоне. Два ЧВК или два Дикого не подходят.",
    zone_desc_health_below = "Требует, чтобы здоровье игрока было ниже указанного значения. Нельзя включать вместе с «Здоровье выше».",
    zone_desc_health_above = "Требует, чтобы здоровье игрока было ниже указанного значения. Нельзя включать вместе с «Здоровье ниже».",
    zone_desc_armor_below = "Требует, чтобы броня игрока была ниже указанного значения. Нельзя включать вместе с «Броня выше».",
    zone_desc_armor_above = "Требует, чтобы броня игрока была ниже указанного значения. Нельзя включать вместе с «Броня ниже».",
    zone_desc_level_below = "Требует, чтобы уровень игрока был ниже указанного значения. Нельзя включать вместе с «Уровень выше».",
    zone_desc_level_above = "Требует, чтобы уровень игрока был ниже указанного значения. Нельзя включать вместе с «Уровень ниже».",
    zone_desc_highlight = "Управляет подсветкой зоны в мире с помощью полупрозрачного отображения для визуальной проверки.",
 
    error_cancel_opposite_condition = "Сначала отключите противоположное условие",
 
	-- notify
    notify_zone_removed = "Зона '%s' удалена!",
    notify_zone_renamed = "Зона переименована в '%s'.",
    notify_zone_reset_used = "Зона '%s' снова доступна.",
    notify_superadmin_only_set_zones = "Только суперадмин может размещать зоны.",
    notify_corner_1_set = "Угол 1 установлен. Направляйтесь к противополож. углу и кликните снова.",
    notify_zone_saved = "Зона '%s' сохранена!",
    notify_placement_cancelled = "Размещение Отменено.",
    notify_no_zone_crosshair = "Нет зоны в прицеле.",
    admin_only_modify_extraction_data = "[Тарковская Эвакуация] Только суперадмин может редактировать данные выхода.",
    admin_only_modify_raid_time = "[Тарковская Эвакуация] Только суперадмин может редактировать время рейда.",
 
	-- condition
    condition_list_format = "%s - %s",
    condition_closed = "Закрыто",
    condition_not_open = "Ещё не открыто",
    condition_required_faction = "Требуемая фракция: %s",
    condition_need_key = "Необходим ключ",
    condition_need_pay = "Необходима оплата",
    condition_need_pay_amount = "Необходимая оплата: %s",
    condition_need_switch = "Переключатель должен быть включён",
    condition_need_coop = "Нужна совместная эвакуация ЧВК и Диких",
    condition_health_below = "Здоровье ниже %s",
    condition_health_above = "Здоровье выше %s",
    condition_armor_below = "Броня ниже %s",
    condition_armor_above = "Броня выше %s",
    condition_level_below = "Уровень ниже %s",
    condition_level_above = "Уровень выше %s",
 
 
	-- DO NOT touch below
 
 
    no_settings_en = "No settings available",
    developing_en = "Working In Progress!",
    not_subscribed_en = "You have not subscribed to this addon!",
 
    language = "!!!language",
	steam_avatar = "!!!steam_avatar",
	extract_time = "!!!extract_time",
    setting_autodeploy = "!!!setting_autodeploy",
	setting_playsound = "!!!setting_autodeploy",
	setting_showmodel = "!!!setting_autodeploy",
    version = "!!!version",
    cmd_deploy = "!!!cmd_deploy",
    cmd_settings = "!!!cmd_settings",
    cmd_players = "!!!cmd_players",
    cmd_deploy_all = "!!!cmd_deploy_all",
    map_hint_ok = "!!!map_hint_ok",
    map_hint_fail = "!!!map_hint_fail",
    setting_gamename = "!!!setting_gamename",
    setting_blur = "!!!setting_blur",
    setting_language = "!!!setting_language",
    setting_background = "!!!setting_background",
    setting_logo_opacity = "!!!setting_logo_opacity",
    setting_overlay = "!!!setting_overlay",
    setting_show_on_join = "!!!setting_show_on_join",
    setting_show_on_respawn = "!!!setting_show_on_respawn",
    setting_respawn_on_deploy = "!!!setting_respawn_on_deploy",
	btn_cancel = "!!!btn_cancel",
 
--[[
	extract_time = "Extract Time:",
    steam_avatar = "Steam\nAvatar",
    language = "Language",
 
]]
 
}
