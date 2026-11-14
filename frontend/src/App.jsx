import { Routes, Route } from 'react-router-dom'
import Navbar from './components/layout/Navbar'
import Home from './pages/customer/Home'
import ProductList from './pages/customer/ProductList'
import NotFound from './pages/NotFound'

function App() {
  return (
    <div className="min-h-screen bg-slate-100">
      <Navbar />
      <main className="max-w-6xl mx-auto px-4 py-8">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/products" element={<ProductList />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </main>
    </div>
  )
}

export default App