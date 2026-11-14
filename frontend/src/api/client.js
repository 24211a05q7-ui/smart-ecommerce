const API_URL = import.meta.env.VITE_API_URL

// Sends a GET request to our API and returns the parsed JSON.
// Throws an Error if the server answers with a failure status (4xx/5xx).
export async function apiGet(path, options = {}) {
  const response = await fetch(`${API_URL}${path}`, options)

  // If the body isn't valid JSON, fall back to null instead of crashing.
  const data = await response.json().catch(() => null)

  if (!response.ok) {
    const error = new Error(data?.message || `Request failed with status ${response.status}`)
    error.status = response.status
    throw error
  }

  return data
}