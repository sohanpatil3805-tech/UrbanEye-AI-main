import React from 'react';
import './Footer.css';

const Footer = () => {
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer-content">
          <div className="footer-brand">
            <h3 className="footer-logo">UrbanEye <span className="text-gradient">AI</span></h3>
            <p className="footer-desc">
              Empowering cities with intelligent, decentralized monitoring.
            </p>
          </div>
          <div className="footer-links">
            <div className="link-group">
              <h4>Project</h4>
              <ul>
                <li><a href="https://github.com/sohanpatil3805-tech/UrbanEye-AI-main" target="_blank" rel="noreferrer">GitHub Repo</a></li>
                <li><a href="#features">Features</a></li>
              </ul>
            </div>
          </div>
        </div>
        <div className="footer-bottom">
          <p>&copy; {new Date().getFullYear()} UrbanEye AI. Created for Smart India Hackathon.</p>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
