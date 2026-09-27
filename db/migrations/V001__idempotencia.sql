-- =============================================================================
-- V001__idempotencia.sql — Tabla de idempotencia + transferencia idempotente
-- Corrección #2 de la revisión: el UNIQUE (canal_id, idempotency_key) sobre la
-- tabla particionada core.transacciones es ilegal en PostgreSQL (toda restricción
-- única en tabla particionada debe incluir la columna de partición). Se reemplaza
-- por una tabla dedicada core.idempotencia con PK (canal_id, idempotency_key).
-- El procedimiento pasa a ser función que devuelve el transaccion_id: si la clave
-- ya existe, no crea una segunda operación y devuelve la original (idempotencia
-- real, demostrable en vivo).
-- Aplica sobre: structura.sql (master v12).
-- =============================================================================

ALTER TABLE core.transacciones DROP CONSTRAINT IF EXISTS uq_transaccion_idempotency;

CREATE TABLE core.idempotencia (
    canal_id         INT NOT NULL REFERENCES reference.canales(canal_id),
    idempotency_key  VARCHAR(64) NOT NULL,
    transaccion_id   BIGINT NOT NULL,
    fecha_transaccion TIMESTAMPTZ NOT NULL,
    creado_en        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (canal_id, idempotency_key)
);

DROP PROCEDURE IF EXISTS core.sp_transferir_dinero(BIGINT, BIGINT, NUMERIC, INT, INT, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION core.sp_transferir_dinero(
    IN p_cuenta_origen BIGINT,
    IN p_cuenta_destino BIGINT,
    IN p_monto NUMERIC(15,2),
    IN p_canal_id INT,
    IN p_sucursal_id INT,
    IN p_idempotency_key VARCHAR(64),
    IN p_moneda VARCHAR(3)
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
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
    IF v_saldo_origen IS NULL THEN
        RAISE EXCEPTION 'CUENTA_ORIGEN_INEXISTENTE: %', p_cuenta_origen;
    END IF;
    IF v_saldo_origen < p_monto THEN
        RAISE EXCEPTION 'SALDO_INSUFICIENTE: Saldo disponible (%) es menor al monto solicitado (%)', v_saldo_origen, p_monto;
    END IF;

    -- 3. Si la clave ya se procesó, devolver la transacción ORIGINAL
    --    sin crear una nueva (replay idempotente, sin efectos).
    SELECT i.transaccion_id INTO v_tx_id FROM core.idempotencia i
    WHERE i.canal_id = p_canal_id AND i.idempotency_key = p_idempotency_key;
    IF FOUND THEN
        RETURN v_tx_id;
    END IF;

    -- 4. Registrar Transacción
    INSERT INTO core.transacciones (cuenta_origen_id, cuenta_destino_id, canal_id, sucursal_id, tipo_transaccion, monto, moneda_id, idempotency_key)
    VALUES (p_cuenta_origen, p_cuenta_destino, p_canal_id, p_sucursal_id, 'TRANSFERENCIA', p_monto, p_moneda, p_idempotency_key)
    RETURNING transaccion_id INTO v_tx_id;

    -- 5. Registrar idempotencia. El UNIQUE cubre la carrera entre dos
    --    llamadas concurrentes con la misma clave: la perdedora borra su
    --    fila huérfana y devuelve la original.
    BEGIN
        INSERT INTO core.idempotencia (canal_id, idempotency_key, transaccion_id, fecha_transaccion)
        VALUES (p_canal_id, p_idempotency_key, v_tx_id, now());
    EXCEPTION WHEN unique_violation THEN
        DELETE FROM core.transacciones WHERE transaccion_id = v_tx_id;
        SELECT i.transaccion_id INTO v_tx_id FROM core.idempotencia i
        WHERE i.canal_id = p_canal_id AND i.idempotency_key = p_idempotency_key;
        RETURN v_tx_id;
    END;

    -- 6. Inserción en Ledger Contable (Doble Partida)
    INSERT INTO core.movimientos_contables (transaccion_id, cuenta_id, tipo_movimiento, monto)
    VALUES (v_tx_id, p_cuenta_origen, 'DEBITO', p_monto);

    INSERT INTO core.movimientos_contables (transaccion_id, cuenta_id, tipo_movimiento, monto)
    VALUES (v_tx_id, p_cuenta_destino, 'CREDITO', p_monto);

    -- 7. Actualizar Saldos de forma atómica
    UPDATE core.cuentas SET saldo_actual = saldo_actual - p_monto, saldo_disponible = saldo_disponible - p_monto WHERE cuenta_id = p_cuenta_origen;
    UPDATE core.cuentas SET saldo_actual = saldo_actual + p_monto, saldo_disponible = saldo_disponible + p_monto WHERE cuenta_id = p_cuenta_destino;

    RETURN v_tx_id;
END; $$;
