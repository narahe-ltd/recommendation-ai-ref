// frontend/src/App.js
import React, { useState, useEffect } from 'react';
import axios from 'axios';

function App() {
  const [customerId, setCustomerId] = useState('');
  const [recommendations, setRecommendations] = useState([]);
  const [loading, setLoading] = useState(false);

  const fetchRecommendations = async () => {
    setLoading(true);
    try {
      const response = await axios.get(`http://ml-server:8000/recommendations/${customerId}`);
      setRecommendations(response.data.recommendations);
    } catch (error) {
      console.error('Error fetching recommendations:', error);
    }
    setLoading(false);
  };

  return (
    <div style={{ padding: '20px' }}>
      <h1>Bank Recommendations</h1>
      <div>
        <input
          type="text"
          value={customerId}
          onChange={(e) => setCustomerId(e.target.value)}
          placeholder="Enter Customer ID"
          style={{ marginRight: '10px' }}
        />
        <button onClick={fetchRecommendations} disabled={loading}>
          {loading ? 'Loading...' : 'Get Recommendations'}
        </button>
      </div>
      
      {recommendations.length > 0 && (
        <div style={{ marginTop: '20px' }}>
          <h2>Recommendations:</h2>
          <ul>
            {recommendations.map((rec, index) => (
              <li key={index}>
                Product ID: {rec[0]} - {rec[1]}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

export default App;