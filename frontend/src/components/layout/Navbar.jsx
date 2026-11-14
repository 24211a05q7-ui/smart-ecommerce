import { NavLink } from 'react-router-dom'

// Classes change depending on whether the link matches the current URL.
const linkClass = ({ isActive }) =>
  isActive
    ? 'text-indigo-600 font-semibold'
    : 'text-slate-600 hover:text-indigo-600'

function Navbar() {
  return (
    <header className="bg-white shadow-sm">
      <nav className="max-w-6xl mx-auto px-4 py-4 flex items-center justify-between">
        <span className="text-xl font-bold text-indigo-600">Smart Commerce</span>

        <div className="flex gap-6">
          <NavLink to="/" end className={linkClass}>
            Home
          </NavLink>
          <NavLink to="/products" className={linkClass}>
            Products
          </NavLink>
        </div>
      </nav>
    </header>
  )
}

export default Navbar