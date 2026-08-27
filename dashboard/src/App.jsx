import L from 'leaflet'
import { MapContainer, Marker, Popup, TileLayer } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import './App.css'

delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
})

const mockEvents = [
  {
    id: 1,
    type: 'Pothole',
    severity: 'High',
    position: [19.076, 72.8777],
  },
  {
    id: 2,
    type: 'Traffic Congestion',
    severity: 'Medium',
    position: [19.0822, 72.8417],
  },
  {
    id: 3,
    type: 'Road Obstruction',
    severity: 'Low',
    position: [19.033, 72.855],
  },
]

const stats = [
  { label: 'Total Events', value: mockEvents.length },
  { label: 'Active Devices', value: 12 },
  { label: 'High Severity', value: mockEvents.filter((event) => event.severity === 'High').length },
  { label: 'Avg Response Time', value: '8 min' },
]

function App() {
  return (
    <main className="dashboard">
      <header>
        <h1>UrbanEye AI Dashboard</h1>
        <p>Live smart-city event visibility for SIH26124 MVP.</p>
      </header>

      <section className="stats-grid">
        {stats.map((stat) => (
          <article className="stat-card" key={stat.label}>
            <p>{stat.label}</p>
            <h2>{stat.value}</h2>
          </article>
        ))}
      </section>

      <section className="map-panel">
        <h2>Event Map</h2>
        <MapContainer center={[19.076, 72.8777]} zoom={12} scrollWheelZoom className="map-view">
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          {mockEvents.map((event) => (
            <Marker key={event.id} position={event.position}>
              <Popup>
                <strong>{event.type}</strong>
                <br />
                Severity: {event.severity}
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </section>
    </main>
  )
}

export default App
