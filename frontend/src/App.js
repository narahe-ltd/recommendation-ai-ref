import React, { useState, useEffect } from 'react';
import axios from 'axios';

const apiUrl = process.env.REACT_APP_API_BASE_URL || 'http://localhost:8000';
const API_KEY = process.env.REACT_APP_API_KEY || 'your_api_key_here'; // Set in .env

function App() {
  const [customerIds, setCustomerIds] = useState('');
  const [recommendations, setRecommendations] = useState([]);
  const [explanation, setExplanation] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [simulating, setSimulating] = useState(false);

  const api = axios.create({
    baseURL: apiUrl,
    headers: { 'X-API-Key': API_KEY, 'Content-Type': 'application/json' }
  });

  const fetchRecommendations = async (id) => {
    setLoading(true);
    setError(null);
    try {
      console.log('API Base URL:', apiUrl);
      const response = await api.get(`/recommendations/${id}`);
      if (response.data) {
        setRecommendations(response.data.recommendations || []);
        setExplanation(response.data.explanation || '');
      } else {
        setError('No data received from the API');
      }
    } catch (err) {
      setError(err.response?.data?.detail || 'Error fetching recommendations');
    }
    setLoading(false);
  };

  const startSimulation = async () => {
    setSimulating(true);
    setError(null);
    try {
      const customerList = customerIds ? customerIds.split(',').map(id => id.trim()) : null;
      await api.post('/simulate_usage', { customers: customerList, num_events: 10, delay: 2.0 });
    } catch (err) {
      setError(err.response?.data?.detail || 'Error starting simulation');
    }
    setSimulating(false);
  };

  useEffect(() => {
    if (!customerIds) return;
    const firstId = customerIds.split(',')[0].trim();
    fetchRecommendations(firstId);
    const interval = setInterval(() => fetchRecommendations(firstId), 10000);
    return () => clearInterval(interval);
  }, [customerIds]);

  return (
    <div style={{ padding: '20px' }}>
      <h1>Bank Recommendations</h1>
      <div>
        <input
          type="text"
          value={customerIds}
          onChange={(e) => setCustomerIds(e.target.value)}
          placeholder="Enter Customer IDs (comma-separated, e.g., cust001, cust002)"
          style={{ marginRight: '10px', width: '300px' }}
        />
        <button onClick={() => fetchRecommendations(customerIds.split(',')[0].trim())} disabled={loading || !customerIds}>
          {loading ? 'Loading...' : 'Get Recommendations'}
        </button>
        <button 
          onClick={startSimulation} 
          disabled={simulating} 
          style={{ marginLeft: '10px' }}
        >
          {simulating ? 'Simulating...' : 'Simulate Usage'}
        </button>
      </div>
      
      {error && <p style={{ color: 'red' }}>Error: {error}</p>}
      
      {recommendations.length > 0 && (
        <div style={{ marginTop: '20px' }}>
          <h2>Recommendations for {customerIds.split(',')[0].trim()}:</h2>
          <ul>
            {recommendations.map((rec, index) => (
              <li key={index}>
                Product ID: {rec[0]} - {rec[1]}
              </li>
            ))}
          </ul>
          <h3>Why These Recommendations?</h3>
          <p>{explanation}</p>
        </div>
      )}
    </div>
  );
}

export default App;