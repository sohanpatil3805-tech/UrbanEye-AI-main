import React, { useState, useEffect, useRef } from 'react';
import L from 'leaflet';
import { MapContainer, Marker, Popup, TileLayer } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { Link } from 'react-router-dom';
import { MapPin, BarChart2, Bell, AlertTriangle, Cpu, Layers, Sun, Moon, Shield, Zap, Wrench, CheckCircle } from 'lucide-react';
import AiModal from './AiModal';
import MunicipalAnalytics from './MunicipalAnalytics';
import ThemeToggle from './ThemeToggle';
import { getEvents, hasValidCoordinates } from '../services/api';
import './Dashboard.css';

delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

const timeAgo = (dateStr) => {
  const date = new Date(dateStr);
  if (!dateStr || Number.isNaN(date.getTime())) return 'Unknown time';
  const diff = Math.floor((Date.now() - date.getTime()) / 60000);
  if (diff < 1) return 'Just now';
  if (diff < 60) return `${diff} min ago`;
  return `${Math.floor(diff / 60)} hrs ago`;
};

const formatTimestamp = (timestamp) => {
  const date = new Date(timestamp);
  if (!timestamp || Number.isNaN(date.getTime())) return 'Unknown time';

  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};

const formatDamageType = (eventType) => String(eventType || 'other')
  .replaceAll('_', ' ')
  .replace(/\b\w/g, (letter) => letter.toUpperCase());

