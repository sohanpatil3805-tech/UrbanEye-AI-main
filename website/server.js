import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

let events = [
  {
    id: 1,
    event_type: 'pothole',
    confidence: 0.96,
    severity: 'critical',
    latitude: 19.0657,
    longitude: 72.8686,
    location_name: 'Bandra Kurla Complex Rd, BKC',
    status: 'pending',
    depth_cm: 7.4,
    speed_kmh: 48,
    timestamp: new Date(Date.now() - 1000 * 60 * 15).toISOString(),
    device_id: 'MOB-SENSOR-892',
    telemetry: [
      { t: 0, x: 0.1, y: 0.98, z: 0.15 },
      { t: 1, x: 0.3, y: 1.05, z: 0.22 },
      { t: 2, x: 1.8, y: 3.84, z: 2.91 }, // Impact spike!
      { t: 3, x: 0.4, y: 1.20, z: 0.50 },
      { t: 4, x: 0.1, y: 0.99, z: 0.12 }
    ]
  },
  {
    id: 2,
    event_type: 'pothole',
    confidence: 0.91,
    severity: 'high',
    latitude: 19.0178,
    longitude: 72.8478,
    location_name: 'Dadar TT Circle, Dadar East',
    status: 'dispatched',
    depth_cm: 5.2,
    speed_kmh: 36,
    timestamp: new Date(Date.now() - 1000 * 60 * 42).toISOString(),
    device_id: 'MOB-SENSOR-410',
    telemetry: [
      { t: 0, x: 0.05, y: 1.01, z: 0.08 },
      { t: 1, x: 0.12, y: 1.02, z: 0.14 },
      { t: 2, x: 1.45, y: 2.95, z: 2.10 },
      { t: 3, x: 0.25, y: 1.10, z: 0.35 },
      { t: 4, x: 0.08, y: 0.99, z: 0.10 }
    ]
  },
  {
    id: 3,
    event_type: 'crack',
    confidence: 0.88,
    severity: 'medium',
    latitude: 19.1197,
    longitude: 72.8464,
    location_name: 'S.V. Road, Andheri West',
    status: 'pending',
    depth_cm: 3.1,
    speed_kmh: 52,
    timestamp: new Date(Date.now() - 1000 * 60 * 75).toISOString(),
    device_id: 'MOB-SENSOR-105',
    telemetry: [
      { t: 0, x: 0.02, y: 0.99, z: 0.05 },
      { t: 1, x: 0.40, y: 1.60, z: 0.80 },
      { t: 2, x: 0.85, y: 2.10, z: 1.25 },
      { t: 3, x: 0.15, y: 1.05, z: 0.20 },
      { t: 4, x: 0.01, y: 1.00, z: 0.04 }
    ]
  },
  {
    id: 4,
    event_type: 'speedbreaker',
    confidence: 0.94,
    severity: 'low',
    latitude: 19.0330,
    longitude: 72.8570,
    location_name: 'Dr. Annie Besant Rd, Worli',
    status: 'repaired',
    depth_cm: 0.0,
    speed_kmh: 30,
    timestamp: new Date(Date.now() - 1000 * 60 * 180).toISOString(),
    device_id: 'MOB-SENSOR-771',
    telemetry: [
      { t: 0, x: 0.05, y: 1.00, z: 0.05 },
      { t: 1, x: 0.20, y: 1.40, z: 0.60 },
      { t: 2, x: 0.50, y: 1.85, z: 0.90 },
      { t: 3, x: 0.10, y: 1.02, z: 0.15 },
      { t: 4, x: 0.02, y: 0.98, z: 0.02 }
    ]
  },
  {
    id: 5,
    event_type: 'pothole',
    confidence: 0.97,
    severity: 'critical',
    latitude: 19.0760,
    longitude: 72.8777,
    location_name: 'Western Express Highway, Santa Cruz',
    status: 'pending',
    depth_cm: 8.1,
    speed_kmh: 62,
    timestamp: new Date(Date.now() - 1000 * 60 * 5).toISOString(),
    device_id: 'MOB-SENSOR-990',
    telemetry: [
      { t: 0, x: 0.1, y: 1.0, z: 0.1 },
      { t: 1, x: 0.5, y: 1.3, z: 0.4 },
      { t: 2, x: 2.4, y: 4.5, z: 3.8 }, // Huge shock spike
      { t: 3, x: 0.6, y: 1.4, z: 0.6 },
      { t: 4, x: 0.1, y: 1.0, z: 0.1 }
    ]
  }
];

let idCounter = 6;

app.post('/events', (req, res) => {
  const confidence = req.body.confidence || Math.random() * 0.15 + 0.85;
  const severity = req.body.severity || (confidence > 0.92 ? 'critical' : confidence > 0.88 ? 'high' : 'medium');
  const depth = req.body.depth_cm || (severity === 'critical' ? (Math.random() * 3 + 6).toFixed(1) : (Math.random() * 3 + 3).toFixed(1));

  const newEvent = {
    id: idCounter++,
    event_type: req.body.event_type || 'pothole',
    confidence: parseFloat(confidence),
    severity: severity,
    latitude: parseFloat(req.body.latitude || 19.076),
    longitude: parseFloat(req.body.longitude || 72.8777),
    location_name: req.body.location_name || 'Live Mobile Telemetry Track',
    status: 'pending',
    depth_cm: parseFloat(depth),
    speed_kmh: req.body.speed_kmh || Math.floor(Math.random() * 30 + 35),
    timestamp: new Date().toISOString(),
    device_id: req.body.device_id || `MOB-SIM-${Math.floor(Math.random() * 899 + 100)}`,
    telemetry: req.body.telemetry || [
      { t: 0, x: 0.1, y: 0.98, z: 0.12 },
      { t: 1, x: 0.35, y: 1.15, z: 0.28 },
      { t: 2, x: (Math.random() * 1.5 + 1.8).toFixed(2), y: (Math.random() * 2 + 3).toFixed(2), z: (Math.random() * 2 + 2).toFixed(2) },
      { t: 3, x: 0.3, y: 1.1, z: 0.25 },
      { t: 4, x: 0.08, y: 0.99, z: 0.1 }
    ]
  };

  events.unshift(newEvent); // put newest at top
  res.json(newEvent);
});

app.get('/events', (req, res) => {
  res.json(events);
});

app.patch('/events/:id', (req, res) => {
  const eventId = parseInt(req.params.id);
  const event = events.find(e => e.id === eventId);
  if (event) {
    if (req.body.status) event.status = req.body.status;
    res.json(event);
  } else {
    res.status(404).json({ error: 'Event not found' });
  }
});

const PORT = 8000;
app.listen(PORT, () => {
  console.log(`UrbanEye Mock Backend server running on http://localhost:${PORT}`);
});

