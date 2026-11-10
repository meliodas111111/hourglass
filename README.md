# Hourglass — песочные часы с физикой песка

Нативное iOS-приложение: таймер в виде песочных часов, где десятки тысяч песчинок падают по реальной гравитации
(CoreMotion) и рисуются через Metal. Время считается по датам, а физика только показывает его: верхняя колба
пустеет ровно к `endDate` при любом наклоне устройства.

| | |
|---|---|
| Язык / UI | Swift 5.9+, SwiftUI, Metal (`MTKView`) |
| Минимальная ОС | iOS 15. Live Activities — 16.1+, интерактивные виджеты — 17+, AlarmKit — 26+ (`if #available` с фолбэками) |
| Устройства | iPhone, iPad, Mac (Designed for iPad), Apple Vision Pro (Designed for iPad) |
| Данные | Только локально: App Group, JSON + UserDefaults. Без аккаунтов и сервера |
| Языки | en, fr, de, hi, it, ja, ko, pl, pt, ru, zh-Hans, es, tr (String Catalog) |

---

## 1. Сборка

Проект описан в [`project.yml`](project.yml) ([XcodeGen](https://github.com/yonaskolb/XcodeGen)), поэтому
`.xcodeproj` не хранится в репозитории и не создаёт конфликтов при слиянии.

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Hourglass.xcodeproj
```

Нужен Xcode 26 или новее: в нём есть SDK AlarmKit. С Xcode 15/16 проект тоже соберётся — код AlarmKit закрыт
`#if canImport(AlarmKit)`, тогда используются уведомления.

Схема **Hourglass** запускает приложение с локальным `Configuration.storekit`, так что покупку можно проверить без App Store Connect.

### Ядро без Xcode (CI, Linux, Windows + Docker)

Вся платформенно-независимая логика живёт в локальном пакете [`Packages/HourglassCore`](Packages/HourglassCore)
и собирается где угодно:

```bash
cd Packages/HourglassCore && swift test -c release -Xswiftc -enable-testing
```

```bash
docker run --rm -v "$PWD/Packages/HourglassCore:/pkg" -w /pkg swift:5.10-jammy swift test -c release -Xswiftc -enable-testing
```

### Генераторы ресурсов (только Python 3, без зависимостей)

| Скрипт | Что генерирует |
|---|---|
| `Tools/generate_strings.py` | `Shared/Resources/Localizable.xcstrings`, `App/Resources/InfoPlist.xcstrings` (13 языков) |
| `Tools/generate_assets.py` | Звуки сигнала `App/Resources/Sounds/*.wav` (< 30 с), иконка, цвета в `Assets.xcassets` |
| `Tools/generate_motion_fixtures.py` | Трассы `gravity.y` для тестов детектора переворота |

---

## 2. Ручная настройка перед релизом

| # | Что | Где |
|---|---|---|
| 1 | **Team ID** | `project.yml` → `DEVELOPMENT_TEAM` |
| 2 | **Bundle ID** приложения и виджета | `project.yml` → `bundleIdPrefix`, `PRODUCT_BUNDLE_IDENTIFIER` (×3) |
| 3 | **App Group** (одинаковый у обоих таргетов) | `project.yml` (entitlements обоих таргетов) **и** `Shared/AppGroup.swift` → `AppGroup.identifier`. Зарегистрировать в Developer Portal |
| 4 | **Time Sensitive Notifications** capability | Уже есть в entitlements; включить у App ID в Developer Portal |
| 5 | **Product ID покупки «Supporter»** (Non-Consumable) | App Store Connect + `project.yml` → `HGSupporterProductID` + `App/Resources/Configuration.storekit` |
| 6 | **AdMob App ID** | `project.yml` → `GADApplicationIdentifier` (сейчас стоит тестовый ID Google) |
| 7 | **AdMob Banner Unit ID** | `project.yml` → `HGBannerAdUnitID` (сейчас тестовый) |
| 8 | **UMP / GDPR-сообщение** | AdMob → Privacy & messaging: создать и опубликовать сообщение GDPR (и при необходимости US states) |
| 9 | **Firebase** | Положить `GoogleService-Info.plist` в `App/Resources/`. Без этого файла Firebase не инициализируется, и приложение работает дальше |
| 10 | **Crashlytics dSYM** | Скрипт уже есть в post-build; срабатывает только в Release и только при наличии plist |
| 11 | **SKAdNetwork IDs** | Дополнить список из [документации Google](https://developers.google.com/admob/ios/3p-skadnetworks) |
| 12 | **Иконка** | Заменить сгенерированную `AppIcon.png` на дизайнерскую |
| 13 | **Privacy labels** | App Store Connect, см. раздел 6 |

---

## 3. Архитектура

MVVM + сервисы. Композиция собирается в одном месте, в [`AppEnvironment`](App/AppEnvironment.swift).

```
┌──────────────────────────── App target ────────────────────────────┐   ┌──── Widget extension ────┐
│ Views (SwiftUI)                                                     │   │ StatusWidget             │
│  HourglassScreen · Library · TimerEditor · Themes · Paywall · Settings│  │ QuickStartWidget (17+ AI)│
│        │                                                            │   │ HourglassLiveActivity    │
│        ▼                                                            │   └──────────┬───────────────┘
│ ViewModels: HourglassViewModel (координатор) · PersistenceService   │              │
│        │                                                            │              │ App Group
│        ▼                                                            │              │ (snapshot,
│ Services                                                            │              │  Library.json)
│  MotionService ──gravity/flip/shake──▶ HourglassViewModel           │              │
│  SimulationDriver (свой поток) ──frames──▶ SandRenderer (Metal)     │◀─────────────┘
│  AlarmService (AlarmKit │ time-sensitive UNNotification)            │
│  StoreService (StoreKit 2) · AdsService (UMP→ATT→GMA)               │
│  LiveActivityService (ActivityKit) · AnalyticsService (Firebase)    │
└───────────────────────────────┬────────────────────────────────────┘
                                │ import
                    ┌───────────▼─────────────── HourglassCore (SwiftPM, Linux-совместим) ──┐
                    │ TimerEngine · TimerPlan/Phase · TimerSnapshot   ← время = даты          │
                    │ SandSimulation · HourglassGeometry (SDF) · PileGenerator              │
                    │ FlipDetector · ShakeDetector · LowPassFilter                            │
                    │ SavedTimer · LibraryCodec (миграции схемы) · SandTheme                  │
                    └─────────────────────────────────────────────────────────────────────────┘
```

| Сервис | Файл | Ответственность |
|---|---|---|
| **MotionService** | `App/Services/MotionService.swift` | CMDeviceMotion 60 Гц → проекция g на экран + low-pass; `FlipDetector` (только iPhone); `ShakeDetector` |
| **TimerEngine** | `Packages/HourglassCore/.../TimerEngine.swift` | idle → running ⇄ paused → finished; `startDate`, `pausedAccumulated`, `totalDuration`; фазы; переворот |
| **SandSimulation** | `Packages/HourglassCore/.../SandSimulation.swift` | Клеточный автомат, дозирующее горлышко, невидимая коррекция, встряхивание |
| **SimulationDriver** | `App/Rendering/SimulationDriver.swift` | Отдельная последовательная очередь, двойной буфер, без накопления очереди, signpost'ы |
| **Renderer** | `App/Rendering/SandRenderer.swift`, `Shaders.metal` | Текстура сетки → песок, стекло (SDF), рамка; анимация переворота; адаптивный fps |
| **AlarmService** | `App/Services/AlarmService.swift` | AlarmKit (26+) или `.timeSensitive` уведомления на конец каждой фазы |
| **StoreService** | `App/Services/StoreService.swift` | Product, purchase, `Transaction.updates`, `currentEntitlements`, `AppStore.sync()` |
| **PersistenceService** | `App/Services/PersistenceService.swift` + `Shared/AppGroup.swift` | Codable JSON в Application Support (App Group), атомарная запись, миграции |

### Ключевые решения

**Время задают даты, физика его только показывает.**
`elapsed = now − startDate − pausedAccumulated`. Физика получает `TimeSync(expectedSource = ceil(N·remaining/total))`.
За счёт `ceil` в верхней колбе остаётся хотя бы одна песчинка, пока время не вышло, и ровно ноль в момент `endDate`.

**Горлышко работает как дозирующий шлюз.**
Песчинка переходит из колбы-источника в колбу-приёмник только при положительном бюджете
`k = clamp(sourceCount − expectedSource, 0, ∞)`. Из-за этого песок никогда не опережает время.

**Невидимая коррекция.**
Включается, когда песок лежит неподвижно и через горлышко ничего не проходит дольше 8 кадров, или когда
отставание больше допуска. Допуск включает песчинки «в полёте» (≈0,75 с нужного расхода), поэтому падение
песка сразу после переворота коррекцию не запускает. Песчинки берутся с поверхности
кучи, самые дальние от горлышка, и переносятся в струю под горлышком. Обычно это несколько штук за кадр
(для 5-секундного таймера — больше, пропорционально нужному расходу). В последние 0,5 с остаток
распределяется по оставшимся кадрам, а на кадре `endDate` переносится всё.

**Ускорение горлышка.**
Горлышко шириной 3 клетки пропускает ~3 песчинки за подшаг (~510 в секунду). Коротким таймерам нужно больше
(5 с при 11 тыс. песчинок — ~2200/с). Тогда полоса строк вокруг горлышка получает до 4 дополнительных подшагов
на кадр: песок там движется быстрее, струя плотнее, а куча живёт в обычном темпе. Таймеры от 5 секунд в
вертикальном положении идут без коррекции; цена — ~0,1 мс на кадр. При наклоне больше ~30° поток ограничен уже
подачей песка по пологой стенке колбы, и недостающее добирает коррекция.

**Порядок обхода сетки.**
Вдоль доминирующей оси гравитации снизу вверх, поперечное направление чередуется каждый подшаг.
Подшагов `∝ |g|·dt`, поэтому при 60 и 120 Гц песок движется с одинаковой скоростью.

**Угол откоса ~30–35°.**
Смесь диагонального шага (45°, с вероятностью ≈ 0,84) и «шага коня» (2 вбок + 1 вниз, 26,6°, с вероятностью ≈ 0,24).

**Колба.**
SDF с центральной симметрией, ширина горлышка 3 клетки. Стенка воронки всегда круче 45°, чтобы колба
опустошалась до конца (это проверяет тест). Кнопка переворота поворачивает массив клеток на 180°,
и стенки совпадают со стенками.

**Переворот.**
Физический: детектор ждёт |gravity.y| > 0,8 не меньше 300 мс, с гистерезисом 0,65 и cooldown.
Меняется колба-источник, `remaining_new = total − remaining_old`. Текст и кнопки поворачиваются на 180°,
чтобы их можно было читать.
Экранный (кнопка или смена фазы): шейдер анимированно поворачивает колбу с вписыванием в кадр, затем
содержимое сетки поворачивается на 180° — ровно в том кадре, где оно появляется на экране, без «прыжка».

**Восстановление.**
Клетки не сохраняются. По снимку таймера и текущей гравитации `PileGenerator` заново строит устоявшиеся
кучи: конус в приёмнике и воронку в источнике.

**Энергия.**
В фоне `MTKView.isPaused` и CoreMotion полностью остановлены. Пока песок движется — 120/60 fps.
Медленная струя — 30 fps. Песок в покое — 10 fps.

**iPad.**
Интерфейс поворачивается, гравитация проецируется в координаты интерфейса. Жест переворота на iPad выключен,
вместо него кнопка: iPad сам переворачивает UI.
**Mac / Vision Pro / Simulator.**
Датчиков нет — гравитация направлена «вниз», переворот кнопкой, AlarmKit не используется.

### Структура

```
App/                 приложение: AppEnvironment, Services/, Rendering/, ViewModels/, Views/, Resources/
Shared/              код и ресурсы app + widget: AppGroup, интенты, Live Activity attributes, уведомления, HourglassGlyph
Widget/              WidgetKit + Live Activity
UITests/             UI-тесты основных сценариев
Packages/HourglassCore/  ядро + unit-тесты (Linux-совместимо)
Tools/               генераторы ресурсов
```

---

## 4. Тесты и проверка

| Набор | Где | Что покрывает |
|---|---|---|
| `TimerEngineTests` (15) | HourglassCore | старт/пауза/резюм, фон и catch-up, «убийство» приложения (снимок через Codable), переворот в running/paused/idle/finished, двойной переворот, Pomodoro и интервалы, бесконечные повторы, сдвиг фаз после паузы, границы 5 с и 24 ч |
| `SandSyncTests` (10) | HourglassCore | верх пуст к `endDate` при наклоне 0°, 15°, 35°, 60°, 90°, 120°, 150°, 180°, лёжа на столе, при 120 Гц на 5-секундном таймере, при физическом перевороте в середине; песок не опережает время; песчинки сохраняются; стенки симметричны; воронка круче 45°; число песчинок по пресетам |
| `FlipDetectorTests` (5) | HourglassCore | реплей трасс `Fixtures/*.csv` (чистый переворот, двойной, короткий всплеск, частичный наклон, лёжа, старт вверх ногами, дрожание руки), удержание 300 мс, cooldown, встряхивание, low-pass |
| `LibraryTests` (5) | HourglassCore | round-trip, миграция v1 → v2, отказ от будущей схемы, дублирование, темы |
| `PerformanceTests` (1) | HourglassCore | стоимость кадра физики по пресетам (только release) |
| `HourglassUITests` (7) | Xcode | старт/пауза/стоп, 5-секундный таймер до конца, валидация < 5 с, последовательность из библиотеки, Zen, премиум-тема → пейволл, холодный старт |

Свои записи датчиков можно положить в `Fixtures` в формате `t,gy` с именем `name__<N>flips.csv` — тест подхватит их сам.

### Профилирование (Instruments)

- **Time Profiler + Points of Interest.** Каждый шаг физики размечен signpost'ом `Sand Step`
  с количеством перемещений и коррекций. Бюджет — 8 мс при 120 Гц.
  На CI (x86, Docker) кадр стоит 1,5 / 2,1 / 3,2 мс для Performance / Balanced / Quality.
- **Energy Log / Power Profiler.** Проверить, что в покое кадров 10/с, а в фоне нет ни кадров, ни сэмплов CoreMotion.
- **Metal System Trace.** Один full-screen-проход, две текстуры, загрузка RG8 размером W×H×2 байт за кадр (≤ 360 КБ).

Пресет по умолчанию выбирается по объёму RAM и Low Power Mode (`SettingsStore.defaultDensity`). Если CPU
не успевает, можно перенести `SandSimulation.substep` в compute shader: структура данных (плоские `UInt8`)
уже подходит для этого.

---

## 5. Что проверено в этой сессии и что — нет

Проект создан на **Windows без Xcode**, поэтому:

- ✅ `HourglassCore` собран и протестирован в Docker (`swift:5.10-jammy`): **36/36 тестов**, без предупреждений.
- ✅ Все 33 Swift-файла App / Shared / Widget / UITests прошли синтаксический разбор `swiftc -parse`.
- ✅ JSON `.xcstrings`, `.storekit` и plist `PrivacyInfo.xcprivacy` валидны.
- ❌ **Полная компиляция iOS-таргетов, Metal-шейдера, запуск на симуляторе и устройстве и UI-тесты не выполнялись** —
  без iOS SDK это невозможно. Первым делом после `xcodegen generate` соберите проект и прогоните UI-тесты.
  Места, где ошибки вероятнее всего (сторонние и новые API):
  - **AlarmKit** (`AlarmService.scheduleAlarmKit`): сигнатуры `AlarmManager.AlarmConfiguration`,
    `AlarmPresentation.Alert(title:stopButton:)` — сверить с вашей версией SDK.
  - **Google Mobile Ads 12 / UMP 3**: используются Swift-имена без префиксов (`BannerView`, `MobileAds.shared`,
    `ConsentInformation.shared`). При более старых SDK нужны `GAD…` / `UMP…` имена.
  - **`WidgetBundle` с `if #available`** при deployment target iOS 15 — нужен Xcode 14.1+.
  - Layout `SandUniforms` (Swift ↔ Metal) защищён `assert(... == 112)`.

---

## 6. Privacy labels (App Store Connect)

Должны совпадать с [`PrivacyInfo.xcprivacy`](App/Resources/PrivacyInfo.xcprivacy):

| Тип данных | Связаны с пользователем | Трекинг | Цель |
|---|---|---|---|
| Crash Data | Нет | Нет | App Functionality |
| Performance Data | Нет | Нет | App Functionality |
| Product Interaction | Нет | Нет | Analytics |
| Advertising Data | Нет | **Да** (только бесплатная версия, только после согласия ATT/UMP) | Third-Party Advertising |
| Device ID | Нет | **Да** (IDFA, только после «Разрешить» в ATT) | Third-Party Advertising |

Аналитика анонимная: без user ID, без IDFV/IDFA в Firebase (отключено в Info.plist), только грубые бакеты
(например, длительность «5–30m»). Её можно выключить в Настройках. Таймеры, библиотека и настройки
никогда не покидают устройство.

---

## 7. Монетизация

- **Supporter** — одна Non-Consumable покупка. Убирает баннер и открывает темы Rose Quartz и Jade.
- Права проверяются через `Transaction.currentEntitlements` при каждом запуске. Последнее известное состояние
  кэшируется в App Group, поэтому офлайн всё работает. «Восстановить покупки» вызывает `AppStore.sync()`.
  Ошибки магазина показываются понятным текстом (сеть, регион, Screen Time, pending / Ask to Buy).
- Баннер показывается **только** в Библиотеке и Настройках, на экране с колбой рекламы нет.
  Порядок: UMP-согласие → ATT → запуск SDK. Supporter не видит никаких запросов согласия.
