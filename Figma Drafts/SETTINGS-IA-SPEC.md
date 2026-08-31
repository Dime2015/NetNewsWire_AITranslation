# Babel Settings — Figma Information Architecture

## Source boundary

The Settings design keeps the quiet Reeder Classic visual language, but its options come from the current Babel iOS project. The authoritative implementation sources are:

- `iOS/Settings/SettingsViewController.swift`
- `iOS/Settings/Base.lproj/Settings.storyboard`
- `iOS/AppDefaults.swift`
- `iOS/Settings/AddAccountViewController.swift`
- `iOS/Settings/DiscoveryAPIKeysViewController.swift`
- `iOS/Settings/ArticleThemesTableViewController.swift`
- `Shared/Translation/TranslationConfig.swift`
- `Shared/Translation/TranslationModelPickerViewController.swift`
- `Shared/Translation/TranslationAPIKeyViewController.swift`
- `Shared/Translation/AppLanguageController.swift`
- `iOS/DesignKit/NNWAccentPalette.swift`

Dynamic account names, API-key status, model catalog results, installed article themes, iCloud availability, statistics, and localized language lists are represented with safe sample states in Figma. They are not claims about the user's current runtime data.

## Navigation hierarchy

### Settings Home

1. 账户与同步
2. 订阅与发现
3. 文章列表
4. 阅读器
5. 翻译
6. 外观与语言
7. 通知
8. 支持与诊断

### 1. 账户与同步

- iCloud account destination
- Local account destination
- Add Account action
- Sync unread article content toggle
- Secondary pages: Account Detail, Add Account

### 2. 订阅与发现

- Import Subscriptions
- Export Subscriptions
- Add Babel News Feed
- Discovery API configuration status
- Secondary page: Discovery API Keys

### 3. 文章列表

- Sort oldest to newest
- Group by feed
- Refresh clears read articles
- Confirm mark all as read

The disabled Timeline Layout customizer is intentionally omitted because the current iOS source explicitly hides it.

### 4. 阅读器

- Article Theme
- Open links in Babel
- Enable JavaScript
- Enable full-screen articles
- Secondary page: Article Theme

### 5. 翻译

- Translation Model: navigates to a dedicated catalog page
- Translation API Key
- Secondary pages: Translation Model, Translation API

The model page is a vertically scrolling catalog. Its first control is `刷新模型列表`, followed by a dynamic popularity Top 10 and then vendor sections. Every Top 10 model row shows its vendor logo before the model name. Each vendor section also uses the repository's real vendor logo when available and shows exactly three representative popular models. The concrete model names in Figma are prototype data; runtime order and availability come from the refreshed OpenRouter catalog. The API editor includes a secure key field, service base URL, live connection test, and clear-key action.

### 6. 外观与语言

- Color Palette: Automatic, Light, Dark
- Accent Color: Orange, Terracotta, Indigo, Forest, Plum, Graphite
- Interface Language: follow system plus bundled localizations
- Secondary page: Color Palette
- Same-page popovers: Accent Color, Interface Language

### 7. 通知

- Open System Notification Settings
- Feed-specific notification behavior remains attached to account/feed detail, matching the current project structure.

### 8. 支持与诊断

- Error Log
- Activity Log
- Account Stats
- Dinosaurs
- iCloud Storage Stats
- Help
- Forum
- Release Notes
- Bug Tracker
- About Babel

These are destinations or read-only information pages, not settings editors, so additional empty editing mockups are intentionally not created.

## Interaction contract

- Settings Home uses a Close action.
- Ordinary first-level and immediate-choice pages use Back.
- Discovery API Keys, Article Theme, Translation Model, and Translation API use explicit Cancel and Save actions because the current code keeps pending values until confirmation.
- Destructive actions use warning red. Ordinary actions, active switches, and selected checkmarks remain monochrome to preserve the Reeder Classic visual hierarchy.
- Visible control artwork is compact; production interaction targets must remain at least 44 pt.
- Short enumerations use an anchored single-select popover on the same page, following `Reeder screenshots/6.png` and `Reeder screenshots/7.png`: current value and down chevron in the row, selected option marked by a check, selection applied immediately, and the popover dismissed after selection.
- Popovers overlay later rows instead of pushing them downward. The Figma material combines Reeder's compact geometry with an iOS 27-inspired thick-glass surface.
- This pattern applies to article sort, article grouping, link opening behavior, color mode, accent color, and interface language. Translation model is intentionally excluded because its dynamic catalog, refresh action, vendor grouping, and long list require a dedicated page. Booleans remain switches; accounts, credentials, dynamic theme management/import, logs, help, and other destinations keep their existing pages.

## Figma validation

- Page: `03 · Settings` (`110:299`)
- Screen count: 16
- Settings Home category count: 8
- First-level page count: 8
- Secondary editor count: 7
- Canvas: 402 × 874 pt per screen
- Structural overflow: none detected
- Editor-navigation assignment errors: none detected
- Figma render font: Inter fallback; production iOS remains SF Pro
