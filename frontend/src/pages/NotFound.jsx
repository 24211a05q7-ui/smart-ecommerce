import { Link } from 'react-router-dom'

function NotFound() {
  return (
    <div className="text-center">
      <h1 className="text-4xl font-bold text-slate-800">404</h1>
      <p className="mt-2 text-slate-600">This page does not exist.</p>
      <Link to="/" className="mt-4 inline-block text-indigo-600 hover:underline">
        Back to Home
      </Link>
    </div>
  )
}

export default NotFound