const getMarkerIcon = (event) => {
  const colors = {
    critical: '#ef4444',
    high: '#f97316',
    medium: '#eab308',
    low: '#22c55e',
  };
  const color = colors[event.severity] || colors.low;

  return L.divIcon({
    className: 'custom-map-marker',
    html: `<div style="background-color: ${color}; width: 14px; height: 14px; border-radius: 50%; border: 2px solid white; box-shadow: 0 0 4px rgba(0,0,0,0.4);"></div>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  });
};

const Dashboard = () => {
  const [events, setEvents] = useState([]);
  const [isLive, setIsLive] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState('map');
  const [selectedEvent, setSelectedEvent] = useState(null);
  const [liveAlert, setLiveAlert] = useState(null);
  const [mapTheme, setMapTheme] = useState(() => localStorage.getItem('urbaneye_map_theme') || 'light');

  const previousEventIds = useRef(new Set());

  useEffect(() => {
    const controller = new AbortController();
    let isMounted = true;

    const fetchEvents = async () => {
      try {
        const data = await getEvents({ signal: controller.signal });
        if (!isMounted) return;

        const newCriticalEvent = previousEventIds.current.size
          ? data.find((event) => (
            event.severity === 'critical' && !previousEventIds.current.has(event.id)
          ))
          : null;

        setEvents(data);
        setIsLive(true);
        setError('');
        if (newCriticalEvent) setLiveAlert(newCriticalEvent);
        previousEventIds.current = new Set(data.map((event) => event.id));
      } catch (requestError) {
        if (requestError?.name === 'AbortError' || !isMounted) return;
        setIsLive(false);
        setError('Live incident data is temporarily unavailable. Please try again shortly.');
      } finally {
        if (isMounted) setIsLoading(false);
      }
    };

    fetchEvents();
    const interval = setInterval(fetchEvents, 15_000);
    return () => {
      isMounted = false;
      controller.abort();
      clearInterval(interval);
    };
  }, []);

  const handleMapThemeToggle = (mode) => {
    setMapTheme(mode);
    localStorage.setItem('urbaneye_map_theme', mode);
  };

  const handleUpdateStatus = () => {
    setError('Incident status updates are not available from the backend yet.');
  };

  const criticalEvents = events.filter(e => e.severity === 'critical').length;
  const potholeCount = events.filter(e => e.event_type === 'pothole').length;
  const crackCount = events.filter(e => e.event_type.includes('crack')).length;
  const mapEvents = events.filter(hasValidCoordinates);

  const mapTileUrl = mapTheme === 'light'
    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}'
    : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  return (
    <div className="dashboard-page">
      {/* Real-time Alert Toast Notification */}
      {liveAlert && (
        <div className="live-alert-toast animate-slide-down">
          <div className="alert-content">
            <div className="alert-icon-pulse"><AlertTriangle size={22} /></div>
            <div className="alert-text">
              <strong>🚨 CRITICAL HAZARD DETECTED IN REAL-TIME</strong>
              <p>{formatDamageType(liveAlert.event_type)} recorded by {liveAlert.source}</p>
            </div>
          </div>
          <div className="alert-actions">
            <button 
              className="btn btn-sm btn-primary" 
              onClick={() => { setSelectedEvent(liveAlert); setLiveAlert(null); }}
            >
              Inspect Telemetry
            </button>
            <button className="alert-close" onClick={() => setLiveAlert(null)}>✕</button>
          </div>
        </div>
      )}

      {/* Navigation Header */}
      <nav className="dashboard-navbar glass-panel">
        <div className="container navbar-container">
          <Link to="/" className="navbar-logo" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <Shield size={24} style={{ color: 'var(--accent-primary)' }} />
            UrbanEye <span className="text-gradient">AI</span>
          </Link>
          <div className="tab-navigation">
            <button 
              className={`nav-tab ${activeTab === 'map' ? 'active' : ''}`}
              onClick={() => setActiveTab('map')}
            >
              <MapPin size={16} /> Live Map & Work Orders
            </button>
            <button 
              className={`nav-tab ${activeTab === 'analytics' ? 'active' : ''}`}
              onClick={() => setActiveTab('analytics')}
            >
              <BarChart2 size={16} /> Municipal Command & Analytics
            </button>
          </div>
          <div className="navbar-actions">
            <ThemeToggle />
            <Link to="/simulator" className="btn btn-outline sim-link-btn" target="_blank">
              <Cpu size={16} /> Open Mobile App
            </Link>
            <Link to="/" className="btn btn-outline">Home</Link>
          </div>
        </div>
      </nav>

      <main className="container dashboard-main">
        {/* Header Summary */}
        <header className="dashboard-header animate-fade-in" style={{ padding: '2rem 0' }}>
          <div className="header-flex">
            <div>
              <h1 className="dashboard-title swipe-from-left delay-100" style={{ fontFamily: 'var(--font-main)', display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap', fontSize: '3rem', fontWeight: '900', letterSpacing: '-1px' }}>
                Smart City Infrastructure Monitor
                <div className="system-pill" style={{
                  color: isLive ? 'var(--color-repaired)' : 'var(--color-critical)',
                  background: isLive ? 'rgba(16, 185, 129, 0.12)' : 'rgba(229, 62, 62, 0.12)',
                  border: `1px solid ${isLive ? 'rgba(16, 185, 129, 0.3)' : 'rgba(229, 62, 62, 0.3)'}`
                }}>
                  <span className="pulse-dot" style={{ background: isLive ? 'var(--color-repaired)' : 'var(--color-critical)' }}></span>
                  {isLive ? 'Live' : 'Offline'}
                </div>
              </h1>
              <p className="dashboard-subtitle swipe-from-left delay-200" style={{ fontSize: '1.2rem', marginTop: '1rem', maxWidth: '600px' }}>
                Real-time AI telemetry feed from mobile edge devices for PWD municipal dispatch.
              </p>
            </div>
          </div>
        </header>

        {error && (
          <div className="dashboard-data-message dashboard-error-message" role="alert">
            {error}
          </div>
        )}

        {/* View 1: Live Event Map & Work Orders */}
        {activeTab === 'map' && (
          <div className="tab-view-content">
            {/* Quick Metrics Bar */}
            <section className="stats-grid" style={{ marginBottom: '2rem' }}>
              <div className="stat-card glass-panel stat-card-total tilt-in delay-200">
                <div className="stat-icon-wrapper"><Layers size={20} style={{ color: 'var(--text-secondary)' }} /></div>
                <span className="stat-value">{events.length}</span>
                <span className="stat-label">Total Logged Anomalies</span>
              </div>
              <div className="stat-card glass-panel stat-card-critical tilt-in delay-300">
                <div className="stat-icon-wrapper"><Zap size={20} style={{ color: 'var(--color-critical)' }} /></div>
                <span className="stat-value" style={{ color: 'var(--color-critical)' }}>{criticalEvents}</span>
                <span className="stat-label">Critical Shock Anomalies</span>
              </div>
              <div className="stat-card glass-panel stat-card-pending tilt-in delay-400">
                <div className="stat-icon-wrapper"><Wrench size={20} style={{ color: 'var(--color-pending)' }} /></div>
                <span className="stat-value" style={{ color: 'var(--color-pending)' }}>{potholeCount}</span>
                <span className="stat-label">Pothole Hazards</span>
              </div>
              <div className="stat-card glass-panel stat-card-repaired tilt-in delay-500">
                <div className="stat-icon-wrapper"><CheckCircle size={20} style={{ color: 'var(--color-repaired)' }} /></div>
                <span className="stat-value" style={{ color: 'var(--color-repaired)' }}>
                  {crackCount}
                </span>
                <span className="stat-label">Crack Hazards</span>
              </div>
            </section>

            {/* Map & Live Feed Layout */}
            <div className="map-feed-layout fade-in-up delay-400">
              {/* Map Panel */}
              <section className="map-panel glass-panel">
                <div className="map-panel-header">
                  <div className="map-header-title">
                    <h2><MapPin size={18} className="text-cyan" /> Geographic Anomaly Distribution</h2>
                    <span className="hint-text">Click marker to inspect YOLOv8 telemetry</span>
                  </div>

                  {/* Independent Map Light/Dark Theme Switcher */}
                  <div className="map-theme-switcher">
                    <span className="map-switcher-label"><Layers size={14} /> Map Style:</span>
                    <button 
                      className={`map-theme-btn nav-tab ${mapTheme === 'dark' ? 'active' : ''}`}
                      onClick={() => handleMapThemeToggle('dark')}
                    >
                      <Moon size={12} /> Dark
                    </button>
                    <button 
                      className={`map-theme-btn nav-tab ${mapTheme === 'light' ? 'active' : ''}`}
                      onClick={() => handleMapThemeToggle('light')}
                    >
                      <Sun size={12} /> Light
                    </button>
                  </div>
                </div>

                  <div className="map-container-wrapper" style={{ position: 'relative' }}>
                    <div className="map-legend glass-panel" style={{ position: 'absolute', bottom: '20px', right: '20px', zIndex: 1000, padding: '0.8rem', borderRadius: '12px', fontSize: '0.75rem', display: 'flex', flexDirection: 'column', gap: '0.4rem', fontWeight: 600 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: '#ef4444' }}></span> Critical</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: '#f97316' }}></span> High</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: '#eab308' }}></span> Medium</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: '#22c55e' }}></span> Low</div>
                    </div>
                  <MapContainer center={[19.076, 72.8777]} zoom={12} scrollWheelZoom className="leaflet-map">
                    <TileLayer
                      key={mapTileUrl}
                      attribution='&copy; OpenStreetMap contributors'
                      url={mapTileUrl}
                    />
                    {mapEvents.map((event) => (
                      <Marker key={event.id} position={[event.latitude, event.longitude]} icon={getMarkerIcon(event)}>
                        <Popup className="custom-popup">
                          <div className="popup-card">
                            <strong className="popup-title text-capitalize">{formatDamageType(event.event_type)}</strong>
                            <div className="popup-meta">
                              <span>Confidence: {(event.confidence * 100).toFixed(0)}%</span>
                              <span className={`badge badge-${event.severity}`}>{event.severity.toUpperCase()}</span>
                            </div>
                            <p className="popup-loc">{formatTimestamp(event.timestamp)}</p>
                            <button 
                              className="popup-inspect-btn"
                              onClick={() => setSelectedEvent(event)}
                            >
                              Inspect AI Telemetry & Waveform
                            </button>
                          </div>
                        </Popup>
                      </Marker>
                    ))}
                  </MapContainer>
                  {!isLoading && mapEvents.length === 0 && (
                    <div className="map-empty-state">
                      No mappable incident coordinates are available.
                    </div>
                  )}
                </div>
              </section>

              {/* Side Event Stream Feed */}
              <aside className="feed-panel glass-panel fade-in-up delay-500">
                <div className="feed-header">
                  <h3><Bell size={18} className="text-cyan" /> Live Sensor Stream</h3>
                  <span className="feed-count">{events.length} Events</span>
                </div>
                <div className="feed-list">
                  {isLoading && events.length === 0 && (
                    <div className="dashboard-state-message" role="status">
                      <span className="dashboard-loading-spinner" aria-hidden="true" />
                      Loading live incidents…
                    </div>
                  )}
                  {!isLoading && events.length === 0 && (
                    <div className="dashboard-state-message">No incidents have been logged yet.</div>
                  )}
                  {events.map(event => (
                    <div 
                      key={event.id} 
                      className={`feed-item ${selectedEvent?.id === event.id ? 'active' : ''}`}
                      onClick={() => setSelectedEvent(event)}
                    >
                      <div style={{ display: 'flex', gap: '0.8rem', alignItems: 'center' }}>
                        {/* Thumbnail Mock */}
                        <div style={{ width: '42px', height: '42px', borderRadius: '8px', background: 'var(--bg-tertiary)', border: '1px solid var(--border-color)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                           <AlertTriangle size={18} style={{ color: 'var(--text-secondary)' }} />
                        </div>
                        <div style={{ flex: 1 }}>
                          <div className="feed-item-top">
                            <span className="feed-type text-capitalize" style={{ fontSize: '0.9rem' }}>{formatDamageType(event.event_type)}</span>
                            <span className={`badge badge-${event.severity}`}>{event.severity?.toUpperCase()}</span>
                          </div>
                          <p className="feed-loc">Source: {event.source}</p>
                          <div className="feed-item-bottom">
                            <span className="feed-time">{event.timestamp ? timeAgo(event.timestamp) : 'Just now'} &bull; {(event.confidence * 100).toFixed(0)}% Match</span>
                            <span className={`badge badge-${event.status}`}>{event.status}</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </aside>
            </div>
          </div>
        )}

        {/* View 2: Municipal Analytics */}
        {activeTab === 'analytics' && (
          <MunicipalAnalytics 
            events={events} 
            onSelectEvent={(event) => setSelectedEvent(event)} 
            isLoading={isLoading}
            error={error}
          />
        )}
      </main>

      {/* AI & Sensor Inspection Modal */}
      {selectedEvent && (
        <AiModal 
          event={selectedEvent} 
          onClose={() => setSelectedEvent(null)}
          onUpdateStatus={handleUpdateStatus}
        />
      )}
    </div>
  );
};

export default Dashboard;
