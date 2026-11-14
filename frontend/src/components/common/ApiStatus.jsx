import { useEffect, useState } from 'react'
import { getServerHealth, getDatabaseHealth } from '../../api/health'

function StatusRow({ label, state }) {
  const styles = {
    loading: 'bg-slate-100 text-slate-600',
    ok: 'bg-green-100 text-green-700',
    error: 'bg-red-100 text-red-700',
  }

  const text = {
    loading: 'Checking...',
    ok: state.message ? `Connected (${state.message})` : 'Connected',
    error: `Failed: ${state.message}`,
  }

  return (
    <div className="flex items-center justify-between gap-4">
      <span className="font-medium text-slate-700">{label}</span>
      <span className={`px-3 py-1 rounded-full text-sm ${styles[state.status]}`}>
        {text[state.status]}
      </span>
    </div>
  )
}

function ApiStatus() {
  const [server, setServer] = useState({ status: 'loading' })
  const [database, setDatabase] = useState({ status: 'loading' })

  useEffect(() => {
    // Lets us cancel the requests if the component disappears mid-request.
    const controller = new AbortController()
    const { signal } = controller

    getServerHealth(signal)
      .then(() => setServer({ status: 'ok' }))
      .catch((err) => {
        if (err.name !== 'AbortError') setServer({ status: 'error', message: err.message })
      })

    getDatabaseHealth(signal)
      .then((data) => setDatabase({ status: 'ok', message: data.database }))
      .catch((err) => {
        if (err.name !== 'AbortError') setDatabase({ status: 'error', message: err.message })
      })

    return () => controller.abort()
  }, [])

  return (
    <div className="mt-8 max-w-md bg-white rounded-xl shadow p-6 space-y-3">
      <h2 className="text-lg font-semibold text-slate-800">System status (temporary)</h2>
      <StatusRow label="API server" state={server} />
      <StatusRow label="Database" state={database} />
    </div>
  )
}

export default ApiStatus