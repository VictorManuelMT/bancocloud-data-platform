import { useEffect, useMemo, useState } from 'react'
import { API_BASE, MODO, getLista, registrarGestion } from './api.js'
import cuarentena from './mocks/cuarentena.json'

const RESULTADOS = [
  { id: 'SE_COMPROMETE', label: 'Se compromete', color: 'bg-emerald-600 hover:bg-emerald-700' },
  { id: 'NO_PUEDE_PAGAR', label: 'No puede pagar', color: 'bg-amber-600 hover:bg-amber-700' },
  { id: 'NO_CONTESTA', label: 'No contesta', color: 'bg-slate-500 hover:bg-slate-600' },
  { id: 'DERIVAR', label: 'No corresponde (derivar)', color: 'bg-red-600 hover:bg-red-700' },
]

function fmt(n) {
  return 'S/ ' + Number(n).toLocaleString('es-PE', { minimumFractionDigits: 2 })
}

export default function App() {
  const [lista, setLista] = useState([])
  const [error, setError] = useState('')
  const [q, setQ] = useState('')
  const [sel, setSel] = useState(null)
  const [gestor, setGestor] = useState('')
  const [fechaComp, setFechaComp] = useState('')
  const [msg, setMsg] = useState('')
  const [hechas, setHechas] = useState({})
  const [tab, setTab] = useState('lista')

  useEffect(() => {
    getLista().then(setLista).catch((e) => setError(String(e.message || e)))
  }, [])

  const filtrada = useMemo(() => {
    const t = q.trim().toLowerCase()
    if (!t) return lista
    return lista.filter(
      (x) => x.cliente.toLowerCase().includes(t) || String(x.credito_id).includes(t),
    )
  }, [lista, q])

  async function onResultado(res) {
    if (!sel) return
    if (!gestor.trim()) {
      setMsg('Escribe tu correo de gestor antes de registrar.')
      return
    }
    if (res === 'SE_COMPROMETE' && !fechaComp) {
      setMsg('Elige la fecha de compromiso para registrar.')
      return
    }
    try {
      await registrarGestion({
        credito_id: sel.credito_id,
        resultado: res,
        fecha_compromiso: res === 'SE_COMPROMETE' ? fechaComp : null,
        gestor: gestor.trim(),
      })
      setHechas((h) => ({ ...h, [sel.credito_id]: res }))
      setMsg(`Registrado: ${res}${MODO === 'mock' ? ' (mock local)' : ''}`)
    } catch (e) {
      setMsg(`Error: ${e.message}`)
    }
  }

  return (
    <div className="min-h-screen bg-slate-100 text-slate-900">
      <header className="bg-indigo-950 text-white px-4 py-3 flex items-center gap-3 sticky top-0 z-10">
        <div className="font-bold text-lg">BancoCloud · Cobranza de hoy</div>
        <span className="text-xs bg-white/15 rounded px-2 py-0.5">
          {MODO === 'mock' ? 'MOCK local' : API_BASE}
        </span>
        <span className="ml-auto text-sm">{filtrada.length} casos</span>
      </header>

      {error && <div className="m-3 p-3 bg-red-100 text-red-800 rounded">{error}</div>}
      {msg && <div className="m-3 p-3 bg-emerald-100 text-emerald-900 rounded">{msg}</div>}

      <div className="p-3 max-w-6xl mx-auto">
        <div className="flex gap-2 mb-3">
          <button
            onClick={() => setTab('lista')}
            className={`px-4 py-2 rounded font-semibold text-sm ${tab === 'lista' ? 'bg-indigo-950 text-white' : 'bg-white'}`}
          >
            Por contactar ({filtrada.length})
          </button>
          <button
            onClick={() => setTab('cuarentena')}
            className={`px-4 py-2 rounded font-semibold text-sm ${tab === 'cuarentena' ? 'bg-red-800 text-white' : 'bg-white'}`}
          >
            No contactar · dato en revisión ({cuarentena.length})
          </button>
        </div>

        {tab === 'cuarentena' ? (
          <div className="bg-red-50 border border-red-200 rounded-lg p-4">
            <p className="text-sm text-red-900 mb-3">
              Estos {cuarentena.length} créditos no están en la lista de hoy. No porque estén al día,
              sino porque su dato no pasó los controles. El banco prefiere no llamar antes que llamar mal.
            </p>
            <div className="grid gap-2">
              {cuarentena.map((x) => (
                <div key={x.credito_id} className="bg-white rounded p-3 text-sm">
                  <div className="flex justify-between gap-2">
                    <span className="font-semibold">{x.cliente}</span>
                    <span className="font-bold">{fmt(x.saldo_expuesto)}</span>
                  </div>
                  <div className="text-slate-600">
                    Crédito {x.credito_id} · {x.tipo_error} → {x.regla}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : (
        <div className="grid gap-3 md:grid-cols-[1fr_380px]">
        <section>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por nombre o crédito…"
            className="w-full p-2.5 rounded border border-slate-300 mb-3"
          />
          <div className="grid gap-2">
            {filtrada.map((x) => (
              <button
                key={x.credito_id}
                onClick={() => { setSel(x); setMsg('') }}
                className={`text-left bg-white rounded-lg p-3 shadow-sm border-2 ${
                  sel?.credito_id === x.credito_id ? 'border-indigo-600' : 'border-transparent'
                }`}
              >
                <div className="flex justify-between gap-2">
                  <div className="font-semibold">{x.cliente}</div>
                  <div className="font-bold text-indigo-900">{fmt(x.saldo_expuesto)}</div>
                </div>
                <div className="text-sm text-slate-600">
                  Crédito {x.credito_id} · {x.dias_mora} días mora · {x.bucket_riesgo} · {x.departamento}
                </div>
                <div className="text-sm mt-1">
                  <span className="font-semibold text-orange-700">Puntaje {x.puntaje_riesgo}</span>
                  {' · '}{x.accion_recomendada}
                  {hechas[x.credito_id] && (
                    <span className="ml-2 text-xs bg-slate-200 rounded px-1.5 py-0.5">
                      {hechas[x.credito_id]}
                    </span>
                  )}
                </div>
              </button>
            ))}
          </div>
        </section>

        <aside className="bg-white rounded-lg p-4 shadow-sm h-fit md:sticky md:top-16">
          {!sel ? (
            <p className="text-slate-500">Toca un caso para ver el detalle.</p>
          ) : (
            <>
              <h2 className="font-bold text-lg">{sel.cliente}</h2>
              <dl className="text-sm mt-2 space-y-1">
                <div className="flex justify-between"><dt>Crédito</dt><dd className="font-mono">{sel.credito_id}</dd></div>
                <div className="flex justify-between"><dt>Saldo expuesto</dt><dd className="font-bold">{fmt(sel.saldo_expuesto)}</dd></div>
                <div className="flex justify-between"><dt>Días mora</dt><dd>{sel.dias_mora}</dd></div>
                <div className="flex justify-between"><dt>Cuotas impagas</dt><dd>{sel.cuotas_impagas}</dd></div>
                <div className="flex justify-between"><dt>Acción</dt><dd>{sel.accion_recomendada}</dd></div>
              </dl>
              {sel.motivo_ia && (
                <p className="text-sm mt-3 p-2 bg-amber-50 border border-amber-200 rounded">
                  <span className="font-semibold">Nota IA ({sel.canal_contacto}): </span>{sel.motivo_ia}
                </p>
              )}
              <input
                value={gestor}
                onChange={(e) => setGestor(e.target.value)}
                placeholder="tu.correo@universidad.edu"
                className="w-full mt-3 p-2 rounded border border-slate-300 text-sm"
              />
              <input
                type="date"
                value={fechaComp}
                onChange={(e) => setFechaComp(e.target.value)}
                className="w-full mt-2 p-2 rounded border border-slate-300 text-sm"
              />
              <div className="grid grid-cols-2 gap-2 mt-3">
                {RESULTADOS.map((r) => (
                  <button
                    key={r.id}
                    onClick={() => onResultado(r.id)}
                    className={`${r.color} text-white text-sm font-semibold rounded p-2.5`}
                  >
                    {r.label}
                  </button>
                ))}
              </div>
            </>
          )}
        </aside>
        </div>
        )}
      </div>
    </div>
  )
}
