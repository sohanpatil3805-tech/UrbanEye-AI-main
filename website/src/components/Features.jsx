import React, { useEffect, useRef } from 'react';
import './Features.css';

const Features = () => {
  const sectionRef = useRef(null);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            entry.target.classList.add('visible');
            
            // Add animation classes to children when section is visible
            const title = entry.target.querySelector('.features-header');
            if (title) title.classList.add('swipe-from-left');
            
            const cards = entry.target.querySelectorAll('.feature-card');
            cards.forEach((card, index) => {
              card.classList.add('fade-in-up');
              card.classList.add(`delay-${(index + 1) * 100}`);
            });
            
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.2 }
    );

    if (sectionRef.current) {
      observer.observe(sectionRef.current);
    }

    return () => observer.disconnect();
  }, []);

  const featureList = [
    {
      title: "Real-time Telemetry",
      description: "Stream GPS coordinates directly from mobile devices to the backend server with minimal latency.",
      icon: "📡"
    },
    {
      title: "Smart Event Detection",
      description: "Capture images of road anomalies and process them using our YOLOv8-powered computer vision pipeline.",
      icon: "👁️"
    },
    {
      title: "Live Dashboard",
      description: "Visualize all active sensors and detected events on an interactive map for instant situational awareness.",
      icon: "🗺️"
    }
  ];

  return (
    <section className="features bg-dark" id="features" ref={sectionRef}>
      <div className="container">
        <div className="features-header text-center" style={{ opacity: 0 }}>
          <h2 className="section-title text-gradient">How UrbanEye Works</h2>
          <p className="section-subtitle">
            A comprehensive pipeline from edge detection to municipal dispatch, built for scale and reliability.
          </p>
        </div>
        
        <div className="features-grid">
          {featureList.map((feature, index) => (
            <div key={index} className="feature-card glass-panel" style={{ opacity: 0 }}>
              <div className="feature-icon">{feature.icon}</div>
              <h3 className="feature-title">{feature.title}</h3>
              <p className="feature-desc">{feature.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default Features;
