// ============================================================================
// CONTRATO API (front <-> Azure de Victor). Congelado: solo cambia VITE_API_URL.
// ----------------------------------------------------------------------------
// GET  {BASE}/api/lista
//   -> 200 [{ credito_id:int, cliente:str, departamento:str,
//             saldo_expuesto:float, dias_mora:int, bucket_riesgo:str,
//             cuotas_impagas:int, puntaje_riesgo:int, prioridad:float,
//             accion_recomendada:str, motivo_ia:str,
//             canal_contacto:str, fecha_gestion:str }]
//
// POST {BASE}/api/gestiones  { credito_id:int, resultado:str, fecha_compromiso:str|null, gestor:str }
//   resultado ∈ SE_COMPROMETE | NO_PUEDE_PAGAR | NO_CONTESTA | DERIVAR
//   -> 200 { ok:true } | 4xx/5xx { error:str }
//
// Sin VITE_API_URL se usa el mock local (src/mocks/lista.json) y el registro
// se guarda en localStorage. CORS debe permitir el dominio del front.
// ============================================================================
import mockLista from './mocks/lista.json'

const BASE = (import.meta.env.VITE_API_URL || '').replace(/\/$/, '')
const KEY = import.meta.env.VITE_API_KEY || ''

// La clave viaja en cabecera x-api-key (Parameter Store del lado de Victor).
// Si no hay clave configurada, se omite la cabecera.
const headers = { 'Content-Type': 'application/json', ...(KEY ? { 'x-api-key': KEY } : {}) }

const delay = (ms) => new Promise((r) => setTimeout(r, ms))

export async function getLista() {
  if (!BASE) {
    await delay(250)
    return mockLista
  }
  const r = await fetch(`${BASE}/api/lista`)
  if (!r.ok) throw new Error(`GET /api/lista -> ${r.status}`)
  return r.json()
}

export async function registrarGestion({ credito_id, resultado, fecha_compromiso, gestor }) {
  const payload = { credito_id, resultado, fecha_compromiso: fecha_compromiso || null, gestor }
  if (!BASE) {
    await delay(250)
    const key = 'gestiones_mock'
    const prev = JSON.parse(localStorage.getItem(key) || '[]')
    prev.push({ ...payload, fecha_registro: new Date().toISOString() })
    localStorage.setItem(key, JSON.stringify(prev))
    return { ok: true, mock: true }
  }
  const r = await fetch(`${BASE}/api/gestiones`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  })
  if (!r.ok) {
    const err = await r.json().catch(() => ({}))
    throw new Error(err.error || `POST /api/gestiones -> ${r.status}`)
  }
  return r.json()
}

export const MODO = BASE ? 'azure' : 'mock'
export const API_BASE = BASE
