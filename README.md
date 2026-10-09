# Marschpad – Musiker-App

Die Musiker-App verbindet das Notenpult des Musikvereins Scharrel mit den
Musikerinnen und Musikern. Nach Auswahl von Instrument und Stimme empfängt sie
die Steuersignale des Dirigenten, lädt passende Noten-PDFs und zeigt diese im
integrierten PDF-Viewer an. Bereits geladene Stücke stehen für die Offline-
Vorbereitung zur Verfügung. Die Oberfläche unterstützt helle und dunkle
Darstellung.

## Funktionen

- Einrichtung und lokale Speicherung von Instrument, Stimme und Darstellung
- Echtzeitverbindung zum Notenserver mit automatischer Wiederverbindung
- Automatischer Download der zum Stück, Instrument und zur Stimme passenden PDF
- Offline-Notenliste, Suche und integrierter PDF-Viewer
- Anzeige von Serverstatus, Wartungshinweisen und Update-Mitteilungen
- Automatische lokale Verbindung zum Dirigenten-Hotspot bei Serverausfall
- Android-Updates mit Prüfung von Version, Paketkennung und APK-Signatur

## Verbindung und Noten

Die App registriert sich über `wss://notenserver.mattis-westerhoff.de` mit der
Kennung `musiker_application` (kanonische Serverkennung:
`musiker_app`). Die Notenliste wird über `GET /api/notes` geladen. Einzelne
PDFs kommen über `GET /api/notes/<relativer-pfad>` vom Notenserver-Proxy;
Nextcloud-Zugangsdaten sind nicht in der App enthalten.

Der Proxy ist derzeit nicht durch eine Anmeldung der Apps geschützt. Wer den
Notenserver erreichen kann, kann die bereitgestellten Noten auflisten und
abrufen. Vertrauliche Zugangsdaten gehören ausschließlich in die
Serverkonfiguration bzw. GitHub Actions Secrets.

Dateien werden nach dem Muster `Stück_Instrument_Stimme.pdf` benannt, zum
Beispiel `Marsch_Trompete_1.pdf`. Die Auswahl in der App muss mit Instrument
und Stimmennummer im Dateinamen übereinstimmen. Heruntergeladene PDFs werden im
Anwendungsdatenverzeichnis des Geräts gespeichert.

## Probe ohne Internet

Aktiviere **Automatisch lokal verbinden** auf dem Musikerpult und verbinde das
Gerät mit dem Hotspot des Dirigenten-Handys. Die App erkennt den lokalen
Probenserver automatisch, wechselt bei einem Ausfall der Internetverbindung
zu ihm und meldet den Wechsel. Sobald die Internetverbindung zurückkehrt,
schaltet sie automatisch zum Notenserver zurück.

Beim Einschalten von **Automatisch lokal verbinden** lädt die App die auf dem
Notenserver vorhandenen PDFs für das ausgewählte Instrument und die Stimme
herunter. Der Download lässt sich auch unter **Offline-Noten → Synchronisieren**
manuell starten. Die Dateinamen müssen auf
`_<Instrument>_<Stimmennummer>.pdf` enden; nicht jede Stimme ist für jedes
Instrument und jedes Stück hinterlegt. Die Offline-Noten-Seite zeigt an, wenn
keine passenden Dateien auf dem Server gefunden werden. Beim Offlinebetrieb
kann die App keine neuen Dateien abrufen. Der Dirigent muss den
Offline-Fallback ebenfalls einschalten; beide Apps müssen während der Probe
geöffnet und im selben WLAN sein.
Die lokale Sitzung verwendet WebSocket über TCP-Port `8765` und automatische
Erkennung über UDP-Port `8766`. Falls UDP-Erkennung im WLAN gesperrt ist, kann
die Hotspot-IP aus dem Dirigentenpult manuell eingegeben werden.
Die lokale WebSocket-Verbindung ist unverschlüsselt. Nur einem privaten,
passwortgeschützten Hotspot des Dirigenten beitreten, keinem öffentlichen WLAN.

Android gestattet Apps nicht, einem WLAN-Hotspot ohne Systembestätigung
beizutreten. Der WLAN-Schalter in der App öffnet deshalb die Android-
WLAN-Einstellungen. Das Dirigenten-Handy muss den Hotspot manuell einschalten.

## Entwickeln und prüfen

Voraussetzungen: Flutter/Dart gemäß `pubspec.yaml` sowie ein Android-SDK für
Android-Builds.

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run
```

Die Serveradresse und App-Kennung sind in `lib/config/app_config.dart`
hinterlegt. Änderungen müssen mit dem Notenserver und der Dirigenten-App
abgestimmt werden.

## Android-Release und Update-Verteilung

Der GitHub-Actions-Workflow **Android Release** erstellt ein signiertes APK,
prüft Version und Signatur und lädt es in den Nextcloud-Ordner `releases`.
Danach erstellt und testet er einen öffentlichen Nur-Lese-Downloadlink. Für
Octopus-Releases aktualisiert er die Production-Variablen `ApkUrl` und
`NotenServerApiKey`, erstellt den Release `musiker_application` und startet
das Production-Deployment. App-Updates werden vom Notenserver per
`release_announce` bekanntgegeben.

Der Workflow startet per Tag `vX.Y.Z` oder manuell mit einer Version im Format
`X.Y.Z`. Für einen Build und APK-Upload ohne Octopus kann der manuelle Eingang
`deploy_to_octopus` auf `false` gesetzt werden.

Benötigte Repository-Secrets:

- Android-Signierung: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`,
  `KEY_ALIAS`
- Nextcloud-Upload und Freigabe: `NC_USER`, `NC_PASS`
- Octopus-Deployment: `OCTOPUS_API_KEY`, `OCTOPUS_SPACE`
- Server-Releasevariable: `NOTEN_SERVER_API_KEY`

Der Octopus-Schlüssel muss gültig sein und die Projektvariablen ändern sowie
Releases erstellen und deployen dürfen. Der Workflow validiert ihn vor dem
Build, wenn ein Octopus-Deployment angefordert wurde. Der Keystore wird nur
temporär in der CI erzeugt und darf nicht eingecheckt oder in Logs ausgegeben
werden.

## Projektstruktur

- `lib/musician_setup.dart` – Instrument- und Stimmenauswahl
- `lib/musician_page.dart` – Musikerpult, Status und Steuersignale
- `lib/offline_practice_page.dart` – lokal gespeicherte Noten und PDF-Viewer
- `lib/services/` – Notenserver-Proxy, Download und Updateprüfung
- `lib/theme/app_theme.dart` – gemeinsames helles und dunkles Designsystem
- `android/` – Android-App und Release-Signierung
- `.github/workflows/release.yml` – signierter Build und Verteilung

## Lizenz

Interne Nutzung – Musikverein Scharrel. Alle Rechte vorbehalten.
