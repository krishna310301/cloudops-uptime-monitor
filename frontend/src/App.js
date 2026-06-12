import { useEffect, useMemo, useState } from "react";
import "./App.css";

const API_BASE =
  process.env.REACT_APP_API_BASE_URL || "";
const API_KEY =
  process.env.REACT_APP_API_KEY || "";

const apiHeaders = (headers = {}) => {
  const nextHeaders = { ...headers };

  if (API_KEY) {
    nextHeaders["X-Api-Key"] = API_KEY;
  }

  return nextHeaders;
};

const apiFetch = (path, options = {}) =>
  fetch(`${API_BASE}${path}`, {
    ...options,
    headers: apiHeaders(options.headers),
  });

function App() {
  const [status, setStatus] = useState([]);
  const [urls, setUrls] = useState([]);
  const [newUrl, setNewUrl] = useState("");
  const [loading, setLoading] = useState(true);
  const [adding, setAdding] = useState(false);
  const [deletingUrl, setDeletingUrl] = useState("");
  const [toast, setToast] = useState(null);
  const [error, setError] = useState("");
  const [lastUpdated, setLastUpdated] = useState(null);
  const [apiHealthy, setApiHealthy] = useState(true);

  useEffect(() => {
    fetchData();

    const interval = setInterval(fetchData, 30000);
    return () => clearInterval(interval);
  }, []);

  const showToast = (type, message) => {
    setToast({ type, message });
    setTimeout(() => setToast(null), 3500);
  };

  const fetchData = async () => {
    try {
      setError("");

      if (!API_BASE) {
        throw new Error("REACT_APP_API_BASE_URL is not configured");
      }

      const [statusRes, urlsRes] = await Promise.all([
        apiFetch("/status"),
        apiFetch("/urls"),
      ]);

      if (!statusRes.ok || !urlsRes.ok) {
        throw new Error("API request failed");
      }

      const statusData = await statusRes.json();
      const urlsData = await urlsRes.json();

      setStatus(statusData.results || []);
      setUrls(urlsData.urls || []);
      setApiHealthy(true);
      setLastUpdated(new Date());

    } catch (err) {
      console.error("Failed to fetch dashboard data:", err);
      setError("Unable to load monitoring data. Check API Gateway/Lambda health and try again.");
      setApiHealthy(false);
    } finally {
      setLoading(false);
    }
  };

  const normalizeUrl = (value) => {
    const trimmed = value.trim();

    if (!trimmed) return "";

    if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
      return trimmed;
    }

    return `https://${trimmed}`;
  };

  const isValidUrl = (value) => {
    try {
      const parsed = new URL(value);
      return parsed.protocol === "http:" || parsed.protocol === "https:";
    } catch {
      return false;
    }
  };

  const addUrl = async () => {
    const normalizedUrl = normalizeUrl(newUrl);

    if (!normalizedUrl) {
      showToast("error", "Enter a website URL to monitor.");
      return;
    }

    if (!isValidUrl(normalizedUrl)) {
      showToast("error", "Enter a valid URL, for example https://example.com.");
      return;
    }

    try {
      setAdding(true);
      setError("");

      if (!API_BASE) {
        throw new Error("REACT_APP_API_BASE_URL is not configured");
      }

      const res = await apiFetch("/urls", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ url: normalizedUrl }),
      });

      const data = await res.json();

      if (!res.ok) {
        throw new Error(data.message || data.error || "Failed to add URL");
      }

      setNewUrl("");
      showToast("success", data.message || "URL added successfully.");
      fetchData();
    } catch (err) {
      console.error("Failed to add URL:", err);
      showToast("error", err.message || "Error adding URL.");
    } finally {
      setAdding(false);
    }
  };

  const deleteUrl = async (url) => {
    try {
      setDeletingUrl(url);
      setError("");

      if (!API_BASE) {
        throw new Error("REACT_APP_API_BASE_URL is not configured");
      }

      const res = await apiFetch("/urls", {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ url }),
      });

      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        throw new Error(data.message || data.error || "Failed to remove URL");
      }

      showToast("success", data.message || "URL removed successfully.");
      fetchData();
    } catch (err) {
      console.error("Failed to remove URL:", err);
      showToast("error", err.message || "Error removing URL.");
    } finally {
      setDeletingUrl("");
    }
  };

  const metrics = useMemo(() => {
    const upCount = status.filter((site) => site.is_up).length;
    const downCount = status.filter((site) => !site.is_up).length;

    const latencyValues = status
      .map((site) => Number(site.latency_ms))
      .filter((value) => Number.isFinite(value) && value >= 0);

    const avgLatency =
      latencyValues.length > 0
        ? Math.round(latencyValues.reduce((sum, value) => sum + value, 0) / latencyValues.length)
        : 0;

    const overallHealth =
      status.length === 0 ? "unknown" : downCount > 0 ? "degraded" : "healthy";

    return {
      upCount,
      downCount,
      avgLatency,
      totalCount: status.length,
      overallHealth,
    };
  }, [status]);

  const getStatusLabel = (site) => {
    if (!site) return "UNKNOWN";
    if (!site.is_up) return "DOWN";

    const latency = Number(site.latency_ms);
    if (Number.isFinite(latency) && latency > 1000) return "SLOW";

    return "UP";
  };

  const formatTime = (value) => {
    if (!value) return "Never";

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "Unknown";

    return date.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  };

  const formatDateTime = (value) => {
    if (!value) return "Never";

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "Unknown";

    return date.toLocaleString([], {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  return (
    <main className="app-shell">
      <section className="hero">
        <div>
          <div className="eyebrow">AWS Serverless Monitoring Console</div>
          <h1>CloudOps Uptime Monitor</h1>
          <p>
            Track website availability, latency, and downtime alerts using Lambda,
            EventBridge, DynamoDB, SNS, CloudWatch, and Terraform.
          </p>
        </div>

        <div className="hero-meta">
          <span className="pill pill-live">● Live</span>
          <span className={apiHealthy ? "pill pill-live" : "pill pill-danger"}>
            API: {apiHealthy ? "Online" : "Offline"}
          </span>
          <span className="pill">us-east-1</span>
          <span className="pill">UI refresh: 30s</span>
          <span className="pill">Checks: 5 min</span>
        </div>
      </section>

      {toast && <div className={`toast toast-${toast.type}`}>{toast.message}</div>}

      {error && (
        <section className="alert-banner">
          <div>
            <strong>Dashboard data unavailable</strong>
            <p>{error}</p>
          </div>
          <button className="secondary-button" onClick={fetchData}>
            Retry
          </button>
        </section>
      )}

      <section className="metrics-grid">
        <MetricCard
          label="Overall Health"
          value={
            metrics.overallHealth === "healthy"
              ? "Healthy"
              : metrics.overallHealth === "degraded"
                ? "Degraded"
                : "No Data"
          }
          tone={metrics.overallHealth}
          helper="Current monitored fleet state"
        />
        <MetricCard
          label="Sites Up"
          value={metrics.upCount}
          tone="healthy"
          helper="Passing latest check"
        />
        <MetricCard
          label="Sites Down"
          value={metrics.downCount}
          tone={metrics.downCount > 0 ? "degraded" : "neutral"}
          helper="Failing latest check"
        />
        <MetricCard
          label="Avg Latency"
          value={metrics.totalCount ? `${metrics.avgLatency}ms` : "—"}
          tone={metrics.avgLatency > 1000 ? "warning" : "neutral"}
          helper="Across latest checks"
        />
        <MetricCard
          label="Last Updated"
          value={lastUpdated ? formatTime(lastUpdated) : "—"}
          tone="neutral"
          helper="Dashboard refresh time"
        />
      </section>

      <section className="panel add-panel">
        <div className="panel-header">
          <div>
            <h2>Add Website</h2>
            <p>Add a URL to the monitored list. The next EventBridge cycle will check it.</p>
          </div>
        </div>

        <div className="url-form">
          <input
            value={newUrl}
            onChange={(e) => setNewUrl(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && addUrl()}
            placeholder="https://example.com"
            aria-label="Website URL"
          />
          <button onClick={addUrl} disabled={adding}>
            {adding ? "Adding..." : "Add URL"}
          </button>
        </div>
      </section>

      <section className="panel">
        <div className="panel-header">
          <div>
            <h2>Live Status</h2>
            <p>Latest check results stored in DynamoDB and displayed through API Gateway.</p>
          </div>
          <button className="secondary-button" onClick={fetchData}>
            Refresh
          </button>
        </div>

        {loading ? (
          <SkeletonTable />
        ) : status.length === 0 ? (
          <EmptyState
            title="No check results yet"
            message="Add a URL above or wait for the next scheduled EventBridge check."
          />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Status</th>
                  <th>URL</th>
                  <th>HTTP</th>
                  <th>Latency</th>
                  <th>Last Checked</th>
                </tr>
              </thead>
              <tbody>
                {status.map((site, index) => {
                  const label = getStatusLabel(site);

                  return (
                    <tr key={`${site.url}-${site.timestamp}-${index}`}>
                      <td>
                        <StatusBadge label={label} />
                      </td>
                      <td>
                        <div className="url-cell">
                          <span>{site.url}</span>
                        </div>
                      </td>
                      <td>{site.status_code || "—"}</td>
                      <td>{site.latency_ms ? `${site.latency_ms}ms` : "—"}</td>
                      <td>{formatDateTime(site.timestamp)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="panel">
        <div className="panel-header">
          <div>
            <h2>Monitored URLs</h2>
            <p>Websites currently registered for scheduled uptime checks.</p>
          </div>
          <span className="count-badge">{urls.length} total</span>
        </div>

        {urls.length === 0 ? (
          <EmptyState
            title="No monitored URLs"
            message="Add your first website to begin collecting uptime data."
          />
        ) : (
          <div className="url-list">
            {urls.map((url) => (
              <div className="url-list-item" key={url}>
                <div>
                  <span className="url-dot" />
                  <span>{url}</span>
                </div>
                <button
                  className="danger-button"
                  onClick={() => deleteUrl(url)}
                  disabled={deletingUrl === url}
                >
                  {deletingUrl === url ? "Removing..." : "Remove"}
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      <footer>
        Built with AWS Lambda · API Gateway · DynamoDB · EventBridge · SNS · CloudWatch · Terraform
      </footer>
    </main>
  );
}

function MetricCard({ label, value, helper, tone }) {
  return (
    <div className={`metric-card metric-${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      <p>{helper}</p>
    </div>
  );
}

function StatusBadge({ label }) {
  return <span className={`status-badge status-${label.toLowerCase()}`}>● {label}</span>;
}

function EmptyState({ title, message }) {
  return (
    <div className="empty-state">
      <strong>{title}</strong>
      <p>{message}</p>
    </div>
  );
}

function SkeletonTable() {
  return (
    <div className="skeleton-stack">
      <div className="skeleton-row" />
      <div className="skeleton-row" />
      <div className="skeleton-row" />
    </div>
  );
}

export default App;
