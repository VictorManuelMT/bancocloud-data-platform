-- =============================================================================
-- V001__idempotencia.down.sql — Reversa de V001 (vuelve al procedimiento v12)
-- =============================================================================

DROP FUNCTION IF EXISTS core.sp_transferir_dinero(BIGINT, BIGINT, NUMERIC, INT, INT, VARCHAR, VARCHAR);

DROP TABLE IF EXISTS core.idempotencia;

ALTER TABLE core.transacciones DROP CONSTRAINT IF EXISTS uq_transaccion_idempotency;
ALTER TABLE core.transacciones
    ADD CONSTRAINT uq_transaccion_idempotency UNIQUE (canal_id, idempotency_key, fecha_transaccion);

CREATE OR REPLACE PROCEDURE core.sp_transferir_dinero(
    IN p_cuenta_origen BIGINT,
    IN p_cuenta_destino BIGINT,
    IN p_monto NUMERIC(15,2),
    IN p_canal_id INT,
    IN p_sucursal_id INT,
    IN p_idempotency_key VARCHAR(64),
    IN p_moneda VARCHAR(3)
) LANGUAGE plpgsql AS $$
DECLARE
    v_saldo_origen NUMERIC(15,2);
    v_tx_id BIGINT;
BEGIN
    -- 1. Bloqueo ordenado preventivo de Deadlocks por ID menor
    IF p_cuenta_origen < p_cuenta_destino THEN
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_origen FOR UPDATE;
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_destino FOR UPDATE;
    ELSE
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_destino FOR UPDATE;
        PERFORM 1 FROM core.cuentas WHERE cuenta_id = p_cuenta_origen FOR UPDATE;
    END IF;

    -- 2. Validar Saldo Disponible
    SELECT saldo_disponible INTO v_saldo_origen FROM core.cuentas WHERE cuenta_id = p_cuenta_origen;
    IF v_saldo_origen < p_monto THEN
        RAISE EXCEPTION 'SALDO_INSUFICIENTE: Saldo disponible (%) es menor al monto solicitado (%)', v_saldo_origen, p_monto;
    END IF;

    -- 3. Registrar Transacción
    INSERT INTO core.transacciones (cuenta_origen_id, cuenta_destino_id, canal_id, sucursal_id, tipo_transaccion, monto, moneda_id, idempotency_key)
    VALUES (p_cuenta_origen, p_cuenta_destino, p_canal_id, p_sucursal_id, 'TRANSFERENCIA', p_monto, p_moneda, p_idempotency_key)
    RETURNING transaccion_id INTO v_tx_id;

    -- 4. Inserción en Ledger Contable (Doble Partida)
    INSERT INTO core.movimientos_contables (transaccion_id, cuenta_id, tipo_movimiento, monto)
    VALUES (v_tx_id, p_cuenta_origen, 'DEBITO', p_monto);

    INSERT INTO core.movimientos_contables (transaccion_id, cuenta_id, tipo_movimiento, monto)
    VALUES (v_tx_id, p_cuenta_destino, 'CREDITO', p_monto);

    -- 5. Actualizar Saldos de forma atómica
    UPDATE core.cuentas SET saldo_actual = saldo_actual - p_monto, saldo_disponible = saldo_disponible - p_monto WHERE cuenta_id = p_cuenta_origen;
    UPDATE core.cuentas SET saldo_actual = saldo_actual + p_monto, saldo_disponible = saldo_disponible + p_monto WHERE cuenta_id = p_cuenta_destino;

    COMMIT;
END; $$;
