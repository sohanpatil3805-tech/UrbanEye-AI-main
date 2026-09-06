import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import ThemeToggle from './ThemeToggle';
import './Simulator.css';

const Simulator = () => {
  const [status, setStatus] = useState('Idle');
  const [logs, setLogs] = useState([]);

  const addLog = (message) => {
    setLogs((prev) => [message, ...prev].slice(0, 5));
  };

  const triggerEvent = async (type) => {
    setStatus(`Detecting ${type}...`);
    
    // Randomize coordinate slightly around Mumbai for variation
    const lat = 19.076 + (Math.random() - 0.5) * 0.1;
    const lng = 72.8777 + (Math.random() - 0.5) * 0.1;
    
    const payload = {
      event_type: type,
      confidence: 0.94,
      severity: 'critical',
      latitude: lat,
      longitude: lng,
      source: "camera",
      location_name: `Live Sensor Stream (${type.toUpperCase()})`
    };

    try {
      const response = await fetch('http://localhost:8000/events', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload)
      });
      
      if (response.ok) {
        addLog(`Sent ${type} at [${lat.toFixed(3)}, ${lng.toFixed(3)}]`);
        setStatus('Event Sent Successfully');
      } else {
        setStatus('Error sending event');
      }
    } catch (err) {
      console.error(err);
      setStatus('Network Error. Is Backend Running?');
    }

    setTimeout(() => {
      setStatus('Idle');
    }, 2000);
  };

  return (
    <div className="simulator-page">
      <nav className="dashboard-navbar glass-panel">
        <div className="container navbar-container">
          <Link to="/" className="navbar-logo">
            UrbanEye <span className="text-gradient">AI</span>
          </Link>
          <div className="navbar-actions">
            <ThemeToggle />
            <Link to="/dashboard" className="btn btn-outline">Go to Dashboard</Link>
          </div>
        </div>
      </nav>

      <main className="container simulator-main">
        <div className="phone-frame">
          <div className="phone-notch"></div>
          <div className="phone-screen">
            <div className="app-header">
              <h2>UrbanEye Scanner</h2>
              <div className="status-badge {status === 'Idle' ? 'idle' : 'active'}">
                {status}
              </div>
            </div>

            <div className="camera-viewfinder">
              <div className="crosshair"></div>
              <p>Simulating Live Camera Feed...</p>
            </div>

            <div className="app-controls">
              <button className="sim-btn pothole-btn" onClick={() => triggerEvent('pothole')}>
                Report Pothole
              </button>
              <button className="sim-btn traffic-btn" onClick={() => triggerEvent('traffic')}>
                Report Traffic
              </button>
              <button className="sim-btn obstacle-btn" onClick={() => triggerEvent('other')}>
                Report Obstacle
              </button>
            </div>

            <div className="app-logs">
              <h4>Activity Log</h4>
              <ul>
                {logs.length === 0 ? <li>No recent events</li> : null}
                {logs.map((log, i) => (
                  <li key={i}>{log}</li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};

export default Simulator;
