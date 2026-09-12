import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { Target, Search, BarChart, AlertTriangle, EyeOff } from 'lucide-react';
import ThemeToggle from './ThemeToggle';
import { fetchModelMetrics } from '../services/api';
import './ModelMetrics.css';

const ModelMetrics = () => {
  const [metrics, setMetrics] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const loadMetrics = async () => {
      try {
        const data = await fetchModelMetrics();
        setMetrics(data);
      } catch (err) {
        console.error(err);
        setError('Failed to load metrics from the AI model.');
      } finally {
        setLoading(false);
      }
    };
    loadMetrics();
  }, []);

  return (
    <div className="metrics-page">
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

      <main className="container metrics-main fade-in-up">
        <div className="metrics-header">
          <h1 className="metrics-title">Live <span className="text-gradient">AI Detection Performance</span></h1>
          <p className="metrics-subtitle">
            These metrics are mathematically derived in real-time by cracking open our PyTorch YOLO weights and reading the underlying validation data. 
            No fake data. No assumptions. Just mathematical truth.
          </p>
        </div>

        {loading ? (
          <div className="metrics-loader">
            <div className="spinner"></div>
            <p>Evaluating AI Model Weights...</p>
          </div>
        ) : error ? (
          <div className="metrics-error">
            <p>{error}</p>
          </div>
        ) : metrics ? (
          <div className="metrics-dashboard">
            <div className="metrics-grid">
              
              <div className="metric-card glass-panel highlight-card">
                <div className="metric-icon"><Target size={32} /></div>
                <div className="metric-data">
                  <h3 className="metric-label">Precision</h3>
                  <div className="metric-value">{metrics.precision}%</div>
                  <p className="metric-desc">When the model flags a pothole, it is correct {metrics.precision}% of the time.</p>
                </div>
              </div>

              <div className="metric-card glass-panel highlight-card">
                <div className="metric-icon"><Search size={32} /></div>
                <div className="metric-data">
                  <h3 className="metric-label">Recall (True Positive Rate)</h3>
                  <div className="metric-value">{metrics.recall}%</div>
                  <p className="metric-desc">The model successfully detects {metrics.recall}% of all actual road damage.</p>
                </div>
              </div>

              <div className="metric-card glass-panel">
                <div className="metric-icon"><BarChart size={32} /></div>
                <div className="metric-data">
                  <h3 className="metric-label">mAP@50</h3>
                  <div className="metric-value">{metrics.map50}%</div>
                  <p className="metric-desc">Mean Average Precision at 0.5 IoU. The industry standard benchmark for object detection.</p>
                </div>
              </div>

              <div className="metric-card glass-panel">
                <div className="metric-icon"><AlertTriangle size={32} /></div>
                <div className="metric-data">
                  <h3 className="metric-label">False Discovery Rate</h3>
                  <div className="metric-value">{metrics.fdr}%</div>
                  <p className="metric-desc">Derived exactly as (1 - Precision). Ensures low false alarm rates for maintenance crews.</p>
                </div>
              </div>

              <div className="metric-card glass-panel">
                <div className="metric-icon"><EyeOff size={32} /></div>
                <div className="metric-data">
                  <h3 className="metric-label">False Negative Rate</h3>
                  <div className="metric-value">{metrics.fnr}%</div>
                  <p className="metric-desc">Derived exactly as (1 - Recall). Mitigated by our decentralized multi-sensor network approach.</p>
                </div>
              </div>
              
            </div>

            <div className="metrics-pitch glass-panel fade-in-up delay-200">
              <h3>Technical Pitch for Judges</h3>
              <blockquote>
                "We evaluated our model directly on our validation set. We achieved a Precision of {metrics.precision}% and an mAP50 of nearly {Math.round(metrics.map50)}%. 
                While it's not perfect, we specifically tuned our confidence thresholds to prioritize Precision over Recall—meaning we would rather miss a few small cracks than accidentally dispatch a PWD crew for a false alarm. 
                Because our system is decentralized, even with a {metrics.recall}% recall, as multiple cars drive over the same road, the aggregate detection rate approaches 100%."
              </blockquote>
            </div>
          </div>
        ) : null}
      </main>
    </div>
  );
};

export default ModelMetrics;
