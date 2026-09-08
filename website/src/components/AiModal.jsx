import React from 'react';
import { X, Cpu, Activity, AlertTriangle, ShieldCheck, MapPin, Layers, Eye } from 'lucide-react';
import './AiModal.css';

const AiModal = ({ event, onClose, onUpdateStatus }) => {
  if (!event) return null;

  const telemetry = Array.isArray(event.telemetry) ? event.telemetry : [];

  // Calculate SVG line paths for Accelerometer X, Y, Z
  const svgWidth = 400;
  const svgHeight = 140;
  const maxVal = 5.0; // scale up to 5g

  const pointsFor = (axis) => telemetry.length > 1 ? telemetry.map((pt, idx) => {
    const x = (idx / (telemetry.length - 1)) * (svgWidth - 40) + 20;
    const y = svgHeight - 20 - ((Number(pt[axis]) || 0) / maxVal) * (svgHeight - 40);
    return `${x},${y}`;
  }).join(' ') : '';

  const pointsX = pointsFor('x');
  const pointsY = pointsFor('y');
  const pointsZ = pointsFor('z');
  const peakY = telemetry.length
    ? Math.max(...telemetry.map((point) => Number(point.y) || 0)).toFixed(2)
    : 'N/A';
  const coordinates = Number.isFinite(event.latitude) && Number.isFinite(event.longitude)
    ? `${event.latitude.toFixed(4)}, ${event.longitude.toFixed(4)}`
    : 'Not available';

  return (
    <div className="ai-modal-overlay" onClick={onClose}>
      <div className="ai-modal-content glass-panel" onClick={(e) => e.stopPropagation()}>
        <header className="ai-modal-header">
          <div className="ai-title-wrap">
            <div className="ai-badge">
              <Cpu size={18} className="ai-icon-pulse" />
              <span>AI Detection Telemetry</span>
            </div>
            <h2>Detection #UE-{event.id}</h2>
          </div>
          <button className="close-btn" onClick={onClose} aria-label="Close modal">
            <X size={20} />
          </button>
        </header>

        <div className="ai-modal-body">
          {/* Left Column: Computer Vision Preview */}
          <div className="cv-viewport-card glass-panel">
            <div className="viewport-header">
              <div className="vp-tag"><Eye size={14} /> Computer Vision Stream</div>
              <div className="conf-chip" style={{
                background: event.confidence > 0.9 ? 'rgba(39, 201, 63, 0.15)' : 'rgba(255, 170, 0, 0.15)',
                color: event.confidence > 0.9 ? '#27C93F' : '#FFAA00'
              }}>
                {(event.confidence * 100).toFixed(1)}% Match
              </div>
            </div>

            <div className="asphalt-canvas">
              {/* Simulated Road Asphalt Background */}
              <div className="asphalt-texture"></div>
              <div className="road-lane-line"></div>

              {/* Bounding Box Visual Overlay */}
              <div className={`bounding-box-overlay severity-${event.severity || 'high'}`}>
                <div className="box-corner tl"></div>
                <div className="box-corner tr"></div>
                <div className="box-corner bl"></div>
                <div className="box-corner br"></div>
                <div className="box-label">
                  <span className="box-class">{event.event_type?.toUpperCase() || 'POTHOLE'}</span>
                  <span className="box-score">{(event.confidence * 100).toFixed(0)}%</span>
                </div>
                <div className="box-crosshair"></div>
              </div>

              <div className="hud-overlay">
                <span className="hud-stat">GPS: {coordinates}</span>
                <span className="hud-stat">Source: {event.source || 'Not reported'}</span>
              </div>
            </div>

            <div className="cv-metrics-row">
              <div className="metric-chip">
                <span className="m-label">Est. Depth</span>
                <span className="m-val">{event.depth_cm ?? 'N/A'}{event.depth_cm != null ? ' cm' : ''}</span>
              </div>
              <div className="metric-chip">
                <span className="m-label">Vehicle Speed</span>
                <span className="m-val">{event.speed_kmh ?? 'N/A'}{event.speed_kmh != null ? ' km/h' : ''}</span>
              </div>
              <div className="metric-chip">
                <span className="m-label">Classification</span>
                <span className="m-val text-capitalize">{event.event_type}</span>
              </div>
            </div>
          </div>

          {/* Right Column: Sensor Waveform & Work-Order Lifecycle */}
          <div className="telemetry-card glass-panel">
            <div className="telemetry-header">
              <h3><Activity size={18} /> 3-Axis Accelerometer Shock Signal</h3>
              <span className="peak-g-chip">Peak Shock: {peakY}g</span>
            </div>

            {/* Custom SVG Waveform Chart */}
            <div className="waveform-container">
              <svg width="100%" height="140" viewBox={`0 0 ${svgWidth} ${svgHeight}`} className="waveform-svg">
                {/* Gridlines */}
                <line x1="0" y1="20" x2={svgWidth} y2="20" stroke="rgba(255,255,255,0.05)" strokeDasharray="4 4" />
                <line x1="0" y1="60" x2={svgWidth} y2="60" stroke="rgba(255,255,255,0.05)" strokeDasharray="4 4" />
                <line x1="0" y1="100" x2={svgWidth} y2="100" stroke="rgba(255,255,255,0.05)" strokeDasharray="4 4" />
                
                {/* Waveform Lines */}
                {telemetry.length > 1 ? (
                  <>
                    <polyline fill="none" stroke="#FF5F56" strokeWidth="2" points={pointsX} opacity="0.8" />
                    <polyline fill="none" stroke="#00F0FF" strokeWidth="2.5" points={pointsY} />
                    <polyline fill="none" stroke="#27C93F" strokeWidth="2" points={pointsZ} opacity="0.8" />
                  </>
                ) : (
                  <text x={svgWidth / 2} y={svgHeight / 2} textAnchor="middle" fill="rgba(255,255,255,0.55)" fontSize="13">
                    Telemetry not reported by backend
                  </text>
                )}
              </svg>

              <div className="legend-row">
                <span className="legend-item"><span className="dot red"></span> X-Axis (Lateral)</span>
                <span className="legend-item"><span className="dot cyan"></span> Y-Axis (Vertical Impact)</span>
                <span className="legend-item"><span className="dot green"></span> Z-Axis (Longitudinal)</span>
              </div>
            </div>

            {/* Details Table */}
            <div className="details-grid">
              <div className="detail-item">
                <span className="d-label"><MapPin size={14} /> Location</span>
                <span className="d-val">{coordinates}</span>
              </div>
              <div className="detail-item">
                <span className="d-label"><AlertTriangle size={14} /> Severity Rating</span>
                <span className={`severity-badge severity-${event.severity}`}>{event.severity?.toUpperCase()}</span>
              </div>
              <div className="detail-item">
                <span className="d-label"><Layers size={14} /> Mobile Sensor ID</span>
                <span className="d-val font-mono">{event.device_id || 'Not reported'}</span>
              </div>
              <div className="detail-item">
                <span className="d-label"><ShieldCheck size={14} /> Verification Status</span>
                <span className={`status-pill status-${event.status}`}>{event.status?.toUpperCase()}</span>
              </div>
            </div>

            {/* Dispatch Action Footer */}
            <div className="modal-action-bar">
              {event.status === 'pending' && (
                <button 
                  className="btn btn-primary dispatch-btn"
                  onClick={() => onUpdateStatus(event.id, 'dispatched')}
                >
                  Dispatch PWD Maintenance Crew
                </button>
              )}
              {event.status === 'dispatched' && (
                <button 
                  className="btn btn-primary resolve-btn"
                  onClick={() => onUpdateStatus(event.id, 'repaired')}
                >
                  Mark as Repaired & Clear Alert
                </button>
              )}
              {event.status === 'repaired' && (
                <div className="repaired-badge font-bold text-gradient">
                  ✓ Repair Certified by City Municipal Board
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AiModal;
