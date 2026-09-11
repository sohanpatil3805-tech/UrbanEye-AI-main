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
          <li><a href="#features" className="nav-link">Features & How it Works</a></li>
        </ul>

        <div className="navbar-actions">
          <ThemeToggle />
          <a href="/dashboard" className="btn btn-primary">
            Live Dashboard
          </a>
        </div>
      </div>
    </nav>
  );
};

export default Navbar;
