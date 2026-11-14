import ApiStatus from '../../components/common/ApiStatus'

function Home() {
  return (
    <div>
      <h1 className="text-3xl font-bold text-slate-800">Welcome to Smart Commerce</h1>
      <p className="mt-2 text-slate-600">
        Intelligent shopping and inventory management.
      </p>
      <ApiStatus />
    </div>
  )
}

export default Home