# UrbanEye AI Backend

Run locally:

```bash
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Swagger docs: `http://localhost:8000/docs`

For a phone on the same Wi-Fi or PC hotspot, replace `localhost` with the PC's
IPv4 address on that network. `0.0.0.0` binds the server to all interfaces; it is
not the address to enter on the phone.

`GET /ping` and the existing `GET /health` return the same health response.
`POST /detect` still accepts multipart `file`, with optional paired `latitude`
and `longitude`. `GET /events` and `POST /events` retain their existing contracts.

Browser CORS permits local website/dashboard origins by default without cookie
credentials. Set `CORS_ALLOW_ORIGINS` to a comma-separated list of allowed origins
to restrict it when deploying (include each origin's scheme and port).
Native Android connectivity depends on the LAN address and firewall, not CORS.
