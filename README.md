# UrbanEye AI (SIH26124)

UrbanEye AI is a Smart India Hackathon MVP that turns mobile devices into moving city sensors. The system captures GPS and camera inputs, detects road events, and visualizes them on a web dashboard for city monitoring teams.

## Repository Structure

- `/mobile` – Flutter app scaffold (Login, Home, Live GPS, Camera)
- `/backend` – FastAPI backend with telemetry, upload, and events APIs
- `/dashboard` – React + Vite dashboard with Leaflet map and event stats
- `/docker-compose.yml` – Multi-service local container setup

## Features in this MVP Scaffold

### Mobile App (Flutter)
- Login screen (placeholder flow)
- Home screen navigation
- Live GPS screen placeholder for geolocation streaming
- Camera screen placeholder for media upload integration
- Firebase integration placeholders through environment settings

### Backend (FastAPI)
- `GET /` health endpoint
- `POST /location` for GPS ingestion
- `POST /upload` for image/file uploads
- `POST /events` and `GET /events` for event ingestion + listing
- Pydantic request/response models
- Built-in Swagger docs at `/docs`
- YOLOv8 integration stub for future CV inference
- Firebase publish placeholder service

### Dashboard (React + Vite + Leaflet)
- Statistics cards for quick situational awareness
- Interactive Leaflet map
- Event markers with popup details
- Ready for backend API integration via `VITE_API_BASE_URL`

## Prerequisites

- Python 3.11+
- Node.js 20+
- npm 10+
- Flutter SDK 3.3+ (for mobile app)
- Docker (optional)

## Environment Setup

Copy and customize environment values:

```bash
cp .env.example .env
```

## Run Locally

### 1) Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

API docs: `http://localhost:8000/docs`

### 2) Dashboard

```bash
cd dashboard
npm install
npm run dev
```

Dashboard URL: `http://localhost:5173`

### 3) Mobile (Flutter)

```bash
cd mobile
flutter pub get
flutter run
```

> Note: Flutter SDK is required locally to run the app.

## Run with Docker

```bash
docker compose up --build
```

- Backend: `http://localhost:8000`
- Dashboard: `http://localhost:5173`

## API Contract (Current)

### `POST /location`
Records device location payload.

### `POST /upload`
Accepts an uploaded file and runs YOLOv8 placeholder inference logic.

### `POST /events`
Stores a detected city event and triggers Firebase placeholder publish.

### `GET /events`
Returns all currently in-memory events.

## Firebase Placeholder Notes

Firebase credentials are intentionally left as placeholders in `.env.example`. Add your service account/project details during integration.

## YOLOv8 Stub Notes

The backend currently includes `run_yolov8_stub(...)` in `backend/app/services/detector.py`. Replace this with actual model loading + inference in later iterations.

## Next Suggested Iterations

- Connect Flutter GPS stream to `/location`
- Connect Flutter camera upload to `/upload`
- Persist events to PostgreSQL/Firestore
- Replace map mock data with backend `/events` API polling
- Integrate real YOLOv8 pipeline and confidence filtering
- Add authentication and role-based access controls

## License

This project is licensed under the MIT License.
