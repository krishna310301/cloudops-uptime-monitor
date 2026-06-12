import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

process.env.REACT_APP_API_BASE_URL = "https://api.example.com/prod";
process.env.REACT_APP_API_KEY = "test-dashboard-key";

const App = require("./App").default;

const jsonResponse = (body, ok = true) =>
  Promise.resolve({
    ok,
    json: () => Promise.resolve(body),
  });

afterEach(() => {
  jest.restoreAllMocks();
});

test("renders live dashboard data from API", async () => {
  global.fetch = jest
    .fn()
    .mockResolvedValueOnce(jsonResponse({
      results: [{
        url: "https://example.com",
        timestamp: "2026-06-12T12:00:00Z",
        status_code: 200,
        latency_ms: 82,
        is_up: true,
      }],
    }))
    .mockResolvedValueOnce(jsonResponse({ urls: ["https://example.com"] }));

  render(<App />);

  expect(await screen.findAllByText("https://example.com")).toHaveLength(2);
  expect(screen.getAllByText("82ms")).toHaveLength(2);
  expect(screen.getByText("Healthy")).toBeInTheDocument();
});

test("sends API key header with dashboard requests", async () => {
  global.fetch = jest
    .fn()
    .mockResolvedValueOnce(jsonResponse({ results: [] }))
    .mockResolvedValueOnce(jsonResponse({ urls: [] }));

  render(<App />);

  await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(2));
  expect(global.fetch).toHaveBeenCalledWith(
    "https://api.example.com/prod/status",
    expect.objectContaining({
      headers: expect.objectContaining({ "X-Api-Key": "test-dashboard-key" }),
    })
  );
});

test("shows API failure state", async () => {
  jest.spyOn(console, "error").mockImplementation(() => {});
  global.fetch = jest.fn().mockResolvedValue(jsonResponse({}, false));

  render(<App />);

  expect(await screen.findByText("Dashboard data unavailable")).toBeInTheDocument();
  expect(screen.getByText(/Unable to load monitoring data/)).toBeInTheDocument();
});

test("rejects invalid URL before calling add endpoint", async () => {
  global.fetch = jest
    .fn()
    .mockResolvedValueOnce(jsonResponse({ results: [] }))
    .mockResolvedValueOnce(jsonResponse({ urls: [] }));

  render(<App />);

  await screen.findByText("No check results yet");
  await userEvent.type(screen.getByLabelText("Website URL"), "not a url");
  await userEvent.click(screen.getByText("Add URL"));

  expect(screen.getByText(/Enter a valid URL/)).toBeInTheDocument();
  expect(global.fetch).toHaveBeenCalledTimes(2);
});
