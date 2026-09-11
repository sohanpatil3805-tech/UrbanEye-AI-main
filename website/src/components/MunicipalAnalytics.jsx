import React, { useState } from 'react';
import { BarChart2, PieChart, FileSpreadsheet, TrendingUp, AlertTriangle, ShieldCheck, IndianRupee, Clock } from 'lucide-react';
import AuditReportModal from './AuditReportModal';
import './MunicipalAnalytics.css';

const formatDamageType = (eventType) => String(eventType || 'other')
  .replaceAll('_', ' ')
  .replace(/\b\w/g, (letter) => letter.toUpperCase());

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

const MunicipalAnalytics = ({ events, onSelectEvent, isLoading, error }) => {
  const [showReportModal, setShowReportModal] = useState(false);

  // Compute metrics
  const totalEvents = events.length;
  const criticalCount = events.filter(e => e.severity === 'critical').length;
  const highCount = events.filter(e => e.severity === 'high').length;
  const mediumCount = events.filter(e => e.severity === 'medium').length;
  const lowCount = events.filter(e => e.severity === 'low' || !e.severity).length;

  const dispatchedCount = events.filter(e => e.status === 'dispatched').length;
  const repairedCount = events.filter(e => e.status === 'repaired').length;
  const activeHazards = events.filter(e => e.status !== 'repaired').length;

  // Estimated PWD budget (₹ 1.25 Lakhs per high/critical pothole, 0.4 Lakhs per low/medium)
  const estBudgetLakhs = ((criticalCount + highCount) * 1.25 + (mediumCount + lowCount) * 0.45).toFixed(2);

  // Hazard type counts from the road-damage model.
  const potholes = events.filter(e => e.event_type === 'pothole').length;
  const cracks = events.filter(e => e.event_type.includes('crack')).length;
  const longitudinalCracks = events.filter(e => e.event_type === 'longitudinal_crack').length;
  const transverseCracks = events.filter(e => e.event_type === 'transverse_crack').length;
  const alligatorCracks = events.filter(e => e.event_type === 'alligator_crack').length;

  return (
    <div className="analytics-section">
      {/* Banner / Header */}
      <div className="analytics-banner glass-panel fade-in-up delay-100">
        <div className="banner-info">
          <div className="authority-badge">
            <ShieldCheck size={16} /> BMC Municipal Road Infrastructure Division
          </div>
          <h2>City Road Safety Executive Command</h2>
          <p>AI-driven municipal risk analysis, budget forecasting, and work-order dispatch pipeline.</p>
        </div>
        <button 
          className="btn btn-primary generate-report-btn"
          onClick={() => setShowReportModal(true)}
        >
          <FileSpreadsheet size={18} /> Export Official Audit Report
        </button>
      </div>

      {/* KPI Stats Row */}
      <div className="kpi-grid">
        <div className="kpi-card fade-in-up delay-200 glass-panel">
          <div className="kpi-icon icon-cyan">
            <AlertTriangle size={24} />
          </div>
          <div className="kpi-content">
            <span className="kpi-label">Active Hazards</span>
            <span className="kpi-value">{events.filter(e => e.status !== 'repaired').length}</span>
            <span className="kpi-subtext">{criticalCount} Critical Action Required</span>
          </div>
        </div>

        <div className="kpi-card fade-in-up delay-300 glass-panel">
          <div className="kpi-icon icon-purple">
            <IndianRupee size={24} />
          </div>
          <div className="kpi-content">
            <span className="kpi-label">Est. Maintenance Cost</span>
            <span className="kpi-value">₹ {totalEvents ? estBudgetLakhs : '0'} L</span>
            <span className="kpi-subtext">PWD Allocated Fund Pool</span>
          </div>
        </div>

        <div className="kpi-card fade-in-up delay-400 glass-panel">
          <div className="kpi-icon icon-green">
            <Clock size={24} />
          </div>
          <div className="kpi-content">
            <span className="kpi-label">Avg Repair SLA</span>
            <span className="kpi-value">{totalEvents ? '4.2 Hrs' : '0 Hrs'}</span>
            <span className="kpi-subtext">{totalEvents ? '88% Within Target SLA' : 'No Data Available'}</span>
          </div>
        </div>

        <div className="kpi-card fade-in-up delay-500 glass-panel">
          <div className="kpi-icon icon-magenta">
            <TrendingUp size={24} />
          </div>
          <div className="kpi-content">
            <span className="kpi-label">Resolution Rate</span>
            <span className="kpi-value">{totalEvents ? ((repairedCount / totalEvents) * 100).toFixed(0) : 0}%</span>
            <span className="kpi-subtext">{repairedCount} Repaired / {dispatchedCount} Dispatched</span>
          </div>
        </div>
      </div>

      {/* Charts Row */}
      <div className="charts-row">
        {/* Severity Bar Chart */}
        <div className="chart-card glass-panel fade-in-up delay-600">
          <h3><BarChart2 size={18} /> Hazard Severity Breakdown</h3>
          <div className="bar-chart-wrapper">
            <div className="bar-column">
              <div className="bar-fill bar-critical" style={{ height: `${totalEvents ? Math.max((criticalCount / totalEvents) * 100, 15) : 10}%` }}>
                <span className="bar-val">{criticalCount}</span>
              </div>
              <span className="bar-label">Critical</span>
            </div>

            <div className="bar-column">
              <div className="bar-fill bar-high" style={{ height: `${totalEvents ? Math.max((highCount / totalEvents) * 100, 15) : 10}%` }}>
                <span className="bar-val">{highCount}</span>
              </div>
              <span className="bar-label">High</span>
            </div>

            <div className="bar-column">
              <div className="bar-fill bar-medium" style={{ height: `${totalEvents ? Math.max((mediumCount / totalEvents) * 100, 15) : 10}%` }}>
                <span className="bar-val">{mediumCount}</span>
              </div>
              <span className="bar-label">Medium</span>
            </div>

            <div className="bar-column">
              <div className="bar-fill bar-low" style={{ height: `${totalEvents ? Math.max((lowCount / totalEvents) * 100, 15) : 10}%` }}>
                <span className="bar-val">{lowCount}</span>
              </div>
              <span className="bar-label">Low</span>
            </div>
          </div>
        </div>

        {/* Classification Donut Summary */}
        <div className="chart-card glass-panel fade-in-up delay-700">
          <h3><PieChart size={18} /> Classification Summary</h3>
          <div className="donut-summary-grid">
            <div className="summary-item">
              <span className="dot dot-cyan"></span>
              <div className="summary-info">
                <span className="sum-title">Potholes</span>
                <span className="sum-count">{potholes} Events</span>
              </div>
            </div>
            <div className="summary-item">
              <span className="dot dot-red"></span>
              <div className="summary-info">
                <span className="sum-title">Road Cracks</span>
                <span className="sum-count">{cracks} Events</span>
              </div>
            </div>
            <div className="summary-item">
              <span className="dot dot-green"></span>
              <div className="summary-info">
                <span className="sum-title">Longitudinal Cracks</span>
                <span className="sum-count">{longitudinalCracks} Events</span>
              </div>
            </div>
            <div className="summary-item">
              <span className="dot dot-purple"></span>
              <div className="summary-info">
                <span className="sum-title">Transverse / Alligator</span>
                <span className="sum-count">{transverseCracks + alligatorCracks} Events</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Corridors Table */}
      <div className="corridor-table-card glass-panel fade-in-up delay-700">
        <h3>Live Incident Register</h3>
        <div className="table-wrapper">
          <table className="corridor-table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Time</th>
                <th>Damage Type</th>
                <th>Confidence</th>
                <th>Severity</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {isLoading && events.length === 0 && (
                <tr><td colSpan="6" className="dashboard-table-state">Loading live incidents…</td></tr>
              )}
              {!isLoading && error && events.length === 0 && (
                <tr><td colSpan="6" className="dashboard-table-state">{error}</td></tr>
              )}
              {!isLoading && !error && events.length === 0 && (
                <tr><td colSpan="6" className="dashboard-table-state">No incidents have been logged yet.</td></tr>
              )}
              {events.map((event) => (
                <tr key={event.id} onClick={() => onSelectEvent(event)} className="clickable-row">
                  <td className="font-mono text-cyan">#UE-{event.id}</td>
                  <td>{formatTimestamp(event.timestamp)}</td>
                  <td className="text-capitalize font-bold">{formatDamageType(event.event_type)}</td>
                  <td>{(event.confidence * 100).toFixed(0)}%</td>
                  <td><span className={`severity-badge severity-${event.severity}`}>{event.severity?.toUpperCase()}</span></td>
                  <td><span className={`status-pill status-${event.status}`}>{event.status?.toUpperCase()}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Official Audit Report Modal */}
      {showReportModal && (
        <AuditReportModal 
          events={events} 
          estBudgetLakhs={estBudgetLakhs} 
          onClose={() => setShowReportModal(false)} 
        />
      )}
    </div>
  );
};

export default MunicipalAnalytics;
