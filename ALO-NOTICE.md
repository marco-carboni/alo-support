# ALO Support: avviso e modifiche rispetto a RustDesk

ALO Support è un fork di **RustDesk 1.5.1** (https://github.com/rustdesk/rustdesk), distribuito con la stessa licenza, **AGPL-3.0**. Il file `LICENCE` e gli avvisi di copyright originali (Purslane Tech Pte. Ltd.) restano invariati.

Codice sorgente completo, come richiesto dall'AGPL-3.0 §13:

- Applicazione: https://github.com/marco-carboni/alo-support
- Sottomodulo `libs/hbb_common` (con le nostre modifiche): https://github.com/marco-carboni/alo-support-hbb-common

Base: tag upstream `1.5.1`. Branch di lavoro: `alo/1.5.1`.

## Modifiche rispetto a upstream

Sottomodulo `libs/hbb_common`:

1. **Server e chiave di fabbrica** (`src/config.rs`): `RENDEZVOUS_SERVERS = ["remote.alo.zone"]` e `RS_PUB_KEY` con la chiave pubblica del nostro server. Nessuna chiave privata nel repository. Il relay predefinito deriva dall'host del server (porta rendezvous + 1, cioè 21117), come già in upstream.
2. **Impostazioni forzate** (`src/config.rs`, `OVERWRITE_SETTINGS`): `approve-mode=click`, `verification-method=use-temporary-password`, `custom-rendezvous-server`, `relay-server` e `key`. Il cliente non può modificarli dall'interfaccia.
3. **Nome applicazione** (`src/config.rs`): `APP_NAME = "ALO Support"`. Di conseguenza il client risulta personalizzato (`is_custom_client()`) e il controllo degli aggiornamenti upstream è disattivato.
4. **Portable senza installazione** (`src/config.rs`, `HARD_SETTINGS`): `disable-installation=Y`.
   Nello stesso blocco: `disable-account=Y` (account nascosto). `BUILTIN_SETTINGS`: `register-device=N` (nessun invio di informazioni sul dispositivo) e `hide-server-settings=Y`.

Applicazione:

5. **Risorse di Windows** (`flutter/windows/runner/Runner.rc`): CompanyName "ALO", FileDescription e ProductName "ALO Support", OriginalFilename `ALO-Support.exe`. Il copyright upstream è mantenuto e preceduto da "Based on RustDesk (AGPL-3.0)".
6. **Barra del titolo** (`flutter/lib/desktop/widgets/tabbar_widget.dart`): mostra il nome dell'applicazione invece di "RustDesk" fisso.
7. **Schermata About** (`flutter/lib/desktop/pages/desktop_setting_page.dart`): link al sorgente del fork e dicitura "Basato su RustDesk (AGPL-3.0)".

8. **Schema `alosupport://`** (`src/common.rs` `get_uri_prefix`, `src/alo_link.rs`, `src/core_main.rs`): il prefisso dei link è `alosupport://` (senza spazio). Su Windows lo schema è registrato per l'utente corrente, senza amministratore, in `HKCU\Software\Classeslosupport` (comando `"<exe>" "%1"`, aggiornato a ogni avvio se l'exe cambia posto). Per rimuoverlo: `reg delete HKCU\Software\Classeslosupport /f`.
9. **Collegamento al ticket Odoo** (`flutter/lib/alo/alo_link.dart`): `alosupport://enroll?u=<base>&t=<token>` e, in alternativa, codice `XXXX-XXXX` digitato nella schermata principale. Richiede conferma dell'utente. Salva `alo-odoo-url` e `alo-device-token` nella configurazione locale utente (`ALO Support_local.toml`). La base Odoo accettata deve essere HTTPS con host `alo.zone` o `*.alo.zone`. Il valore di ripiego per il codice è `kAloDefaultOdooBase` (staging) in un solo punto del sorgente.
10. **Hello ed eventi** (`flutter/lib/alo/alo_link.dart`, `src/alo_link.rs`, ganci in `src/server/connection.rs` e `src/server.rs`): all'avvio (al massimo ogni ora) `POST /hello`; all'accettazione e alla chiusura di una connessione in ingresso `POST /event` con id evento, orario UTC e versione. Coda su disco (`alo-events.json`, massimo 50). Nessun ID del tecnico, IP o altro. Senza collegamento non viene inviato nulla.
11. **Versione ALO** `1.5.1-alo.2` (`ALO_VERSION` in Rust, `kAloVersion` in Dart), mostrata in About e inviata a Odoo.
12. **Traduzioni**: le nuove stringhe sono in inglese con la traduzione italiana in `src/lang/it.rs`.

Nessuna modifica a cifratura, protocollo o autenticazione.

## Icone e immagini

Per Windows l'icona è quella ALO fornita dal proprietario: `res/icon.png`, `res/32x32.png`, `res/64x64.png`, `res/128x128.png`, `res/128x128@2x.png`, `res/icon.ico`, `res/tray-icon.ico`, `flutter/windows/runner/resources/app_icon.ico` e `flutter/assets/icon.svg` (ridisegnata in vettoriale).

Ancora quelli di RustDesk (segnaposto, da sostituire quando si prepara la versione macOS o la documentazione):

- `res/mac-icon.png`, `res/mac-tray-dark-x2.png`, `res/mac-tray-light-x2.png`
- `res/scalable.svg`, `res/logo.svg`, `res/logo-header.svg`, `res/design.svg`, `res/rustdesk-banner.svg`

## Note

- Il collegamento "Privacy Statement" e "Website" nella schermata About puntano ancora a rustdesk.com: non fanno richieste di rete finché l'utente non li apre.
- Il binario distribuito non è firmato dal processo di build: la firma la applica il proprietario con il proprio certificato.
