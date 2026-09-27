# Migraciones BancoCloud (v12 → v13)

Dos caminos de instalación, mismo estado final:

1. **Base nueva (demo/exposición):** aplicar `db/master/bancocloud_master_v13.sql` una sola vez.
2. **Base v12 existente:** aplicar en orden `V001` → `V005` (cada una con `psql -v ON_ERROR_STOP=1 -f`).

Cada migración tiene su reversa `V00X__*.down.sql` (orden inverso para revertir).

| Archivo | Qué hace |
|---|---|
| V001__idempotencia | Tabla `core.idempotencia` + transferencia idempotente (función que devuelve el tx original). Elimina el UNIQUE ilegal sobre la tabla particionada. |
| V002__catalogos_seed | Semilla idempotente: 2 monedas, 7 canales, 10 sucursales (una DIGITAL), 11 productos. |
| V003__columnas_negocio | `reference.tipos_transaccion` + FK; `transacciones.comision`; `clientes.segmento_cliente`; `cuentas.saldo_inicial`; `tarjetas.saldo_disponible`. |
| V004__rls | RLS completo: SELECT propio en clientes; SELECT/INSERT/UPDATE propios en cuentas y transacciones (USING + WITH CHECK). |
| V005__particiones_demo | Particiones mensuales oct-2025 → ago-2026 (la ventana demo de 12 meses). |

Verificación rápida tras migrar:

```bash
psql -d bancocloud -v ON_ERROR_STOP=1 -f db/migrations/V001__idempotencia.sql
# ... V002 ... V005
psql -d bancocloud -c "SELECT count(*) FROM reference.canales;"  # 7
```
