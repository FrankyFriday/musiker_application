# Marschpad Musiker

Die Musiker-App zeigt empfangene Noten an und kann PDFs für die Offline-Nutzung
herunterladen. Notenlisten und PDF-Dateien werden über den noten-server bezogen;
Nextcloud-Zugangsdaten liegen ausschließlich in der Serverkonfiguration.

Der Notenserver stellt `GET /api/notes` für die PDF-Liste und
`GET /api/notes/<relative-path>` für einzelne PDFs bereit. Der Proxy ist auf
PDFs im Nextcloud-Ordner `noten` begrenzt, aber absichtlich ohne App-Anmeldung:
Jeder, der den Notenserver erreicht, kann diese Noten auflisten und abrufen.

## Android-Releases

Der Workflow `Android Release` erstellt und prüft ein signiertes APK, lädt es
zu Nextcloud hoch, erzeugt einen öffentlichen Nur-Lese-Downloadlink und
aktualisiert vor dem Deployment die Octopus-Produktionsvariablen. Der APK-Link
ist öffentlich, damit App-Updater und noten-server das APK ohne Nextcloud-
Zugangsdaten herunterladen können.

Folgende GitHub-Actions-Secrets müssen in diesem Repository konfiguriert sein:

- `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`
- `NC_USER`, `NC_PASS`
- `OCTOPUS_API_KEY`, `OCTOPUS_SPACE`
- `NOTEN_SERVER_API_KEY`

`OCTOPUS_API_KEY` muss ein gültiger Octopus-API-Schlüssel mit Berechtigungen zum
Ändern von Projektvariablen sowie zum Erstellen und Deployen von Releases sein.
Der Workflow prüft den Schlüssel vor dem Android-Build. Für einen manuellen
Build ohne Octopus-Deployment kann `deploy_to_octopus` auf `false` gesetzt
werden.
