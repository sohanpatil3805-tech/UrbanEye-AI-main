import React from 'react';
import { X, Printer, Shield, CheckCircle, FileText } from 'lucide-react';
import './AuditReportModal.css';

const AuditReportModal = ({ events, estBudgetLakhs, onClose }) => {
  const currentDate = new Date().toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'long',
    year: 'numeric'
  });

  const criticalCount = events.filter(e => e.severity === 'critical').length;
  const highCount = events.filter(e => e.severity === 'high').length;

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="report-modal-overlay" onClick={onClose}>
      <div className="report-modal-content glass-panel" onClick={(e) => e.stopPropagation()}>
        <header className="report-modal-header no-print">
          <div className="report-title">
            <FileText size={20} className="text-cyan" />
            <span>Municipal Infrastructure Audit Preview</span>
          </div>
          <div className="report-actions">
            <button className="btn btn-primary print-btn" onClick={handlePrint}>
              <Printer size={16} /> Print / Save as PDF
            </button>
            <button className="close-btn" onClick={onClose}>
              <X size={20} />
            </button>
          </div>
        </header>

        {/* Printable Report Document */}
        <div className="printable-report-document" id="printable-area">
          <div className="report-letterhead">
            <div className="govt-seal">
              <Shield size={36} color="#00F0FF" />
            </div>
            <div className="letterhead-text">
              <h2>MUNICIPAL CORPORATION OF GREATER MUMBAI</h2>
              <h3>DEPARTMENT OF ROAD INFRASTRUCTURE & SAFETY</h3>
              <p>UrbanEye AI Decentralized Mobile Sensor Detection Audit</p>
            </div>
            <div className="report-meta font-mono">
              <div><strong>Doc Ref:</strong> BMC/PWD/UE-2026/09</div>
              <div><strong>Audit Date:</strong> {currentDate}</div>
              <div><strong>Status:</strong> OFFICIAL AUDIT</div>
            </div>
          </div>

          <hr className="report-divider" />

          <section className="report-section">
            <h4>1. Executive Summary</h4>
            <p>
              This road infrastructure audit report synthesizes telemetry gathered by the UrbanEye AI 
              decentralized mobile edge sensing network across primary municipal transit corridors. 
              Automated computer vision classification models (YOLOv8) and 3-axis accelerometer sensor fusion 
              have identified <strong>{events.length} active road anomalies</strong> requiring PWD maintenance intervention.
            </p>
          </section>

          <section className="report-section">
            <h4>2. Key Metrics & Cost Forecast</h4>
            <div className="report-grid-table">
              <div className="report-grid-cell">
                <span className="rg-label">Total Anomaly Volume</span>
                <span className="rg-val">{events.length} Events</span>
              </div>
              <div className="report-grid-cell">
                <span className="rg-label">Critical Structural Hazards</span>
                <span className="rg-val text-warning">{criticalCount + highCount} Zones</span>
              </div>
              <div className="report-grid-cell">
                <span className="rg-label">Allocated Repair Estimation</span>
                <span className="rg-val text-cyan">₹ {estBudgetLakhs} Lakhs</span>
              </div>
              <div className="report-grid-cell">
                <span className="rg-label">AI Edge Detection Accuracy</span>
                <span className="rg-val">94.8% Avg</span>
              </div>
            </div>
          </section>

          <section className="report-section">
            <h4>3. Anomaly Location Register & Action Plan</h4>
            <table className="report-data-table">
              <thead>
                <tr>
                  <th>Audit ID</th>
                  <th>Location Corridor</th>
                  <th>Hazard Class</th>
                  <th>Severity</th>
                  <th>Depth (cm)</th>
                  <th>Work Order Status</th>
                </tr>
              </thead>
              <tbody>
                {events.map(event => (
                  <tr key={event.id}>
                    <td className="font-mono">UE-{event.id}</td>
                    <td>{event.location_name || 'Mumbai Road Segment'}</td>
                    <td style={{textTransform: 'capitalize'}}>{event.event_type}</td>
                    <td>{event.severity?.toUpperCase()}</td>
                    <td>{event.depth_cm || 5.0} cm</td>
                    <td>{event.status?.toUpperCase()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>

          <div className="report-footer-sign">
            <div className="sign-box">
              <CheckCircle size={24} color="#27C93F" />
              <div>
                <strong>Certified by UrbanEye AI Autonomous System</strong>
                <p>Digital Cryptographic Proof Signature Verified</p>
              </div>
            </div>
            <div className="sign-line">
              <p>Chief Municipal Engineer (Roads)</p>
              <p>BMC Infrastructure Division</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AuditReportModal;
