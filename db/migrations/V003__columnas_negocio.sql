-- =============================================================================
-- V003__columnas_negocio.sql — Columnas que exige la revisión
-- - reference.tipos_transaccion: catálogo de tipos de operación (corrección #3).
--   requiere_destino = solo las transferencias llevan cuenta destino.
-- - core.transacciones.comision: ingreso con el que se calcula rentabilidad
--   por producto (informativa; el ledger mueve el monto en 2 asientos).
-- - core.clientes.segmento_cliente: MASIVO / PREFERENTE / PATRIMONIAL,
--   derivado del saldo promedio (rentabilidad por segmento).
-- - core.cuentas.saldo_inicial: apertura contable; el saldo final verifica
--   como saldo_inicial + créditos − débitos del ledger.
-- - core.tarjetas.saldo_disponible: las tarjetas de crédito quedan modeladas
--   con línea, usado, disponible, corte y pago (distinto de débito).
-- =============================================================================

CREATE TABLE reference.tipos_transaccion (
    codigo VARCHAR(30) PRIMARY KEY,
    descripcion TEXT NOT NULL,
    requiere_destino BOOLEAN NOT NULL
);

INSERT INTO reference.tipos_transaccion (codigo, descripcion, requiere_destino) VALUES
('TRANSFERENCIA', 'Transferencia entre cuentas propias o de terceros', true),
('TRANSFERENCIA_PLIN', 'Transferencia inmediata billetera Plin', true),
('DEPOSITO', 'Deposito en efectivo o ventanilla', false),
('RETIRO', 'Retiro de efectivo (ATM o ventanilla)', false),
('COMPRA_POS', 'Compra con tarjeta en comercio POS', false),
('PAGO_QR', 'Pago con QR interoperable', false);

ALTER TABLE core.transacciones
    ADD COLUMN comision NUMERIC(15,2) NOT NULL DEFAULT 0.00;
ALTER TABLE core.transacciones
    ADD CONSTRAINT fk_transacciones_tipo_transaccion
    FOREIGN KEY (tipo_transaccion) REFERENCES reference.tipos_transaccion(codigo);

ALTER TABLE core.clientes
    ADD COLUMN segmento_cliente VARCHAR(20) NOT NULL DEFAULT 'MASIVO'
    CHECK (segmento_cliente IN ('MASIVO', 'PREFERENTE', 'PATRIMONIAL'));

ALTER TABLE core.cuentas
    ADD COLUMN saldo_inicial NUMERIC(15,2) NOT NULL DEFAULT 0.00;

ALTER TABLE core.tarjetas
    ADD COLUMN saldo_disponible NUMERIC(15,2) NOT NULL DEFAULT 0.00;
