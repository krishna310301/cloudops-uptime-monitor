import { useState, useEffect } from "react";

const API_BASE = process.env.REACT_APP_API_BASE_URL || "https://3c7g55lcd0.execute-api.us-east-1.amazonaws.com/prod";
function App() {
  const [status, setStatus] = useState([]);
  const [urls, setUrls] = useState([]);
  const [newUrl, setNewUrl] = useState("");
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 30000);
    return () => clearInterval(interval);
  }, []);

  const fetchData = async () => {
    try {
      const [statusRes, urlsRes] = await Promise.all([
        fetch(`${API_BASE}/status`),
        fetch(`${API_BASE}/urls`)
      ]);
      const statusData = await statusRes.json();
      const urlsData = await urlsRes.json();
      setStatus(statusData.results || []);
      setUrls(urlsData.urls || []);
    } catch (err) {
      console.error("Failed to fetch:", err);
    } finally {
      setLoading(false);
    }
  };

  const addUrl = async () => {
    if (!newUrl) return;
    try {
      const res = await fetch(`${API_BASE}/urls`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: newUrl })
      });
      const data = await res.json();
      setMessage(data.message);
      setNewUrl("");
      fetchData();
      setTimeout(() => setMessage(""), 3000);
    } catch (err) {
      setMessage("Error adding URL");
    }
  };

  const getStatusColor = (isUp) => isUp ? "#22c55e" : "#ef4444";
  const getStatusText = (isUp) => isUp ? "UP" : "DOWN";

  const upCount = status.filter(s => s.is_up).length;
  const downCount = status.filter(s => !s.is_up).length;

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h1 style={styles.title}>☁️ CloudOps Uptime Monitor</h1>
        <p style={styles.subtitle}>Real-time website availability tracking</p>
      </div>

      <div style={styles.statsRow}>
        <div style={{...styles.statCard, borderColor: "#22c55e"}}>
          <div style={{...styles.statNumber, color: "#22c55e"}}>{upCount}</div>
          <div style={styles.statLabel}>Sites Up</div>
        </div>
        <div style={{...styles.statCard, borderColor: "#ef4444"}}>
          <div style={{...styles.statNumber, color: "#ef4444"}}>{downCount}</div>
          <div style={styles.statLabel}>Sites Down</div>
        </div>
        <div style={{...styles.statCard, borderColor: "#3b82f6"}}>
          <div style={{...styles.statNumber, color: "#3b82f6"}}>{status.length}</div>
          <div style={styles.statLabel}>Total Monitored</div>
        </div>
      </div>

      <div style={styles.card}>
        <h2 style={styles.sectionTitle}>Add URL to Monitor</h2>
        <div style={styles.inputRow}>
          <input
            style={styles.input}
            type="text"
            placeholder="https://example.com"
            value={newUrl}
            onChange={(e) => setNewUrl(e.target.value)}
            onKeyPress={(e) => e.key === "Enter" && addUrl()}
          />
          <button style={styles.button} onClick={addUrl}>
            Add URL
          </button>
        </div>
        {message && <p style={styles.message}>{message}</p>}
      </div>

      <div style={styles.card}>
        <h2 style={styles.sectionTitle}>Live Status</h2>
        {loading ? (
          <p style={styles.loading}>Loading...</p>
        ) : status.length === 0 ? (
          <p style={styles.loading}>No data yet. Wait for next check cycle.</p>
        ) : (
          <table style={styles.table}>
            <thead>
              <tr>
                <th style={styles.th}>Status</th>
                <th style={styles.th}>URL</th>
                <th style={styles.th}>Response Code</th>
                <th style={styles.th}>Latency</th>
                <th style={styles.th}>Last Checked</th>
              </tr>
            </thead>
            <tbody>
              {status.map((site, i) => (
                <tr key={i} style={i % 2 === 0 ? styles.rowEven : styles.rowOdd}>
                  <td style={styles.td}>
                    <span style={{
                      ...styles.badge,
                      backgroundColor: getStatusColor(site.is_up)
                    }}>
                      {getStatusText(site.is_up)}
                    </span>
                  </td>
                  <td style={styles.td}>{site.url}</td>
                  <td style={styles.td}>{site.status_code}</td>
                  <td style={styles.td}>{site.latency_ms}ms</td>
                  <td style={styles.td}>
                    {new Date(site.timestamp).toLocaleTimeString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p style={styles.refresh}>Auto-refreshes every 30 seconds</p>
      </div>

      <div style={styles.card}>
        <h2 style={styles.sectionTitle}>Monitored URLs</h2>
        {urls.length === 0 ? (
          <p style={styles.loading}>No URLs added yet.</p>
        ) : (
          urls.map((url, i) => (
            <div key={i} style={styles.urlItem}>
              🔗 {url}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

const styles = {
  container: {
    minHeight: "100vh",
    backgroundColor: "#0f172a",
    color: "#e2e8f0",
    fontFamily: "'Segoe UI', sans-serif",
    padding: "24px",
    maxWidth: "1000px",
    margin: "0 auto"
  },
  header: {
    textAlign: "center",
    marginBottom: "32px"
  },
  title: {
    fontSize: "2rem",
    fontWeight: "bold",
    color: "#38bdf8",
    margin: 0
  },
  subtitle: {
    color: "#94a3b8",
    marginTop: "8px"
  },
  statsRow: {
    display: "flex",
    gap: "16px",
    marginBottom: "24px"
  },
  statCard: {
    flex: 1,
    backgroundColor: "#1e293b",
    borderRadius: "12px",
    padding: "20px",
    textAlign: "center",
    border: "1px solid",
  },
  statNumber: {
    fontSize: "2.5rem",
    fontWeight: "bold"
  },
  statLabel: {
    color: "#94a3b8",
    marginTop: "4px"
  },
  card: {
    backgroundColor: "#1e293b",
    borderRadius: "12px",
    padding: "24px",
    marginBottom: "24px"
  },
  sectionTitle: {
    fontSize: "1.2rem",
    fontWeight: "600",
    marginBottom: "16px",
    color: "#38bdf8"
  },
  inputRow: {
    display: "flex",
    gap: "12px"
  },
  input: {
    flex: 1,
    padding: "10px 16px",
    borderRadius: "8px",
    border: "1px solid #334155",
    backgroundColor: "#0f172a",
    color: "#e2e8f0",
    fontSize: "0.95rem"
  },
  button: {
    padding: "10px 24px",
    backgroundColor: "#38bdf8",
    color: "#0f172a",
    border: "none",
    borderRadius: "8px",
    fontWeight: "600",
    cursor: "pointer",
    fontSize: "0.95rem"
  },
  message: {
    color: "#22c55e",
    marginTop: "8px"
  },
  table: {
    width: "100%",
    borderCollapse: "collapse"
  },
  th: {
    textAlign: "left",
    padding: "10px 12px",
    color: "#94a3b8",
    borderBottom: "1px solid #334155",
    fontSize: "0.85rem",
    textTransform: "uppercase"
  },
  td: {
    padding: "12px",
    borderBottom: "1px solid #1e293b",
    fontSize: "0.9rem"
  },
  rowEven: { backgroundColor: "#1e293b" },
  rowOdd: { backgroundColor: "#162032" },
  badge: {
    padding: "4px 10px",
    borderRadius: "999px",
    color: "white",
    fontWeight: "600",
    fontSize: "0.8rem"
  },
  refresh: {
    color: "#475569",
    fontSize: "0.8rem",
    marginTop: "12px",
    textAlign: "right"
  },
  loading: {
    color: "#94a3b8"
  },
  urlItem: {
    padding: "10px 12px",
    backgroundColor: "#0f172a",
    borderRadius: "8px",
    marginBottom: "8px",
    fontSize: "0.9rem"
  }
};

export default App;