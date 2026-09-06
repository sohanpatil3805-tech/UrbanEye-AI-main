import React from 'react';
import ThemeToggle from './ThemeToggle';
import './Navbar.css';

const Navbar = () => {
  return (
    <nav className="navbar glass-panel">
      <div className="container navbar-container">
        <a href="/" className="navbar-logo">
          UrbanEye <span className="text-gradient">AI</span>
        </a>
        
        <ul className="navbar-links">
          <li><a href="#features" className="nav-link">Features</a></li>
          <li><a href="#how-it-works" className="nav-link">How it Works</a></li>
          <li><a href="#about" className="nav-link">About</a></li>
        </ul>

        <div className="navbar-actions">
          <ThemeToggle />
          <a href="/dashboard" className="btn btn-outline">
            Live Dashboard
          </a>
          <a href="/simulator" className="btn btn-primary">
            Mobile App
          </a>
        </div>
      </div>
    </nav>
  );
};

export default Navbar;
