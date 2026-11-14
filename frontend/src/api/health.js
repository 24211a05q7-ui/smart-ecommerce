import { apiGet } from './client'

export const getServerHealth = (signal) => apiGet('/health', { signal })
export const getDatabaseHealth = (signal) => apiGet('/health/db', { signal })