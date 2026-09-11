import React, { useState, useEffect, useRef } from 'react';
import L from 'leaflet';
import { MapContainer, Marker, Popup, TileLayer } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { Link } from 'react-router-dom';
import { MapPin, BarChart2, Bell, AlertTriangle, Cpu, Layers, Sun, Moon, Shield, Zap, Wrench, CheckCircle } from 'lucide-react';
import AiModal from './AiModal';
import MunicipalAnalytics from './MunicipalAnalytics';
import ThemeToggle from './ThemeToggle';
import './Dashboard.css';

delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

const timeAgo = (dateStr) => {
  if (!dateStr) return 'Just now';
  const diff = Math.floor((new Date() - new Date(dateStr)) / 60000);
  if (diff < 1) return 'Just now';
  if (diff < 60) return `${diff} min ago`;
  return `${Math.floor(diff / 60)} hrs ago`;
};

const Dashboard = () => {
  const [events, setEvents] = useState([]);
  const [isLive, setIsLive] = useState(false);
  const [activeTab, setActiveTab] = useState('map');
  const [selectedEvent, setSelectedEvent] = useState(null);
  const [liveAlert, setLiveAlert] = useState(null);
  const [mapTheme, setMapTheme] = useState(() => localStorage.getItem('urbaneye_map_theme') || 'light');

  const getMarkerIcon = (event) => {
    let color = 'var(--text-tertiary)'; // default grey
    if (event.status === 'repaired') {
      color = 'var(--color-repaired)';
    } else if (event.status === 'dispatched') {
      color = 'var(--color-info)';
    } else if (event.severity === 'critical') {
      color = 'var(--color-critical)';
    } else if (event.severity === 'high' || event.severity === 'medium' || event.status === 'pending') {
      color = 'var(--color-pending)';
    }
    
    return L.divIcon({
      className: 'custom-map-marker',
      html: `<div style="background-color: ${color}; width: 14px; height: 14px; border-radius: 50%; border: 2px solid white; box-shadow: 0 0 4px rgba(0,0,0,0.4);"></div>`,
      iconSize: [14, 14],
      iconAnchor: [7, 7]
    });
  };

  const prevEventCount = useRef(0);

  const fetchEvents = async () => {
    try {
      const res = await fetch('http://localhost:8000/events');
      if (res.ok) {
        const data = await res.json();
        setEvents(data);
        setIsLive(true);

        if (prevEventCount.current > 0 && data.length > prevEventCount.current) {
          const newest = data[0];
          setLiveAlert(newest);
        }
        prevEventCount.current = data.length;
      } else {
        setIsLive(false);
      }
    } catch (err) {
      setIsLive(false);
    }
  };

  useEffect(() => {
    fetchEvents();
    const interval = setInterval(fetchEvents, 2000);
    return () => clearInterval(interval);
  }, []);

  const handleMapThemeToggle = (mode) => {
    setMapTheme(mode);
    localStorage.setItem('urbaneye_map_theme', mode);
  };

  const handleUpdateStatus = async (eventId, newStatus) => {
    try {
      const res = await fetch(`http://localhost:8000/events/${eventId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: newStatus })
      });
      if (res.ok) {
        const updated = await res.json();
        setEvents(prev => prev.map(e => e.id === eventId ? updated : e));
        if (selectedEvent && selectedEvent.id === eventId) {
          setSelectedEvent(updated);
        }
      }
    } catch (err) {
      console.error('Failed to update status:', err);
    }
  };

  const criticalEvents = events.filter(e => e.severity === 'critical').length;
  const pendingWorkOrders = events.filter(e => e.status === 'pending').length;

  const mapTileUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';

  return (
    <div className="dashboard-page">
      {/* Real-time Alert Toast Notification */}
      {liveAlert && (
        <div className="live-alert-toast animate-slide-down">
          <div className="alert-content">
            <div className="alert-icon-pulse"><AlertTriangle size={22} /></div>
            <div className="alert-text">
              <strong>🚨 CRITICAL HAZARD DETECTED IN REAL-TIME</strong>
              <p>{liveAlert.event_type?.toUpperCase()} recorded at {liveAlert.location_name || 'Mumbai Telemetry Stream'}</p>
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
                  {isLive ? 'Edge Network Synchronized' : 'Offline'}
                </div>
              </h1>
              <p className="dashboard-subtitle swipe-from-left delay-200" style={{ fontSize: '1.2rem', marginTop: '1rem', maxWidth: '600px' }}>
                Real-time AI telemetry feed from mobile edge devices for PWD municipal dispatch.
              </p>
            </div>
          </div>
        </header>

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
                <span className="stat-value" style={{ color: 'var(--color-pending)' }}>{pendingWorkOrders}</span>
                <span className="stat-label">Pending PWD Work Orders</span>
              </div>
              <div className="stat-card glass-panel stat-card-repaired tilt-in delay-500">
                <div className="stat-icon-wrapper"><CheckCircle size={20} style={{ color: 'var(--color-repaired)' }} /></div>
                <span className="stat-value" style={{ color: 'var(--color-repaired)' }}>
                  {events.filter(e => e.status === 'repaired').length}
                </span>
                <span className="stat-label">Repaired / Certified</span>
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
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: 'var(--color-critical)' }}></span> Critical</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: 'var(--color-pending)' }}></span> High / Pending</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: 'var(--color-info)' }}></span> Dispatched</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}><span style={{ width: '10px', height: '10px', borderRadius: '50%', background: 'var(--color-repaired)' }}></span> Repaired</div>
                    </div>
                  <MapContainer center={[19.076, 72.8777]} zoom={12} scrollWheelZoom className="leaflet-map">
                    <TileLayer
                      key={`${mapTileUrl}-${mapTheme}`}
                      attribution='&copy; OpenStreetMap contributors'
                      url={mapTileUrl}
                      className={mapTheme === 'dark' ? 'map-tiles-dark' : ''}
                    />
                    {events.map((event) => (
                      <Marker key={event.id} position={[event.latitude, event.longitude]} icon={getMarkerIcon(event)}>
                        <Popup className="custom-popup">
                          <div className="popup-card">
                            <strong className="popup-title text-capitalize">{event.event_type}</strong>
                            <div className="popup-meta">
                              <span>Confidence: {(event.confidence * 100).toFixed(0)}%</span>
                              <span className={`status-pill status-${event.status}`}>{event.status?.toUpperCase()}</span>
                            </div>
                            <p className="popup-loc">{event.location_name || 'Mumbai Central Corridor'}</p>
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
                </div>
              </section>

              {/* Side Event Stream Feed */}
              <aside className="feed-panel glass-panel fade-in-up delay-500">
                <div className="feed-header">
                  <h3><Bell size={18} className="text-cyan" /> Live Sensor Stream</h3>
                  <span className="feed-count">{events.length} Events</span>
                </div>
                <div className="feed-list">
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
                            <span className="feed-type text-capitalize" style={{ fontSize: '0.9rem' }}>{event.event_type}</span>
                            <span className={`badge badge-${event.severity}`}>{event.severity?.toUpperCase()}</span>
                          </div>
                          <p className="feed-loc">{event.location_name || 'Mumbai Road Segment'}</p>
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
            onUpdateStatus={handleUpdateStatus} 
            onSelectEvent={(event) => setSelectedEvent(event)} 
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
