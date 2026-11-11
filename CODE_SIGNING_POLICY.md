# Code signing policy

ALO Support is a fork of [RustDesk](https://github.com/rustdesk/rustdesk) 1.5.1 (AGPL-3.0) with a preset server. The source of every released file is in this repository, branch `alo/1.5.1`.

Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org).

## Team roles

- Committers and reviewers: [marco-carboni](https://github.com/marco-carboni)
- Approvers: [marco-carboni](https://github.com/marco-carboni)

Every release is built from this repository by the workflow `.github/workflows/alo-windows-signpath.yml` on GitHub-hosted runners and submitted to SignPath for signing. Each signing request is approved manually.

## Privacy policy

ALO Support is a remote support tool. When it is running it connects to the ALO server `remote.alo.zone` to register its ID and to relay connections requested by a technician. This is the only server configured by default. The client does not send device information or heartbeats to any server (`register-device` is disabled), and it is configured not to check for updates on rustdesk.com.

Screen content, keyboard and mouse input are sent only during a connection that the person using the computer has accepted with the Accept button. Nothing is sent to any other networked system unless the person operating the program asks for it.

RustDesk's own components are described in the [RustDesk privacy statement](https://rustdesk.com/privacy.html).
