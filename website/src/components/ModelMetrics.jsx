import React, { useState, useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import { Target, Search, BarChart, AlertTriangle, EyeOff, Activity, RefreshCw } from 'lucide-react';
import ThemeToggle from './ThemeToggle';
import { fetchModelMetrics, fetchConfusionMatrix } from '../services/api';
import './ModelMetrics.css';

// Short abbreviations for confusion matrix headers
const CLASS_SHORT = ['LC', 'TC', 'AC', 'PH'];
const CLASS_COLORS = ['#a97b50', '#5b8dd9', '#38bd78', '#e05c5c'];

const POLL_INTERVAL_MS = 5000;

// ── Heat-map cell colouring ─────────────────────────────────────────────────
function getCellStyle(value, maxVal, isDiagonal) {
  const intensity = Math.min(value / Math.max(maxVal, 1), 1);
  if (isDiagonal) {
    return {
      background: `rgba(56, 189, 120, ${0.08 + intensity * 0.75})`,
      color: intensity > 0.4 ? '#fff' : 'var(--text-primary)',
    };
  }
  if (intensity < 0.04) return {};
  return {
    background: `rgba(224, 92, 92, ${0.06 + intensity * 0.65})`,
    color: intensity > 0.5 ? '#fff' : 'var(--text-primary)',
  };
}

// ── Per-class bar card ──────────────────────────────────────────────────────
function ClassBar({ cls, color }) {
  return (
    <div className="class-bar-card glass-panel">
      <div className="class-bar-name" style={{ color }}>{cls.class}</div>
      <div className="class-bar-stats">
        <span className="stat-chip tp">TP {cls.tp}</span>
        <span className="stat-chip fp">FP {cls.fp}</span>
        <span className="stat-chip fn">FN {cls.fn}</span>
      </div>
      <div className="class-bar-row">
        <span className="class-bar-label">Precision</span>
        <div className="class-bar-track">
          <div className="class-bar-fill prec-fill" style={{ width: `${cls.precision}%`, background: color }} />
        </div>
        <span className="class-bar-pct">{cls.precision}%</span>
      </div>
      <div className="class-bar-row">
        <span className="class-bar-label">Recall</span>
        <div className="class-bar-track">
          <div className="class-bar-fill rec-fill" style={{ width: `${cls.recall}%`, background: color }} />
        </div>
        <span className="class-bar-pct">{cls.recall}%</span>
      </div>
      <div className="class-bar-f1">F1 Score: <strong>{cls.f1}%</strong></div>
    </div>
  );
}

// ── Main component ──────────────────────────────────────────────────────────
const ModelMetrics = () => {
  const [metrics, setMetrics]           = useState(null);
  const [confusionData, setConfusionData] = useState(null);
  const [loading, setLoading]           = useState(true);
  const [confLoading, setConfLoading]   = useState(true);
  const [error, setError]               = useState(null);
  const [lastUpdated, setLastUpdated]   = useState(null);
  const [pulse, setPulse]               = useState(false);
  const abortRef = useRef(null);

  // One-time load of summary metrics
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

  // Live polling of confusion matrix every 5 s
  useEffect(() => {
    const controller = new AbortController();
    abortRef.current = controller;

    const fetchConf = async () => {
      try {
        const data = await fetchConfusionMatrix({ signal: controller.signal });
        setConfusionData(data);
        setLastUpdated(new Date().toLocaleTimeString());
        setPulse(true);
        setTimeout(() => setPulse(false), 600);
      } catch (err) {
        if (err?.name !== 'AbortError') console.error('Confusion fetch error:', err);
      } finally {
        setConfLoading(false);
      }
    };

    fetchConf();
    const id = setInterval(fetchConf, POLL_INTERVAL_MS);

    return () => {
      clearInterval(id);
      controller.abort();
    };
  }, []);

  // Max value in matrix for colour scaling
  const maxMatrixVal = confusionData
    ? Math.max(...confusionData.matrix.flat())
    : 1;

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
            These metrics are mathematically derived in real-time by cracking open our PyTorch YOLO weights and reading the underlying validation data.{' '}
            No fake data. No assumptions. Just mathematical truth.
          </p>
        </div>

        {/* ── Summary metric cards ── */}
        {loading ? (
          <div className="metrics-loader">
            <div className="spinner" />
            <p>Evaluating AI Model Weights...</p>
          </div>
        ) : error ? (
          <div className="metrics-error"><p>{error}</p></div>
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
                  <p className="metric-desc">Derived exactly as (1 - Recall). Mitigated by our decentralised multi-sensor network approach.</p>
                </div>
              </div>
            </div>

            <div className="metrics-pitch glass-panel fade-in-up delay-200">
              <h3>Technical Pitch for Judges</h3>
              <blockquote>
                "We evaluated our model directly on our validation set. We achieved a Precision of {metrics.precision}% and an mAP50 of nearly {Math.round(metrics.map50)}%.{' '}
                While it's not perfect, we specifically tuned our confidence thresholds to prioritise Precision over Recall—meaning we would rather miss a few small cracks than accidentally dispatch a PWD crew for a false alarm.{' '}
                Because our system is decentralised, even with a {metrics.recall}% recall, as multiple cars drive over the same road, the aggregate detection rate approaches 100%."
              </blockquote>
            </div>
          </div>
        ) : null}

        {/* ── Confusion Matrix ── */}
        <div className="confusion-section fade-in-up delay-300">
          <div className="confusion-section-header">
            <div>
              <h2 className="confusion-title">
                <Activity size={22} style={{ verticalAlign: 'middle', marginRight: 8 }} />
                Live <span className="text-gradient">Confusion Matrix</span>
              </h2>
              <p className="confusion-subtitle">
                Seeded from validation metrics in <code>best.pt</code> and updated in real-time with every image processed via the AI detection pipeline.
              </p>
            </div>

            <div className="confusion-live-badge-wrap">
              <span className={`live-dot${pulse ? ' pulse-once' : ''}`} />
              <span className="live-label">LIVE</span>
              {lastUpdated && (
                <span className="last-updated">
                  <RefreshCw size={12} /> {lastUpdated}
                </span>
              )}
            </div>
          </div>

          {confLoading ? (
            <div className="metrics-loader">
              <div className="spinner" />
              <p>Loading confusion matrix...</p>
            </div>
          ) : confusionData ? (
            <>
              {/* Matrix table */}
              <div className="confusion-wrap glass-panel">
                <div className="confusion-axis-label axis-predicted">PREDICTED →</div>
                <div className="confusion-axis-label axis-actual">← ACTUAL</div>

                <div className="confusion-table-scroll">
                  <table className="confusion-table">
                    <thead>
                      <tr>
                        <th className="corner-cell" />
                        {CLASS_SHORT.map((s, j) => (
                          <th key={j} className="col-header" style={{ color: CLASS_COLORS[j] }}>
                            {s}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {confusionData.matrix.map((row, i) => (
                        <tr key={i}>
                          <th className="row-header" style={{ color: CLASS_COLORS[i] }}>
                            {CLASS_SHORT[i]}
                          </th>
                          {row.map((val, j) => (
                            <td
                              key={j}
                              className={`conf-cell${i === j ? ' conf-diagonal' : ''}`}
                              style={getCellStyle(val, maxMatrixVal, i === j)}
                            >
                              <span className="conf-val">{val}</span>
                              {i === j && <span className="conf-tag">TP</span>}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                {/* Legend */}
                <div className="confusion-legend">
                  <span className="legend-item"><span className="legend-dot tp-dot" /> True Positive (correct detection)</span>
                  <span className="legend-item"><span className="legend-dot fp-dot" /> False Positive / Miss-classification</span>
                  <span className="legend-item conf-images-note">
                    Images processed (live): <strong>{confusionData.total_images_processed}</strong>
                  </span>
                </div>
              </div>

              {/* Full class names legend */}
              <div className="class-legend-row">
                {confusionData.classes.map((name, i) => (
                  <span key={i} className="class-legend-chip" style={{ borderColor: CLASS_COLORS[i], color: CLASS_COLORS[i] }}>
                    <strong>{CLASS_SHORT[i]}</strong> = {name}
                  </span>
                ))}
              </div>

              {/* Per-class bars */}
              <div className="per-class-grid">
                {confusionData.per_class.map((cls, i) => (
                  <ClassBar key={cls.class} cls={cls} color={CLASS_COLORS[i]} />
                ))}
              </div>

              {/* Source note */}
              <p className="confusion-source-note">
                📊 Data source: {confusionData.source}
              </p>
            </>
          ) : (
            <div className="metrics-error"><p>Could not load confusion matrix. Is the backend running?</p></div>
          )}
        </div>
      </main>
    </div>
  );
};

export default ModelMetrics;
