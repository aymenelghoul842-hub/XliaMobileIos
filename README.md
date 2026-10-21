# XLiaMobile – Flutter

Flutter port of the Ionic/Angular app. **Done:** Config, Login, Drawer, Home, Etat Residents (listes), Previsions (help), CA (feedback), PV (recaptilatif) + PV details (deteilrecap), Etat tiers (invitefriend), Settings (change hotel, change password, language, logout).

## Run

```bash
cd xlia_mobile
flutter create . --org com.arabsoft --project-name xlia_mobile   # generates android/ ios/ ...
dart run tool/setup.dart                                         # allows http:// + INTERNET permission
flutter pub get
dart run flutter_launcher_icons          # launcher icon (XLia "X")
dart run flutter_native_splash:create    # native splash screen
flutter run
```

`flutter create .` only adds the missing platform folders; it keeps our `lib/` and `pubspec.yaml`.

## Structure

```
lib/
  main.dart                 routes + theme
  core/
    prefs.dart              localStorage replacement (SharedPreferences)
    app_config.dart         base URL + request bodies (AppConfigService)
    api_client.dart         POST + timeout + retry
    session.dart            GetDataproce -> session id + dates (one shared in-flight call)
    loader.dart             retry-while-empty reads, procedure runner, stale-load token
    fmt.dart                dates (13-OCT-2026 / dd/MM/yyyy), numbers, hex colors
    charts.dart             LineSeriesChart, PieLegendChart (fl_chart)
    lang.dart               FR/EN translations
  screens/
    splash_screen.dart      startup routing (AuthGuard)
    config_screen.dart      server + hotel config
    login_screen.dart       login flow (user -> md5 login -> hotels -> session)
    drawer_shell.dart       drawer + modules from /api/module/user/{id}
    home_screen.dart        Etat Hotel: tables + charts
    listes_screen.dart      Etat Residents (/menu/listes)
    previsions_screen.dart  Previsions (/menu/help): pie + weekly rooms/pax + compared forecast
    pv_screen.dart          PV (/menu/recaptilatif): period, sales points table, charts
    deteilrecap_screen.dart PV details: articles of one point of sale (pushed from PV)
    tiers_screen.dart       Etat tiers (/menu/invitefriend): unpaid list by third party
    ca_screen.dart          CA (/menu/feedback): turnover line, agency tables, pies
    settings_screen.dart    profile, change hotel, change password, language, logout
    placeholder_screen.dart pages not ported yet
```

## Add the next page

1. Create `lib/screens/xxx_screen.dart`.
2. Add a `case '/menu/xxx':` in `buildPage()` (drawer_shell.dart).

## Not ported yet
Register, forgot-password, dark mode / notifications switches, chatbot/weather on login, and the other drawer pages
(deteilagence (not linked from any Ionic page), arrivals-departures, chiffre...).
