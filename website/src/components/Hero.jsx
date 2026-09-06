import { Link } from 'react-router-dom';
import './Hero.css';

const Hero = () => {
  return (
    <section className="hero">
      <div className="hero-background"></div>
      <div className="container hero-container">
        <div className="hero-content">
          <div className="badge fade-in-up delay-100">Smart India Hackathon 2026</div>
          <h1 className="hero-title swipe-from-left delay-200">
            Turn Mobile Devices Into <br />
            <span className="text-gradient">Moving City Sensors</span>
          </h1>
          <p className="hero-subtitle swipe-from-left delay-300">
            UrbanEye AI captures GPS and camera inputs, detects road events, and visualizes them on a live dashboard for city monitoring teams. Real-time situational awareness made simple.
          </p>
          <div className="hero-cta fade-in-up delay-400">
            <Link to="/dashboard" className="btn btn-primary btn-lg">Explore Dashboard</Link>
            <Link to="/simulator" className="btn btn-outline btn-lg">Open Mobile Simulator</Link>
          </div>
        </div>
        
        <div className="hero-visual">
          <div className="glass-panel mock-dashboard tilt-in delay-500">
            <div className="mock-header">
              <span className="dot dot-red"></span>
              <span className="dot dot-yellow"></span>
              <span className="dot dot-green"></span>
            </div>
            <div className="mock-body">
              <div className="mock-map">
                <div className="pulse-marker marker-1"></div>
                <div className="pulse-marker marker-2"></div>
                <div className="pulse-marker marker-3"></div>
              </div>
              <div className="mock-stats">
                <div className="stat-card">
                  <span className="stat-value">24</span>
                  <span className="stat-label">Active Sensors</span>
                </div>
                <div className="stat-card">
                  <span className="stat-value">12</span>
                  <span className="stat-label">Live Events</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

export default Hero;
