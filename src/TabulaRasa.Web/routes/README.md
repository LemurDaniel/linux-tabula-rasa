# Routes
Pode loads every file here via `Use-PodeRoutes` in `Start-TabulaRasaServer`.

| File | Routes |
| --- | --- |
| `routes.info.ps1` | `GET /api/info`, `GET /api/qr`, `POST /api/console`, `GET /api/diagnostics`, `GET /api/kiosk` (public, console only from localhost) |
| `routes.session.ps1` | `POST`/`DELETE /api/session` (public) |
| `routes.disks.ps1` | `GET /api/disks`, `.../partitions`, `.../browse` |
| `routes.jobs.ps1` | `POST /api/jobs`, `GET`/`DELETE /api/jobs/:id` |
| `routes.replug.ps1` | `POST`/`GET`/`DELETE /api/replug`, `POST /api/replug/confirm` |
