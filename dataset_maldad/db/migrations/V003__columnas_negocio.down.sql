-- =============================================================================
-- V003__columnas_negocio.down.sql — Reversa de V003
-- =============================================================================

ALTER TABLE core.tarjetas DROP COLUMN IF EXISTS saldo_disponible;
ALTER TABLE core.cuentas DROP COLUMN IF EXISTS saldo_inicial;
ALTER TABLE core.clientes DROP COLUMN IF EXISTS segmento_cliente;
ALTER TABLE core.transacciones DROP CONSTRAINT IF EXISTS fk_transacciones_tipo_transaccion;
ALTER TABLE core.transacciones DROP COLUMN IF EXISTS comision;
DROP TABLE IF EXISTS reference.tipos_transaccion;
