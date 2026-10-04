# Marschpad Musiker

Die Musiker-App zeigt empfangene Noten an und kann PDFs für die Offline-Nutzung
herunterladen. Notenlisten und PDF-Dateien werden über den noten-server bezogen;
Nextcloud-Zugangsdaten liegen ausschließlich in der Serverkonfiguration.

Der Notenserver stellt `GET /api/notes` für die PDF-Liste und
`GET /api/notes/<relative-path>` für einzelne PDFs bereit. Der Proxy ist auf
PDFs im Nextcloud-Ordner `noten` begrenzt, aber absichtlich ohne App-Anmeldung:
Jeder, der den Notenserver erreicht, kann diese Noten auflisten und abrufen.
